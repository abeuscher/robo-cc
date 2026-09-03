# Sessions

One session = one section of `roadmap.md`. Each session has a **brief** to start and a
**log** to finish.

## Files

- `TEMPLATE-session-brief.md` — copy to `NNN. <Title> — Brief.md` at session start.
- `TEMPLATE-session-log.md` — copy to `NNN. <Title> — Log.md` at session close.
- `NNN. <Title> — Brief.md` / `— Log.md` — the actual session records, kept in git.

## Flow

1. **Draft the brief** (usually at the end of the previous session) from the template and
   the next roadmap pass. Review it together before opening.
2. **`/open-session NNN`** — the agent reads the brief's reading list, then stops at the
   Open Gate for confirmation.
3. **Work** the session. When implementation is done the agent syncs, runs a Studio
   playtest, and reports — then waits.
4. **`/close-session`** — the agent writes the log, updates `roadmap.md`, drafts the next
   brief, and commits on the session branch. No push, no merge to main.

## Branch naming

`session-NNN` (e.g. `session-001`). One branch per session.
