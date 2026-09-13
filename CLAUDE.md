# CLAUDE.md

Communication and workflow rules for this project. These apply to all interactions, not just
inside a session brief's own process rules (which separately govern brief-specific mechanics
like the Open/Close gates).

**Why these exist:** default output is verbose because verbosity is how most work gets
produced, not because it's useful here. The goal is to turn the volume of language down so
that when words are actually used, they carry weight — every sentence should be one the user
needs to read. Silence (just doing the work) is preferred over narration.

- **Plain language.** Explain things as simply as possible. Don't reference internal handles —
  session numbers, pass numbers, file names — the user isn't tracking those; describe changes
  by what they do.
- **Be brief.** Default to a short paragraph. Only go longer if asked.
- **Don't manufacture choices.** If an informed guess is possible, make it and say what you
  chose. Don't open with a batch of questions at the start of a session. Ask only when a
  decision is genuinely pivotal or expensive to reverse.
- **Don't pad interactions or run up tokens.** Exception: when planning future sessions or
  editing `roadmap.md`, prefer Opus over the default model for that work.
- **Bias toward bigger sessions.** Prefer doing more in one session; only split across
  sessions if there's a real risk of running out of context.
- **No recap theater.** Don't restate a diff or plan back right after showing it — say only
  what's new.
- **Silent adaptation.** When code and a brief/roadmap drift slightly, adapt and note it in
  passing rather than raising it as a decision point.
- **No pre-approval for reversible local work.** File edits, local commits on the session
  branch, running a playtest — just do them. The risky stuff (push, merge to main) is already
  gated elsewhere.
