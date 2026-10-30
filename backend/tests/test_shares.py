from fastapi.testclient import TestClient
from sqlalchemy import select

from app.db import SessionLocal
from app.models import Share

PATIENT_1 = {"Authorization": "Bearer patient-1"}
PATIENT_2 = {"Authorization": "Bearer patient-2"}
CLINICIAN_1 = {"Authorization": "Bearer clinician-1"}
SHARE = {"clinician_id": 1, "from_date": "2026-10-01", "to_date": "2026-10-07"}
SHARE_FIELDS = {
    "id",
    "clinician_id",
    "from_date",
    "to_date",
    "include_notes",
    "created_at",
    "revoked_at",
}


def metric(client: TestClient, name: str) -> float:
    """A label-less counter's current value; counters live for the whole test session."""
    for line in client.get("/metrics").text.splitlines():
        if line.startswith(f"{name} "):
            return float(line.split()[1])
    return 0.0


def test_patient_creates_share(client: TestClient) -> None:
    response = client.post("/shares", json=SHARE, headers=PATIENT_1)

    assert response.status_code == 201
    share = response.json()
    assert set(share) == SHARE_FIELDS
    assert share["clinician_id"] == 1
    assert (share["from_date"], share["to_date"]) == ("2026-10-01", "2026-10-07")
    assert share["include_notes"] is False
    assert share["revoked_at"] is None


def test_patient_can_include_notes(client: TestClient) -> None:
    share = client.post("/shares", json={**SHARE, "include_notes": True}, headers=PATIENT_1)

    assert share.json()["include_notes"] is True


def test_single_day_share_is_valid(client: TestClient) -> None:
    single_day = {**SHARE, "to_date": SHARE["from_date"]}

    assert client.post("/shares", json=single_day, headers=PATIENT_1).status_code == 201


def test_share_stores_consent_version(client: TestClient) -> None:
    client.post("/shares", json=SHARE, headers=PATIENT_1)

    with SessionLocal() as db:
        assert db.scalars(select(Share.consent_version)).all() == ["2026-10-v1"]


def test_rejects_invalid_shares(client: TestClient) -> None:
    for invalid in (
        {**SHARE, "from_date": "2026-10-08"},  # after to_date
        {**SHARE, "clinician_id": 99},  # unknown doctor
        {**SHARE, "to_date": "2026-13-01"},  # not a date
        {"from_date": "2026-10-01", "to_date": "2026-10-07"},  # no doctor
    ):
        assert client.post("/shares", json=invalid, headers=PATIENT_1).status_code == 422


def test_shares_are_newest_first_and_only_own(client: TestClient) -> None:
    first = client.post("/shares", json=SHARE, headers=PATIENT_1).json()
    second = client.post("/shares", json={**SHARE, "clinician_id": 2}, headers=PATIENT_1).json()

    assert [s["id"] for s in client.get("/shares", headers=PATIENT_1).json()] == [
        second["id"],
        first["id"],
    ]
    assert client.get("/shares", headers=PATIENT_2).json() == []


def test_revoke_sets_revoked_at(client: TestClient) -> None:
    share = client.post("/shares", json=SHARE, headers=PATIENT_1).json()

    response = client.post(f"/shares/{share['id']}/revoke", headers=PATIENT_1)

    assert response.status_code == 200
    assert response.json()["id"] == share["id"]
    assert response.json()["revoked_at"] is not None


def test_revoking_twice_keeps_the_first_revocation(client: TestClient) -> None:
    share = client.post("/shares", json=SHARE, headers=PATIENT_1).json()
    first = client.post(f"/shares/{share['id']}/revoke", headers=PATIENT_1).json()

    second = client.post(f"/shares/{share['id']}/revoke", headers=PATIENT_1)

    assert second.status_code == 200
    assert second.json()["revoked_at"] == first["revoked_at"]


def test_cannot_revoke_someone_elses_share(client: TestClient) -> None:
    share = client.post("/shares", json=SHARE, headers=PATIENT_1).json()

    others = client.post(f"/shares/{share['id']}/revoke", headers=PATIENT_2)
    missing = client.post("/shares/999/revoke", headers=PATIENT_2)

    assert others.status_code == missing.status_code == 404
    assert others.json() == missing.json()
    assert client.get("/shares", headers=PATIENT_1).json()[0]["revoked_at"] is None


def test_share_endpoints_are_for_patients_only(client: TestClient) -> None:
    assert client.post("/shares", json=SHARE, headers=CLINICIAN_1).status_code == 403
    assert client.get("/shares", headers=CLINICIAN_1).status_code == 403
    assert client.post("/shares/1/revoke", headers=CLINICIAN_1).status_code == 403


def test_share_metrics_count_creations_and_revocations(client: TestClient) -> None:
    created, revoked = (
        metric(client, "shares_created_total"),
        metric(client, "shares_revoked_total"),
    )

    share = client.post("/shares", json=SHARE, headers=PATIENT_1).json()
    client.post(f"/shares/{share['id']}/revoke", headers=PATIENT_1)
    client.post(f"/shares/{share['id']}/revoke", headers=PATIENT_1)  # no second count

    assert metric(client, "shares_created_total") == created + 1
    assert metric(client, "shares_revoked_total") == revoked + 1
