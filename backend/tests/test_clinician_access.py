"""A doctor reads a shared diary: only what was shared, always recorded, revealing no patients."""

from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError

from app import audit, sharing
from app.db import SessionLocal
from app.models import AccessLog, DiaryEntry

PATIENT_1 = {"Authorization": "Bearer patient-1"}  # Anna Becker, Europe/Berlin
PATIENT_2 = {"Authorization": "Bearer patient-2"}
CLINICIAN_1 = {"Authorization": "Bearer clinician-1"}  # Dr. Lena Hofmann
CLINICIAN_2 = {"Authorization": "Bearer clinician-2"}
ANNAS_DIARY = "/clinician/patients/1/entries"


def add_entry(client: TestClient, recorded_at: str, note: str | None = "Private note") -> int:
    entry = {"recorded_at": recorded_at, "mood": 2, "symptoms": ["headache"], "note": note}
    return client.post("/entries", json=entry, headers=PATIENT_1).json()["id"]


def share(client: TestClient, from_date: str, to_date: str, **fields: Any) -> int:
    body = {"clinician_id": 1, "from_date": from_date, "to_date": to_date, **fields}
    return client.post("/shares", json=body, headers=PATIENT_1).json()["id"]


def reads(client: TestClient, outcome: str) -> float:
    prefix = f'clinician_reads_total{{outcome="{outcome}"}} '
    for line in client.get("/metrics").text.splitlines():
        if line.startswith(prefix):
            return float(line.removeprefix(prefix))
    return 0.0


def access_log_rows() -> int:
    with SessionLocal() as db:
        return db.scalar(select(func.count()).select_from(AccessLog)) or 0


def test_doctor_sees_entries_by_patients_local_day(client: TestClient) -> None:
    half_past_midnight = add_entry(client, "2026-10-01T22:30:00Z")  # 00:30 on 2 Oct in Berlin
    share(client, "2026-10-01", "2026-10-01")

    assert client.get(ANNAS_DIARY, headers=CLINICIAN_1).json() == []

    share(client, "2026-10-02", "2026-10-02")
    assert [e["id"] for e in client.get(ANNAS_DIARY, headers=CLINICIAN_1).json()] == [
        half_past_midnight
    ]


def test_doctor_sees_app_v1_entry_on_its_local_day(client: TestClient) -> None:
    with SessionLocal() as db:
        # Written by app v1 at 23:50 local time on 14 March, stored as if it were UTC.
        entry = DiaryEntry(
            patient_id=1,
            recorded_at=datetime(2026, 3, 14, 23, 50, tzinfo=UTC),
            mood=2,
            symptoms=["pain"],
            source="app-v1",
        )
        db.add(entry)
        db.commit()
        entry_id = entry.id
    share(client, "2026-03-14", "2026-03-14")

    entries = client.get(ANNAS_DIARY, headers=CLINICIAN_1).json()

    assert [e["id"] for e in entries] == [entry_id]
    # The real moment (Berlin is UTC+1 in March), so the portal shows it on the 14th too.
    assert entries[0]["recorded_at"] == "2026-03-14T22:50:00Z"


def test_app_v1_entries_are_ordered_by_their_real_time(client: TestClient) -> None:
    # Stored "00:30Z" by app v1 really was 23:30Z on the 14th, before a v2 entry at 23:45Z.
    v2_entry = add_entry(client, "2026-03-14T23:45:00Z")
    with SessionLocal() as db:
        v1 = DiaryEntry(
            patient_id=1,
            recorded_at=datetime(2026, 3, 15, 0, 30, tzinfo=UTC),
            mood=3,
            symptoms=[],
            source="app-v1",
        )
        db.add(v1)
        db.commit()
        v1_entry = v1.id
    share(client, "2026-03-14", "2026-03-15")

    entries = client.get(ANNAS_DIARY, headers=CLINICIAN_1).json()

    assert [e["id"] for e in entries] == [v2_entry, v1_entry]


def test_doctor_gets_entries_newest_first_in_the_api_shape(client: TestClient) -> None:
    older = add_entry(client, "2026-10-02T08:00:00Z")
    newer = add_entry(client, "2026-10-03T08:00:00Z")
    share(client, "2026-10-01", "2026-10-07")

    entries = client.get(ANNAS_DIARY, headers=CLINICIAN_1).json()

    assert [e["id"] for e in entries] == [newer, older]
    assert entries[0] == {
        "id": newer,
        "recorded_at": "2026-10-03T08:00:00Z",
        "mood": 2,
        "symptoms": ["headache"],
        "note": None,
    }


def test_notes_are_shown_only_when_included(client: TestClient) -> None:
    add_entry(client, "2026-10-02T08:00:00Z", note="Private note")
    share(client, "2026-10-01", "2026-10-07")
    assert client.get(ANNAS_DIARY, headers=CLINICIAN_1).json()[0]["note"] is None

    share(client, "2026-10-01", "2026-10-07", include_notes=True)
    assert client.get(ANNAS_DIARY, headers=CLINICIAN_1).json()[0]["note"] == "Private note"


def test_unknown_patient_and_not_shared_look_identical(client: TestClient) -> None:
    add_entry(client, "2026-10-02T08:00:00Z")
    no_share = client.get(ANNAS_DIARY, headers=CLINICIAN_1)
    not_a_patient = client.get("/clinician/patients/99/entries", headers=CLINICIAN_1)
    share(client, "2026-10-01", "2026-10-07", clinician_id=2)
    shared_with_someone_else = client.get(ANNAS_DIARY, headers=CLINICIAN_1)
    revoked = share(client, "2026-10-01", "2026-10-07")
    client.post(f"/shares/{revoked}/revoke", headers=PATIENT_1)
    after_revoke = client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    for response in (no_share, not_a_patient, shared_with_someone_else, after_revoke):
        assert response.status_code == 404
        assert response.content == no_share.content
    assert client.get(ANNAS_DIARY, headers=CLINICIAN_2).status_code == 200


def test_revoking_takes_effect_on_the_next_read(client: TestClient) -> None:
    add_entry(client, "2026-10-02T08:00:00Z")
    share_id = share(client, "2026-10-01", "2026-10-07")
    assert client.get(ANNAS_DIARY, headers=CLINICIAN_1).status_code == 200

    client.post(f"/shares/{share_id}/revoke", headers=PATIENT_1)

    assert client.get(ANNAS_DIARY, headers=CLINICIAN_1).status_code == 404


def test_every_read_is_recorded_and_shown_to_the_patient(client: TestClient) -> None:
    first = add_entry(client, "2026-10-02T08:00:00Z")
    share(client, "2026-10-01", "2026-10-02")
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)
    second = add_entry(client, "2026-10-02T09:00:00Z")
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    log = client.get("/access-log", headers=PATIENT_1).json()

    assert [r["entry_ids"] for r in log] == [[second, first], [first]]
    assert set(log[0]) == {"clinician_id", "clinician_name", "accessed_at", "entry_ids"}
    assert (log[0]["clinician_id"], log[0]["clinician_name"]) == (1, "Dr. Lena Hofmann")
    assert log[0]["accessed_at"] >= log[1]["accessed_at"]


def test_access_record_says_which_notes_were_seen(client: TestClient) -> None:
    with_note = add_entry(client, "2026-10-02T08:00:00Z", note="Private note")
    add_entry(client, "2026-10-03T08:00:00Z", note=None)
    share(client, "2026-10-01", "2026-10-07")
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)
    share(client, "2026-10-01", "2026-10-07", include_notes=True)
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    with SessionLocal() as db:
        records = db.scalars(select(AccessLog.note_entry_ids).order_by(AccessLog.id)).all()

    # First read without notes; second with notes, but only one entry has a note to see.
    assert records == [[], [with_note]]


def test_read_with_nothing_in_the_period_is_still_recorded(client: TestClient) -> None:
    share(client, "2026-10-01", "2026-10-07")

    assert client.get(ANNAS_DIARY, headers=CLINICIAN_1).json() == []
    assert [r["entry_ids"] for r in client.get("/access-log", headers=PATIENT_1).json()] == [[]]


def test_refused_reads_are_not_recorded(client: TestClient) -> None:
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    assert access_log_rows() == 0


def test_patients_see_only_their_own_access_log(client: TestClient) -> None:
    share(client, "2026-10-01", "2026-10-07")
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    assert client.get("/access-log", headers=PATIENT_2).json() == []


def test_no_data_when_the_access_cannot_be_recorded(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    add_entry(client, "2026-10-02T08:00:00Z")
    share(client, "2026-10-01", "2026-10-07")
    before = reads(client, "audit_failed")

    def failing_record_access(*args: Any, **kwargs: Any) -> None:
        raise SQLAlchemyError("access_log is unavailable")

    monkeypatch.setattr(audit, "record_access", failing_record_access)
    response = client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal server error"}
    assert access_log_rows() == 0
    assert reads(client, "audit_failed") == before + 1


def test_read_outcomes_are_counted_without_ids(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    before = {o: reads(client, o) for o in ("ok", "not_found", "error")}
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)
    share(client, "2026-10-01", "2026-10-07")
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    def broken_rules(*args: Any, **kwargs: Any) -> None:
        raise RuntimeError("bug")

    monkeypatch.setattr(sharing, "visible_entries", broken_rules)
    client.get(ANNAS_DIARY, headers=CLINICIAN_1)

    assert {o: reads(client, o) - before[o] for o in before} == {
        "ok": 1,
        "not_found": 1,
        "error": 1,
    }
    reads_lines = [line for line in client.get("/metrics").text.splitlines() if "reads" in line]
    assert not any("patient" in line or "clinician_id" in line for line in reads_lines)


def test_clinician_endpoint_is_for_clinicians_only(client: TestClient) -> None:
    assert client.get(ANNAS_DIARY, headers=PATIENT_1).status_code == 403
    assert client.get("/access-log", headers=CLINICIAN_1).status_code == 403


def test_clinician_path_is_logged_as_a_template(
    client: TestClient, app_logs: Callable[[], str]
) -> None:
    client.get("/clinician/patients/48151623/entries", headers=CLINICIAN_1)

    assert "GET /clinician/patients/{patient_id}/entries -> 404" in app_logs()
    assert "48151623" not in app_logs()


def test_entries_and_me_responses_are_unchanged(client: TestClient) -> None:
    # App v2.3 parses these strictly and crashes on any new field.
    add_entry(client, "2026-10-02T08:00:00Z")
    share(client, "2026-10-01", "2026-10-07")

    entries = client.get("/entries", headers=PATIENT_1).json()

    assert set(entries[0]) == {"id", "recorded_at", "mood", "symptoms", "note"}
    assert set(client.get("/me", headers=PATIENT_1).json()) == {"role", "id", "name"}
