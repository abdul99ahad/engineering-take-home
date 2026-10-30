"""Which diary entries a doctor may see. Pure functions: no database, no HTTP."""

from collections.abc import Sequence
from datetime import UTC, date, datetime
from typing import Protocol
from zoneinfo import ZoneInfo

# Version of the consent text the app shows before sharing (O.Cons_3). Change it with the text.
CONSENT_VERSION = "2026-10-v1"


class EntryLike(Protocol):
    recorded_at: datetime
    source: str


class ShareLike(Protocol):
    from_date: date
    to_date: date
    include_notes: bool
    revoked_at: datetime | None


def local_day(recorded_at: datetime, source: str, tz: ZoneInfo) -> date:
    """The day the entry belongs to in the patient's own diary."""
    if source == "app-v1":
        # App v1 sent local wall-clock time without a zone and it was stored as if it were UTC,
        # so the stored UTC date already is the patient's local date.
        return recorded_at.astimezone(UTC).date()
    return recorded_at.astimezone(tz).date()


def visible_entries[E: EntryLike](
    entries: Sequence[E], shares: Sequence[ShareLike], tz: ZoneInfo
) -> list[tuple[E, bool]]:
    """The entries covered by an active share, in input order, each with whether its note shows.

    A note shows only if an active share covering that entry's day includes notes.
    """
    active = [s for s in shares if s.revoked_at is None]
    visible = []
    for entry in entries:
        day = local_day(entry.recorded_at, entry.source, tz)
        covering = [s for s in active if s.from_date <= day <= s.to_date]
        if covering:
            visible.append((entry, any(s.include_notes for s in covering)))
    return visible
