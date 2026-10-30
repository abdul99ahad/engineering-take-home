from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    false,
    func,
)
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Patient(Base):
    __tablename__ = "patients"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    email: Mapped[str] = mapped_column(String(320), unique=True)
    timezone: Mapped[str] = mapped_column(String(64))  # IANA name, e.g. "Europe/Berlin"
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Clinician(Base):
    __tablename__ = "clinicians"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    practice: Mapped[str] = mapped_column(String(200))


class DiaryEntry(Base):
    __tablename__ = "diary_entries"
    __table_args__ = (CheckConstraint("mood BETWEEN 1 AND 5", name="mood_range"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    mood: Mapped[int]
    symptoms: Mapped[list[str]] = mapped_column(ARRAY(Text), default=list)
    note: Mapped[str | None] = mapped_column(Text)
    # "app-v1" entries were sent without a time zone and stored as if they were UTC.
    source: Mapped[str] = mapped_column(String(16), server_default="app-v2")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Share(Base):
    """A patient's consent for one doctor to read a period of their diary."""

    __tablename__ = "shares"
    __table_args__ = (Index("ix_shares_clinician_patient", "clinician_id", "patient_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    clinician_id: Mapped[int] = mapped_column(ForeignKey("clinicians.id"))
    # Inclusive calendar days as the patient sees them in their own time zone.
    from_date: Mapped[date]
    to_date: Mapped[date]
    include_notes: Mapped[bool] = mapped_column(server_default=false())
    # The consent text the patient agreed to (O.Cons_3).
    consent_version: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AccessLog(Base):
    """One row per doctor read (O.Log_1). Append-only: a trigger rejects UPDATE and DELETE.

    patient_id and entry_ids have no foreign keys, so erasing a patient's diary is never blocked
    by, and never cascades into, the audit trail.
    """

    __tablename__ = "access_log"

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(index=True)
    clinician_id: Mapped[int] = mapped_column(ForeignKey("clinicians.id"))
    accessed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    entry_ids: Mapped[list[int]] = mapped_column(ARRAY(Integer))
