"""Records doctors' access to diaries (O.Log_1). Rows are append-only (see migration 0002)."""

from sqlalchemy.orm import Session

from app.models import AccessLog


def record_access(
    db: Session,
    patient_id: int,
    clinician_id: int,
    entry_ids: list[int],
    note_entry_ids: list[int],
) -> None:
    """Adds the record to the caller's transaction, so it commits together with the read."""
    db.add(
        AccessLog(
            patient_id=patient_id,
            clinician_id=clinician_id,
            entry_ids=entry_ids,
            note_entry_ids=note_entry_ids,
        )
    )
