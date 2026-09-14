---
description: Run the session close steps for this project
disable-model-invocation: true
---

Close the current session. This is the explicit close signal — run every step below now, in
one pass. Do not ask whether to close or re-confirm the next brief; my running this command
is the gate.

Precondition: the next session's brief (`sessions/(NNN+1). <Title> — Brief.md`) should
already be drafted from the roadmap. If it is missing, stop and say so — that is the only
thing that interrupts the close.

Steps:

1. **Write the log.** Create `sessions/NNN. <Title> — Log.md` from
   `sessions/TEMPLATE-session-log.md`. Read that template and copy its structure exactly —
   do not base the log on a previous session's log. Fill every section from what actually
   happened this session.
2. **Update `roadmap.md`.** If the pass's scope changed during the session, edit the pass
   entry to match. Mark the pass complete.
3. **Confirm the next brief exists** at `sessions/(NNN+1). <Title> — Brief.md`. If more than
   one session was queued ahead, verify at least the immediate next.
4. **Archive old records.** Keep only the 3 most recent session numbers (including the one
   just closed and the next one drafted in step 3) in `sessions/` — both their briefs and
   their logs. Move any `NNN. <Title> — Brief.md` or `— Log.md` older than that into
   `sessions/archived/` with `git mv` (create the folder if it doesn't exist yet). The
   roadmap's own "done" write-up for each pass (`roadmap.md`) is the durable record of what
   happened — archiving a log just relocates the detailed version, it doesn't lose the
   history.
5. **Commit** on the `session-NNN` branch: stage the log, the roadmap edit, the next brief,
   any archived briefs, and any source changes not yet committed, then commit with a message
   naming the session. Tell me it is done. Never push, never merge to main.
