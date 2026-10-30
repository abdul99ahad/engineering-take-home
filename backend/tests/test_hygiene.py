"""Logs and error responses must not leak health data or internals (O.Log_4, O.Err_1)."""

import logging
from collections.abc import Callable, Iterator

import pytest
from fastapi.testclient import TestClient

from app.db import get_db
from app.main import app

PATIENT_1 = {"Authorization": "Bearer patient-1"}
ENTRY = {
    "recorded_at": "2026-10-05T08:30:00+02:00",
    "mood": 2,
    "symptoms": ["dizziness"],
    "note": "Secret note about my day",
}


@pytest.fixture
def broken_client() -> Iterator[TestClient]:
    """A client whose database fails with a message that contains health data, like SQLAlchemy's."""

    def broken_db() -> None:
        raise RuntimeError("INSERT ... [parameters: {'note': 'Secret note about my day'}]")

    app.dependency_overrides[get_db] = broken_db
    try:
        with TestClient(app, raise_server_exceptions=False) as client:
            yield client
    finally:
        app.dependency_overrides.clear()


def test_request_bodies_are_not_logged(client: TestClient, app_logs: Callable[[], str]) -> None:
    client.post("/entries", json=ENTRY, headers=PATIENT_1)

    assert "POST /entries -> 201" in app_logs()
    assert "Secret note" not in app_logs()
    assert "dizziness" not in app_logs()


def test_raw_paths_are_not_logged(client: TestClient, app_logs: Callable[[], str]) -> None:
    client.get("/patients/48151623/diary", headers=PATIENT_1)

    assert "48151623" not in app_logs()


def test_server_access_log_is_silenced(caplog: pytest.LogCaptureFixture) -> None:
    # uvicorn's own access log line carries the raw path and the client IP.
    caplog.set_level(logging.INFO, logger="uvicorn.access")

    logging.getLogger("uvicorn.access").info('1.2.3.4 - "GET /clinician/patients/1/entries"')

    assert caplog.records == []


def test_unhandled_error_returns_generic_500(broken_client: TestClient) -> None:
    response = broken_client.get("/entries", headers=PATIENT_1)

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal server error"}


def test_unhandled_error_logs_only_the_exception_type(
    broken_client: TestClient, app_logs: Callable[[], str]
) -> None:
    broken_client.get("/entries", headers=PATIENT_1)

    assert "Unhandled RuntimeError on /entries" in app_logs()
    assert "GET /entries -> 500" in app_logs()
    assert "Secret note" not in app_logs()
    assert "parameters" not in app_logs()


def test_unhandled_error_is_counted_in_metrics(broken_client: TestClient) -> None:
    broken_client.get("/entries", headers=PATIENT_1)

    metrics = broken_client.get("/metrics").text
    assert 'http_requests_total{method="GET",route="/entries",status="500"}' in metrics
