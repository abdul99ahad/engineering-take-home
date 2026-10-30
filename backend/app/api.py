from collections.abc import Sequence
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app import audit, sharing
from app.auth import User, current_clinician, current_patient, current_user
from app.db import get_db
from app.metrics import APP_EVENTS, CLINICIAN_READS, SHARES_CREATED, SHARES_REVOKED
from app.models import AccessLog, Clinician, DiaryEntry, Patient, Share
from app.schemas import (
    AccessLogOut,
    ClinicianEntryOut,
    ClinicianOut,
    EntryIn,
    EntryOut,
    Me,
    ShareIn,
    ShareOut,
    TelemetryEvent,
)

router = APIRouter()

Db = Annotated[Session, Depends(get_db)]
AnyUser = Annotated[User, Depends(current_user)]
PatientUser = Annotated[User, Depends(current_patient)]
ClinicianUser = Annotated[User, Depends(current_clinician)]


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/me", response_model=Me)
def me(user: AnyUser) -> User:
    return user


@router.get("/clinicians", response_model=list[ClinicianOut])
def list_clinicians(_: AnyUser, db: Db) -> Sequence[Clinician]:
    return db.scalars(select(Clinician).order_by(Clinician.name)).all()


@router.get("/entries", response_model=list[EntryOut])
def list_entries(user: PatientUser, db: Db) -> Sequence[DiaryEntry]:
    query = (
        select(DiaryEntry)
        .where(DiaryEntry.patient_id == user.id)
        .order_by(DiaryEntry.recorded_at.desc())
    )
    return db.scalars(query).all()


@router.post("/entries", response_model=EntryOut, status_code=201)
def create_entry(body: EntryIn, user: PatientUser, db: Db) -> DiaryEntry:
    entry = DiaryEntry(patient_id=user.id, **body.model_dump())
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.post("/shares", response_model=ShareOut, status_code=201)
def create_share(body: ShareIn, user: PatientUser, db: Db) -> Share:
    if db.get(Clinician, body.clinician_id) is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Unknown clinician")
    share = Share(patient_id=user.id, consent_version=sharing.CONSENT_VERSION, **body.model_dump())
    db.add(share)
    db.commit()
    db.refresh(share)
    SHARES_CREATED.inc()
    return share


@router.get("/shares", response_model=list[ShareOut])
def list_shares(user: PatientUser, db: Db) -> Sequence[Share]:
    query = (
        select(Share)
        .where(Share.patient_id == user.id)
        .order_by(Share.created_at.desc(), Share.id.desc())
    )
    return db.scalars(query).all()


@router.post("/shares/{share_id}/revoke", response_model=ShareOut)
def revoke_share(share_id: int, user: PatientUser, db: Db) -> Share:
    share = db.scalar(select(Share).where(Share.id == share_id, Share.patient_id == user.id))
    if share is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    if share.revoked_at is None:
        share.revoked_at = func.now()
        db.commit()
        db.refresh(share)
        SHARES_REVOKED.inc()
    return share


@router.get("/access-log", response_model=list[AccessLogOut])
def access_log(user: PatientUser, db: Db) -> list[AccessLogOut]:
    query = (
        select(AccessLog, Clinician.name)
        .join(Clinician, Clinician.id == AccessLog.clinician_id)
        .where(AccessLog.patient_id == user.id)
        .order_by(AccessLog.accessed_at.desc(), AccessLog.id.desc())
    )
    return [
        AccessLogOut(
            clinician_id=record.clinician_id,
            clinician_name=name,
            accessed_at=record.accessed_at,
            entry_ids=record.entry_ids,
        )
        for record, name in db.execute(query).tuples()
    ]


@router.get("/clinician/patients/{patient_id}/entries", response_model=list[ClinicianEntryOut])
def clinician_entries(patient_id: int, user: ClinicianUser, db: Db) -> list[ClinicianEntryOut]:
    outcome = "error"  # anything unexpected below counts as an error
    try:
        # Consent is checked on every read, so a revocation applies to the next one (O.Cons_2).
        shares = db.scalars(
            select(Share).where(
                Share.patient_id == patient_id,
                Share.clinician_id == user.id,
                Share.revoked_at.is_(None),
            )
        ).all()
        if not shares:
            # Same answer whether or not the person is a patient: never reveal who is one.
            outcome = "not_found"
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")

        tz = ZoneInfo(db.get_one(Patient, patient_id).timezone)
        entries = db.scalars(select(DiaryEntry).where(DiaryEntry.patient_id == patient_id)).all()
        visible = [
            ClinicianEntryOut(
                id=entry.id,
                # The real moment, so app-v1 entries show on the right day for the doctor too.
                recorded_at=sharing.true_recorded_at(entry.recorded_at, entry.source, tz),
                mood=entry.mood,
                symptoms=entry.symptoms,
                note=entry.note if show_note else None,
            )
            for entry, show_note in sharing.visible_entries(entries, shares, tz)
        ]
        # Sorted by the real moment, not the stored one, so app-v1 entries fall into place.
        visible.sort(key=lambda entry: (entry.recorded_at, entry.id), reverse=True)

        # Recorded in the same transaction as the read: no record, no data (O.Log_1, O.Mon_1).
        try:
            audit.record_access(
                db,
                patient_id,
                user.id,
                entry_ids=[entry.id for entry in visible],
                note_entry_ids=[entry.id for entry in visible if entry.note is not None],
            )
            db.commit()
        except SQLAlchemyError:
            db.rollback()
            outcome = "audit_failed"
            raise

        outcome = "ok"
        return visible
    finally:
        CLINICIAN_READS.labels(outcome).inc()


@router.post("/telemetry", status_code=204)
def telemetry(body: TelemetryEvent, _: AnyUser) -> Response:
    APP_EVENTS.labels(body.event).inc()
    return Response(status_code=204)
