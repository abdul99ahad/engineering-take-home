# Prompts

The prompts that drove this take-home, with what came of each one. They are written the way a user
would ideally write them, using specifics from the docs, the design spec
(`docs/specs/2026-10-30-diary-sharing-design.md`) and the plan
(`docs/plans/2026-10-30-diary-sharing.md`). The brainstorming, planning and code-review steps run
my own custom skills.

## 1. Understand the project

**Prompt:**
> Read README.md, BRIEF.md, API.md, REQUIREMENTS.md, NOTES.md, app/DESIGN.md and the backend and app
> code. Summarise what exists, what the task asks us to build (endpoints, patient screens,
> monitoring, NOTES.md), and every trap hidden in the brief, requirements and seed data.

**Outcome:** A summary of the stack and the four deliverables, plus 11 traps: patient time zones,
`app-v1` rows, frozen `/entries` and `/me`, private notes, no patient enumeration, body logging in
the existing middleware, the append-only 10-year access log, erasure vs audit, no IDs in metrics,
consent versioning, and requirements that don't apply.

## 2. Start brainstorming

**Prompt:**
> Run my brainstorming skill for the diary sharing feature: ask me what matters to me before
> designing, then produce a written design and an implementation plan.

**Outcome:** Brainstorming started with one open question about what the reviewers should take
away from the submission.

## 3. What the reviewers should take away

**Prompt:**
> Optimise for two takeaways: every hidden trap in the brief is visibly handled (code, a test named
> after the rule, NOTES.md), and NOTES.md is honest about gaps. Code should be single-responsibility,
> loosely coupled, fully tested and follow the existing conventions.

**Outcome:** Played back the intent, and flagged the tension between "test everything" and the
2-hour timebox.

## 4. Keep it simple

**Prompt:**
> No layered architecture: a few small modules with clear jobs. Put the tricky rules (time zones,
> note visibility) in pure functions with fast unit tests.

**Outcome:** Backend design played back: `shares` and append-only `access_log` tables, a pure
`sharing.py`, thin routes, an identical 404 for doctors, the access-log write in the same
transaction, and the logging and 500 fixes.

## 5. Mockup feedback

**Prompt:**
> Revise the mockup: (1) propose better names for the "Who saw your diary" section and make each
> access record expandable to show which entries the doctor saw; (2) restyle the consent summary as
> a distinct terms panel, using existing design tokens only.

**Outcome:** Revision 2: three name options, expandable visitor rows (entries matched from
`entry_ids`), and a "Your consent" panel with five numbered terms, a version line and an "I agree"
checkbox that gates the share button.

## 6. Choose the section name

**Prompt:**
> Name the section "Your diary's visitors". The consent panel is approved. Write the design document.

**Outcome:** Wrote `docs/specs/2026-10-30-diary-sharing-design.md`, self-reviewed it as the
builder, and settled the minor gaps.

## 7. Approve design, request plan

**Prompt:**
> Confirm how monitoring is covered (on-call signal, product signal, what pages someone). The design
> is approved: write a test-first implementation plan with exact files, interfaces and tests.

**Outcome:** Monitoring summarised. Wrote `docs/plans/2026-10-30-diary-sharing.md`: 11 steps from
logging hygiene to NOTES.md, with a Review Focus of five edge cases. Recommended running it
natively.

## 8. Explain the logging fix before writing it

**Prompt:**
> Don't commit the spec or plan. Before you touch the logging and error handling, explain: what the
> logs contain today, what O.Log_4, O.Err_1 and the brief allow, what we will and won't log and
> why, and how the tests prove it.

**Outcome:** Explained the allowed and forbidden log fields. Found two gaps in the plan: uvicorn's
own access log (raw path and IP), and Starlette re-raising after exception handlers. Updated the
plan.

## 9. Logging and error hygiene

**Prompt:**
> Test-first: write `backend/tests/test_hygiene.py`, watch it fail, then fix `log_requests` in
> `backend/app/main.py`.

**Outcome:** 5 failing tests written. Scoped them to the API's own logger, because the test
client logs raw URLs. The middleware then logs the route template only, unhandled errors return a
generic JSON 500 and log the exception type only, and 15/15 tests pass.

## 10. Question the Dockerfile change

**Prompt:**
> Explain why `--no-access-log` should go in `backend/Dockerfile`, and whether there is a better
> place for it.

**Outcome:** Showed live logs in which uvicorn printed raw paths and IPs. Recommended disabling
`uvicorn.access` in code instead.

## 11. Dev-only, so why test it?

**Prompt:**
> The Dockerfile looks dev-only. Argue for in-code vs Dockerfile placement of the access-log switch.

**Outcome:** The leak matters in production, which may not use this Dockerfile (`--reload`), so
the rule should travel with the code. Offered the Dockerfile plus a NOTES.md caveat as the
alternative.

## 12. Go inline

**Prompt:**
> Disable `uvicorn.access` in `backend/app/main.py`, test-first, and verify with the live logs.

**Outcome:** Added `test_server_access_log_is_silenced` (red, then green) and the one-line fix.
16/16 tests pass, lint is clean, and the live log has no IDs or IPs.

## 13. Second-opinion review

**Prompt:**
> Verify these two review points against the code and uvicorn's source. Change things only if
> they're actually a problem here.

**Outcome:** Point 1 was already met and pinned by a test. Point 2: uvicorn runs `dictConfig`
before importing the app, so the setting holds; no change, and a deployment note goes in NOTES.md.

## 14. Commit the logging work, log prompts, write the sharing rules

**Prompt:**
> Commit the logging and error hygiene with a single-line Conventional Commits message. Create
> PROMPTS.md logging every prompt so far with its outcome, and add a rule to CLAUDE.md to keep it
> updated, plus the single-line commit rule. Then write the sharing rules test-first: pure
> `local_day` and `visible_entries` in `backend/app/sharing.py` with unit tests in
> `backend/tests/test_sharing_rules.py` (00:30 Berlin, `app-v1`, DST, single-day share, revoked
> share, overlapping shares and notes).

**Outcome:** Logging committed (`d66433c`). PROMPTS.md created, and CLAUDE.md gained the
PROMPTS.md rule and the single-line commit rule. The rules landed as `backend/app/sharing.py` with
`CONSENT_VERSION`, `local_day` and `visible_entries` behind small Protocols, and 7 unit tests.
23/23 backend tests pass; committed as `feat(backend/sharing): add time-zone-aware sharing rules`.

## 15. Check the plan against the timebox

**Prompt:**
> Estimate the work still left at the pace of what's done so far, compare it with the README's
> 2-hour timebox (counting time already spent, from file and commit timestamps), and propose
> concrete cuts in priority order that keep what the graders test: the API contract, the patient
> screens, the requirements and NOTES.md.

**Outcome:** The plan doesn't fit as written: about 2.5 hours of work remain, and roughly 1.5 hours
have already gone, mostly on brainstorming and planning. Proposed a trimmed plan (drop the
dashboard, "Choose dates" and expandable visitors, thinner app tests) of about 1.5 hours, and
asked how to count the clock.

## 16. Shares and append-only access log

**Prompt:**
> Test-first: `Share` and `AccessLog` models in `backend/app/models.py`, a hand-written Alembic
> migration `0002` with a trigger that rejects UPDATE and DELETE on `access_log`, and no foreign
> keys from `access_log` to patients or entries (erasure). Prove that the models match the
> migration and that the migration downgrades cleanly.

**Outcome:** Two tests: append-only (red, then green), and no foreign keys to patients or entries.
`alembic check` reports no drift, the downgrade and re-upgrade work, the dev database is at `0002`,
and 25/25 tests pass. Committed as
`feat(backend/sharing): add shares and append-only access log tables`.

## 17. Start NOTES.md as we go

**Prompt:**
> Record the O.Log_3 limit in NOTES.md now, along with everything else already built (data model,
> O.Log_4, O.Err_1, logging next steps), so NOTES grows with the code instead of being written at
> the end. Leave it uncommitted for me to review.

**Outcome:** NOTES.md now has the data model section, the O.Log_3 (partly met), O.Log_4 and
O.Err_1 rows with code and test references, and two next steps. Left uncommitted for review: the
user stopped the commit.

## 18. Patient share endpoints

**Prompt:**
> Test-first: `POST /shares`, `GET /shares` and `POST /shares/{id}/revoke` exactly as in API.md.
> Patients only. Return 422 for an unknown doctor or `from_date > to_date`. Revoking someone else's
> or a missing share returns the same 404, and revoking twice keeps the first `revoked_at`. The
> server stamps `consent_version` and doesn't return it. Add label-less `shares_created` and
> `shares_revoked` counters.

**Outcome:** 11 tests (all red, then green) in `backend/tests/test_shares.py`, plus `ShareIn` and
`ShareOut`, the routes and the counters. 36/36 backend tests pass. Committed as
`feat(backend/sharing): add patient share endpoints`. NOTES.md is still uncommitted.

## 19. Audited doctor read

**Prompt:**
> Test-first: `GET /clinician/patients/{patient_id}/entries` (clinicians only; the identical 404
> for no share, an unknown patient, another doctor's share or a revoked share; local-day filtering
> including `app-v1`; notes only when included; newest first) and `GET /access-log`. Write the
> access record in the same transaction as the read; if it fails, return a generic 500 with no
> data. Count `clinician_reads_total{outcome}` with no IDs, keep `/entries` and `/me` unchanged,
> and check it live against the dev API.

**Outcome:** `backend/app/audit.py`, `current_clinician`, `ClinicianEntryOut` and `AccessLogOut`,
both routes, and an outcome counter set in a `finally` block. 15 tests in
`test_clinician_access.py`; the `app_logs` fixture moved to `conftest.py`. 51/51 tests pass, and
the live check matched the design. Not committed: the user asked for a review first. NOTES.md
(uncommitted) gained rows for O.Cons_1–3, O.Log_1–2 and O.Mon_1.

## 20. Review before committing

**Prompt:**
> Before committing the doctor read, review it and the access-log code against the design and the
> brief's traps. For each part, say whether it does what's intended; list any bugs or gaps with a
> recommended fix.

**Outcome:** Self-review confirmed the identical 404, consent checked on every read, the
single-transaction audit and the metrics. It found a bug (doctors are shown `app-v1` entries'
stored timestamp, which is off by the UTC offset, so the wrong day), a gap (the access log doesn't
record whether notes were seen) and a slip (`outcome = "ok"` set before the response is built).
Fixes are proposed and await the user's decision.

## 21. Independent code review

**Prompt:**
> Run my code-review skill: a fresh reviewer, with no session history, checks the whole backend
> change (base `dbef365` to the working tree, including the uncommitted doctor read) against
> BRIEF.md, API.md, REQUIREMENTS.md, the design and the plan, and reports Critical/Important/Minor
> issues with a verdict.

**Outcome:** Verdict "ready with fixes", 51/51 tests pass, no critical issues. Important: the
`app-v1` timestamp shown to doctors (it found this independently), and the `audit_failed` series
missing until its first failure, so an `increase()` alert misses the first failure after every
restart. Seven minor issues (revoke race, untested commit-time audit failure, sort tiebreak,
422 body shape, trigger and role limits for NOTES, Dockerfile flag). Merged with the self-review
into one fix list for the user's decision.

## 22. Is the timestamp fix in the brief?

**Prompt:**
> Quote what BRIEF.md says about patient-local days and `app-v1` rows, and say whether correcting
> the timestamps in the doctor's response is required by the brief or is our own inference.

**Outcome:** The brief requires local-day *filtering*, including handling `app-v1` rows, and that
is done. It doesn't say which timestamp to return, so the fix is an inference. Recommended doing
it anyway, because otherwise the API contradicts itself: an entry included as 14 March carries a
timestamp that reads as 15 March. Also flagged that the patient's own diary shows these rows
shifted.

## 23. Fix the app-v1 timestamp for doctors

**Prompt:**
> Test-first: add a pure `true_recorded_at(recorded_at, source, tz)` to `backend/app/sharing.py`
> that turns `app-v1` stored values into the real UTC moment (summer and winter time), base
> `local_day` on it, return the corrected time in the doctor's response, and sort by the real time
> with an id tie-break. Check it live against the seeded `app-v1` entries.

**Outcome:** Three unit tests and two API tests (red, then green). `local_day` now builds on
`true_recorded_at`, so the `app-v1` rule lives in one place. The doctor's response carries
corrected times, sorted newest first by the real moment with an id tie-break. The response is now
built before the audit write, which also resolves review items 6 and 7. 55/55 tests pass. Live,
the seeded 23:50 entry from 14 March now reads `2026-03-14T22:50:00Z`. Not committed yet.

## 24. Apply only my own review findings

**Prompt:**
> Apply only the fixes from my own review: #3 (record in the access log which notes the doctor
> saw, without changing the API.md response) and #6 (count `ok` only after the response is
> built). Skip the reviewer-only items 2, 4 and 5.

**Outcome:** #6 was already fixed by the timestamp change. For #3: a red-then-green test
`test_access_record_says_which_notes_were_seen`, an `AccessLog.note_entry_ids` column, and
`record_access` and the route passing the IDs of notes actually disclosed.

## 25. Fold the column into migration 0002

**Prompt:**
> `0002` has never left this machine, so add `note_entry_ids` to it instead of creating `0003`.
> Downgrade and re-upgrade the test database, run `make reset` for dev, and confirm the schema
> matches the models.

**Outcome:** The column is now in `0002`. The test database was re-migrated, `alembic check`
shows no drift, and 56/56 tests pass. `make reset` left the dev database at `0002` with the new
column, the 8 seeded entries, and no leftover shares or access rows. NOTES.md (uncommitted)
updated: data model, the O.Log_1 row, and an O.Log_2 gap (`note_entry_ids` isn't returned by the
API).

## 26. Record the unfixed review items

**Prompt:**
> In NOTES.md, record each reviewer finding we chose not to fix (items 2, 4, 5, 8, 9, 10) as a
> known gap: what's wrong, why it matters, the fix. Cross-reference the requirement rows they
> weaken.

**Outcome:** NOTES.md has a new "Known gaps" section with six entries (the metric series that
appears late, the untested commit-time audit failure, the revoke race, the two 422 shapes, the
in-code-only access-log switch, `app-v1` rows still shifted for patients). The O.Mon_1 and O.Log_3
rows reference them, and the data model section reflects the `app-v1` time fix and the single
`0002` migration. Still uncommitted.

## 27. App models, API calls and consent text

**Prompt:**
> Build the app's sharing layer test-first, with nothing trimmed from the two screens that follow:
> - `Clinician`, `Share` (with `isActive`) and `AccessRecord` models;
> - `ApiClient.listClinicians`, `listShares`, `createShare` (dates sent as `YYYY-MM-DD`),
>   `revokeShare` and `listAccessLog`;
> - `isoDate`, `formatDateRange` and `formatShortDateTime` in `format.dart`;
> - `lib/sharing_rules.dart` with `consentVersion = '2026-10-v1'`, `Period` presets and the five
>   exact `consentTerms` strings.

**Outcome:** Two new test files (helpers, and API calls against a mock HTTP client), red, then
green. 16/16 Flutter tests pass and `flutter analyze` is clean. Committed as
`feat(app/sharing): add sharing models, API calls and consent text`.

## 28. Share form screen

**Prompt:**
> Build `ShareFormScreen` in `app/lib/share_form_screen.dart` test-first, with
> - a doctor picker (`FilterChip`s from `/clinicians`);
> - "Last 7 days", "Last 30 days" and "Choose dates" (date range picker, last date today);
> - an "Include my notes" switch, off by default;
> - the "Your consent" panel (five numbered terms, version line, "I agree" checkbox);
> - a pinned "Share my diary" button, enabled only with a doctor chosen and consent ticked;
> - on success, track `share_created` and close; on failure, a snackbar
>   "Couldn't share your diary. Try again.".
> Changing what is shared must clear the consent tick (O.Cons_1).

**Outcome:** Seven widget tests in `app/test/share_form_test.dart` (red, then green) and the
screen built from existing widgets. The form isn't reachable from the diary until the sharing
screen adds the button.

## 29. Follow DESIGN.md

**Prompt:**
> Review the share form against app/DESIGN.md rule by rule (tokens, type, spacing, shape, layout,
> components, words, accessibility) and fix every deviation.

**Outcome:** Found and fixed four deviations: a 12 px gap that isn't a spacing token, the consent
panel's radius (card, not control), chip tap targets below 48 px in desktop browsers, and jargon
in the version line ("Version 2026-10-v1 of these terms").

## 30. No design tests

**Prompt:**
> Don't write tests for visual design (spacing, radii, sizes, tap targets). Keep tests to what the
> user can do and what the rules guarantee, and record this as a working rule.

**Outcome:** Dropped the tap-target test before it was written; design fixes are in code only.
Added the rule "Test functionality, not design" to CLAUDE.md. 23/23 Flutter tests pass; lint is
clean. The share form is not committed yet.

## 31. Sharing screen and diary entry point

**Prompt:**
> Commit the share form. Then build the sharing screen test-first (functional tests only):
> - `SharingScreen` with "Shared now" (with confirmed "Stop sharing"), "Stopped", and "Your
>   diary's visitors" (expandable: practice, the entries seen, "N entries no longer in your
>   diary");
> - empty and error states, and a "Share diary" button that opens the form;
> - `sharing_opened` and `share_revoked` events;
> - a "Share with your doctor" button on the diary screen.
> Rebuild the web app so it can be checked in the browser.

**Outcome:** Share form committed (`d1b11a0`). Seven widget tests for the sharing screen. They
caught a real bug: `setState` given an arrow function that returned a Future, which would have
crashed the screen when a share was stopped. `app/lib/sharing_screen.dart` and the diary button
are built from existing tokens and widgets. 30/30 Flutter tests pass, lint is clean, and
`make app` rebuilt the web build. Committed as
`91c4258 feat(app/sharing): add sharing screen with visitors and stop sharing`.

## 32. How to test the app by hand

**Prompt:**
> Give me a manual test script as bullet-point scenarios: the patient flows in the app (share,
> consent, stop sharing, visitors) plus the doctor side and the hidden rules via curl (notes,
> identical 404, `app-v1` time, roles, logs, metrics, append-only log, error states), each with
> the expected result.

**Outcome:** A 12-scenario manual test script, plus a note that the user's browser isn't in the
patient's time zone (Europe/Berlin), which affects which days the presets cover and the times
shown.

## 33. Two visits for one request

**Prompt:**
> The Sharing screen shows two visits, but I sent only one successful doctor read. Check the
> access log and explain where the second record came from.

**Outcome:** Two rows exist: 10:47:08 UTC was the agent's own curl as `clinician-2` in an earlier
answer, and 10:48:21 UTC was the user's request. Both were real reads, so both were recorded
(O.Log_1). The 404s weren't recorded, as designed. The agent's demo read is now a permanent
record, because the log is append-only; only `make reset` clears it.

## 34. Equal-width share cards

**Prompt:**
> Make the share cards on the Sharing screen full width, like the visitor cards, so every card
> lines up regardless of its text length. Design fix only, no test; rebuild the web app.

**Outcome:** `_Card` in `app/lib/sharing_screen.dart` now takes the full content width
(`width: double.infinity`), so both share cards and the stopped cards line up with the visitor
cards. 30/30 tests pass, lint is clean, and the web build is rebuilt. Committed as
`fix(app/sharing): make share cards full width`.

## 35. Dashboard and alerts

**Prompt:**
> Add the monitoring:
> - a Grafana dashboard for diary sharing (on-call: audit failures, failing reads, p95 latency,
>   outcomes; product: shares created and stopped, app events);
> - file-provisioned alert rules: page on any audit failure (catching the first failure after a
>   restart, known gap #1, without changing app code), page on more than 5% failing doctor
>   reads, morning alert on p95 above 1 s.
> Verify with `make observe` that Grafana loads them, every query runs in Prometheus, and the
> rules evaluate without errors. No doctor reads against the dev database.

**Outcome:**
- `observability/dashboards/diary-sharing.json`: 7 panels in an on-call row and a product row,
  as a separate dashboard rather than additions to the example one.
- `observability/grafana/alerting/sharing-alerts.yml`: three rules.
- Grafana loaded the dashboard and all three rules with no provisioning errors. All 10 queries
  ran in Prometheus, and the rules evaluate as healthy and not firing.
- The audit alert firing was not tested, because that needs a real failure.
- Committed as `feat(observability): add sharing dashboard and alerts`.

## 36. Cross-check the assumptions and add them to NOTES.md

**Prompt:**
> Verify each assumption in the list I pasted against the code and tests (api.py, schemas.py,
> sharing.py, auth.py, metrics.py, migration 0002, app/lib sharing_rules.dart and
> sharing_screen.dart, test_shares.py, test_clinician_access.py). Report any that are wrong or
> missing, then write them into NOTES.md "Assumptions and open questions" as bolded-lead bullets
> under one sub-heading per group. Don't change code.

**Outcome:** All pasted assumptions matched the code and tests. Added two the list missed: the
skipped summer-time hour for `app-v1` rows, and that entries can't be deleted through the API
today. NOTES.md "Assumptions and open questions" now has six sub-sections. No commit.

## 37. Write "How I used AI"

**Prompt:**
> Fill NOTES.md "How I used AI" concisely from PROMPTS.md: the tools (Claude Code, my custom
> brainstorming, planning and code-review skills, a second review session), the brainstorm → plan
> → implement → review workflow with links to the spec and plan, and where I corrected the agent,
> citing PROMPTS entry numbers.

**Outcome:** NOTES.md "How I used AI" written: tools, a four-step workflow, and six corrections
(Dockerfile flag, `app-v1` time inference, migration `0003` folded into `0002`, design tests,
DESIGN.md check, assumptions cross-checked). No commit.