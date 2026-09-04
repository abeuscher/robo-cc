# Template: Session Brief

Copy this file to `NNN. <Title> — Brief.md` at the start of a session and fill in the
placeholders. This is the whole brief — there is no separate base prompt. Delete this
header block in the copy.

---

# Session NNN — <Title> — Brief

**Roadmap section:** Pass N — <name> (`roadmap.md`)
**Branch:** session-NNN

## Goal

One or two sentences: what this session builds and the state the game reaches by the end.

## Reading list

Read these before touching code, in order:

1. `spec.md` — the sections this pass implements (name them).
2. `roadmap.md` — the pass entry for this session, plus §2 Architecture and §5 Physics notes.
3. This brief.
4. Previous session log `sessions/(NNN-1). <Title> — Log.md` — "What was built" and
   "Deferred / carried forward".
5. The `src/` files this session will modify (list them).

## Starting state

One line each — the handoff from the previous session:

- What already exists in `src/` that this session builds on.
- `Config` constants already defined vs. added this session.
- Anything left unfinished or deferred last session.
- Rojo pipeline status (known-good / needs a re-check).

## Plan

The phases of this session — what gets built, not how.

### Phase 1 — ...

### Phase 2 — ...

## Out of scope

What this session deliberately does not touch (usually: later roadmap passes).

## Open questions

Decisions that must be settled before implementation. Omit the section if there are none.

---

## Process rules

- Read every file you intend to modify before editing it.
- All game state and physics is server-authoritative. Clients send intent only; the server
  validates role, phase, and limits on every remote.
- Every tunable lives in `src/shared/Config.luau`. No gameplay magic numbers in logic.
- One ModuleScript per responsibility. `init.*.luau` scripts only bootstrap.
- `src/shared` never requires from `src/server` or `src/client`.
- Match the existing code style. No comments or type annotations on code you did not write.
- Adapt silently to small drift between this brief and the code; note it in one line. Pause
  and ask only for decisions that are expensive to reverse — data shape, new abstractions,
  changes to the arena or physics model.
- A question from the user is a question, not an instruction to act.
- When implementation is done: sync in Studio, run a two-player playtest, report what you
  saw. Then stop — do not start the close until the user says so.

---

## Session Open Gate

After the reading list is done and before any code: post a short orientation — the session
shape, the work plan, anything that needs clarifying — and wait for the user to confirm. Do
not pipeline from reading straight into implementation.

---

## Session Close Gate

The next session's brief should already be drafted from `sessions/TEMPLATE-session-brief.md`
before `/close-session` is run — that command's own precondition checks for it and stops if
it's missing, rather than drafting it itself. Everything below happens only when the user
explicitly runs `/close-session`:

1. Write this session's log at `sessions/NNN. <Title> — Log.md` from
   `sessions/TEMPLATE-session-log.md` — copy its structure exactly.
2. Update `roadmap.md` if the pass's scope shifted; mark the pass done.
3. Confirm the next session's brief exists.
4. Commit on the `session-NNN` branch. Never push, never merge to main.
