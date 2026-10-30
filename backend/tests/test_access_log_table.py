"""The access log is evidence: kept as written (O.Log_3), not tied to data that may be erased."""

import pytest
from sqlalchemy import delete, select, update
from sqlalchemy.exc import DBAPIError

from app.db import SessionLocal
from app.models import AccessLog


def test_access_log_rejects_update_and_delete() -> None:
    with SessionLocal() as db:
        db.add(AccessLog(patient_id=1, clinician_id=1, entry_ids=[1]))
        db.commit()

        for statement in (update(AccessLog).values(entry_ids=[]), delete(AccessLog)):
            with pytest.raises(DBAPIError, match="append-only"):
                db.execute(statement)
            db.rollback()

        assert db.scalars(select(AccessLog.entry_ids)).all() == [[1]]


def test_access_log_does_not_depend_on_entries_or_patients() -> None:
    # No foreign keys to diary_entries or patients, so erasing those later cannot be blocked by
    # (or cascade into) the audit trail.
    with SessionLocal() as db:
        db.add(AccessLog(patient_id=999, clinician_id=1, entry_ids=[12345]))
        db.commit()
