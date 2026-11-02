# Project

Kranus engineering take-home: add diary sharing end to end. FastAPI + PostgreSQL backend,
Flutter (web build) app. Everything runs in Docker via `make`; there is no local Python or Flutter.

- `make setup` once, then `make up` (app on 28001, API docs on 28000)
- `make test` runs backend and app tests, and must stay green
- `make observe` brings up Prometheus (28002) and Grafana (28003)
- Auth is a stub: `Authorization: Bearer <role>-<id>`. The app always acts as `patient-1`.

Read before changing anything: [BRIEF.md](BRIEF.md) for the scenario and stakeholder constraints,
[API.md](API.md) for the contract, [REQUIREMENTS.md](REQUIREMENTS.md) for the security and data
protection requirements, [app/DESIGN.md](app/DESIGN.md) for app conventions,
[ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit together.
Deliverable write-up goes in [NOTES.md](NOTES.md).

## Hard constraints

These are not preferences. Each one is a requirement or a stakeholder constraint from the brief,
and breaking one fails the task even if the feature works.

1. **Do not change `/entries` or `/me` responses at all.** App v2.3 is on about a third of installs,
   cannot be force-updated, and parses both strictly. No new fields, no reordering, no type changes.
2. **Paths and field names in API.md are frozen.** The clinician portal team already built against
   them and Kranus runs their own tests against the contract. Match them exactly.
3. **Never reveal whether a person is a patient.** `GET /clinician/patients/{id}/entries` must respond
   identically when the person is not a patient, when no share exists, and when a share was revoked.
   Do not split 403 and 404 by cause. (O.Cons_1)
4. **Day boundaries are the patient's local days, not UTC.** An entry at 00:30 belongs to that day.
   Rows with `source = 'app-v1'` were written without a time zone and stored as if UTC, and were never
   corrected, so they need separate handling. Do not filter with a naive `DATE(recorded_at)`.
5. **Check consent at read time.** Revocation applies to every access that starts after it, so share
   state is never cached or resolved ahead of the request. (O.Cons_2)
6. **Notes are private by default.** `note` is `null` unless the patient set `include_notes` on that
   share. Doctors get mood and symptoms otherwise.
7. **Audit rows are append-only.** Access records are retained ten years and protected against
   modification: no UPDATE, no DELETE, no soft-edit path. (O.Log_1, O.Log_3)
8. **A failed audit write must alert, and must not silently allow the read.** (O.Mon_1)
9. **No health data or direct identifiers in logs, metrics, or metric labels.** No names, no email
   addresses, no diary content. Monitoring carries no patient data. (O.Log_4)
10. **Error responses expose nothing internal.** No stack traces, SQL, file paths, or library
    versions. (O.Err_1)
11. **Erasure is out of scope but must not be designed out.** Do not build it; do describe how it
    would work, including the conflict with the ten-year audit retention. (O.Del_1)

## Working rules

- **Reproduce before changing.** Work from the running app, the API docs, logs and queries, not from
  assumptions about what the code does.
- **Tests ship with the feature**, in the same change, not after. Keep `make test` passing.
- **Test functionality, not design.** No tests for spacing, radii, colours, sizes or tap targets;
  follow app/DESIGN.md in the code and check it by eye. Test what the user can do and what the
  rules guarantee (including copy that carries meaning, such as consent terms).
- **Small, individually reviewable commits.** One concern per commit. The message is a single
  Conventional Commits line (e.g. `feat(backend/sharing): ...`): no body, no trailers.
- **Explain every line.** Anything generated gets read and understood before it is committed. If a
  line cannot be defended out loud, it does not go in.
- **Document assumptions where the spec is silent** (revoke idempotency, `from_date` after `to_date`,
  unknown share ids) in NOTES.md rather than guessing quietly.
- **Two-hour timebox.** Prefer a smaller finished slice plus honest next steps over a wide
  half-working one. When time runs out, stop and write it down.

## PROMPTS.md: log every prompt

Keep `PROMPTS.md` as the record of how this project was driven. Update it in the same
turn as the work it describes, not at the end of the session.

Format, one entry per exchange that changed something:

    ## <n>. <short title naming the work>

    **Prompt:**
    > <the instruction, as it should have been written>

    **Outcome:** <what actually happened: files, tests, commit, what was left undone>

Rules:

- One entry per exchange that produced a decision, a design, code, or a finding.
  Skip approvals ("ok", "looks fine"), "continue" after an interruption, commit-only
  chores, and anything that turned out to be a local tooling or cache problem.
- Where my actual message was vaguer than that, record the sharper version. The
  Outcome stays factual, including the parts that went wrong or were left out.
- Keep the Outcome honest about what was *not* done: tests not written, items not
  fixed, things left uncommitted.
- Number entries sequentially and never reuse a number.

## NOTES.md is a deliverable, not a summary

O.Doc_1 requires an applicability assessment for every requirement in REQUIREMENTS.md: does it apply,
where is it met, or why not. Several cannot be met in this harness because auth is stubbed, including
O.Auth_1 (re-authentication after 15 minutes) and O.Pass_1 (password rules). Say that explicitly
rather than omitting them.

NOTES.md must also carry: assumptions made, 2 to 3 screenshots of the sharing screens, the
observability signals (one product, one on-call) with what to watch and when someone should act, and
what would come next. Write it as you go; do not reconstruct it at the end.