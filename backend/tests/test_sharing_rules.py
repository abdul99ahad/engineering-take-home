"""The sharing rules, without a database: which days an entry belongs to and what a doctor sees."""

from datetime import UTC, date, datetime
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app.sharing import local_day, true_recorded_at, visible_entries

BERLIN = ZoneInfo("Europe/Berlin")  # UTC+2 in early October 2026


def entry(recorded_at: datetime, source: str = "app-v2") -> SimpleNamespace:
    return SimpleNamespace(recorded_at=recorded_at, source=source)


def share(
    from_date: date, to_date: date, include_notes: bool = False, revoked: bool = False
) -> SimpleNamespace:
    revoked_at = datetime(2026, 10, 20, tzinfo=UTC) if revoked else None
    return SimpleNamespace(
        from_date=from_date, to_date=to_date, include_notes=include_notes, revoked_at=revoked_at
    )


def test_entry_at_00_30_berlin_belongs_to_that_day() -> None:
    assert local_day(datetime(2026, 10, 1, 22, 30, tzinfo=UTC), "app-v2", BERLIN) == date(
        2026, 10, 2
    )


def test_app_v1_entry_is_already_local_time() -> None:
    # App v1 stored 23:50 local wall-clock time as if it were UTC: it is still the 14th.
    assert local_day(datetime(2026, 3, 14, 23, 50, tzinfo=UTC), "app-v1", BERLIN) == date(
        2026, 3, 14
    )


def test_app_v1_time_is_corrected_to_the_real_moment() -> None:
    # 23:50 on 14 March in Berlin (UTC+1) really was 22:50 UTC.
    assert true_recorded_at(datetime(2026, 3, 14, 23, 50, tzinfo=UTC), "app-v1", BERLIN) == (
        datetime(2026, 3, 14, 22, 50, tzinfo=UTC)
    )


def test_app_v1_time_correction_follows_summer_time() -> None:
    # 10:00 on 1 April in Berlin (UTC+2) really was 08:00 UTC.
    assert true_recorded_at(datetime(2026, 4, 1, 10, 0, tzinfo=UTC), "app-v1", BERLIN) == (
        datetime(2026, 4, 1, 8, 0, tzinfo=UTC)
    )


def test_app_v2_time_is_already_correct() -> None:
    recorded_at = datetime(2026, 10, 1, 22, 30, tzinfo=UTC)

    assert true_recorded_at(recorded_at, "app-v2", BERLIN) == recorded_at


def test_local_day_across_dst_change() -> None:
    # Berlin is still UTC+1 at 23:30Z on 28 March 2026, so that is 00:30 on the 29th.
    assert local_day(datetime(2026, 3, 28, 23, 30, tzinfo=UTC), "app-v2", BERLIN) == date(
        2026, 3, 29
    )


def test_single_day_share_includes_only_that_day() -> None:
    late_on_1st = entry(datetime(2026, 10, 1, 21, 59, tzinfo=UTC))  # 23:59 on 1 Oct
    early_on_2nd = entry(datetime(2026, 10, 1, 22, 30, tzinfo=UTC))  # 00:30 on 2 Oct
    early_on_3rd = entry(datetime(2026, 10, 2, 22, 1, tzinfo=UTC))  # 00:01 on 3 Oct

    visible = visible_entries(
        [late_on_1st, early_on_2nd, early_on_3rd],
        [share(date(2026, 10, 2), date(2026, 10, 2))],
        BERLIN,
    )

    assert [e for e, _ in visible] == [early_on_2nd]


def test_revoked_share_shows_nothing() -> None:
    entries = [entry(datetime(2026, 10, 2, 8, 0, tzinfo=UTC))]

    assert (
        visible_entries(
            entries, [share(date(2026, 10, 1), date(2026, 10, 7), revoked=True)], BERLIN
        )
        == []
    )


def test_note_hidden_unless_a_covering_active_share_includes_notes() -> None:
    e = entry(datetime(2026, 10, 2, 8, 0, tzinfo=UTC))
    without_notes = share(date(2026, 10, 1), date(2026, 10, 7))
    revoked_with_notes = share(
        date(2026, 10, 1), date(2026, 10, 7), include_notes=True, revoked=True
    )
    with_notes = share(date(2026, 10, 1), date(2026, 10, 7), include_notes=True)

    assert visible_entries([e], [without_notes, revoked_with_notes], BERLIN) == [(e, False)]
    assert visible_entries([e], [without_notes, with_notes], BERLIN) == [(e, True)]


def test_note_shown_only_for_days_covered_by_the_notes_share() -> None:
    on_2nd = entry(datetime(2026, 10, 2, 8, 0, tzinfo=UTC))
    on_3rd = entry(datetime(2026, 10, 3, 8, 0, tzinfo=UTC))
    week_without_notes = share(date(2026, 10, 1), date(2026, 10, 7))
    one_day_with_notes = share(date(2026, 10, 3), date(2026, 10, 3), include_notes=True)

    visible = visible_entries([on_2nd, on_3rd], [week_without_notes, one_day_with_notes], BERLIN)

    assert visible == [(on_2nd, False), (on_3rd, True)]
