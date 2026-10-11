# Project memory

Notes that AI agents working on DataDungeon keep for each other: status,
plans, decisions in progress and lessons that are not obvious from the code
or the git history. Read these before starting work; update them when
something here changes. `../config.yml` names this project's agent on the
Arcana bus.

`.ai/` is a git worktree of the repository's orphan `ai` branch, ignored by
the code checkout (moved there 2026-10-11; its history before that is in
the code's history, under `.ai/`). Run git against it (`git -C .ai ...`),
stage by path, never `git add -A`, and push it by name
(`git -C .ai push origin ai`). Notes commits start with "Note". Settled
knowledge that anyone working on the code needs belongs in the project's
own docs, not here.

| File | What it holds |
|---|---|
| [handoff.md](handoff.md) | Current state, what's next, and the longer plan (Infocomic images, semantic search, Memo under load, transfs) |
| [principles.md](principles.md) | DD stays generic, the plain design comes first, working before optimizing |
| [consumers.md](consumers.md) | Infocomic, Cattacula, Pirateship and Silicon Circus: how each builds against DD, and what's left |
| [release.md](release.md) | Tagging releases, the awscr-s3 fork, the local Memo override |
| [performance.md](performance.md) | What keys, tags, vectors, search, paging and the tag planner cost at 1M assets, which benchmark measures each, and why SQL never splices values |
| [coordination.md](coordination.md) | Arcana identity, peers, and the per-message sign-off rule |

Design documents are at the code's root: `DESIGN.md`, `DESIGN-store.md`,
`DESIGN-best-match.md` (built in 0.10.0), `DESIGN-image-fields.md` (built
in 0.11), `NOTES-delete-orphans.md` and `NOTES-list-keys-scope.md`.

Keep each note short and dated (`*Updated YYYY-MM-DD*`), with absolute
dates and commit hashes. Check the code or `git log` before acting on
anything here; notes go stale. Machine-specific facts don't belong here.
Never commit credentials or keys.

## Handling inbox notes

Messages from other agents that didn't come live land in `.ai/mail/inbox/`.
A note in the inbox has not been dealt with yet, so the inbox holds only
unprocessed notes. To process one:

1. Commit the note as it arrived, before anything else, so the original is
   kept in history.
2. Put what matters into the memory notes here, in your own words.
3. Delete the note in a following commit, and cite the commit that still
   has it (`git -C .ai show <commit>:mail/inbox/<file>`).

If a note is reference material that will be consulted again, such as a
spec or a design, move it here as its own file instead of summarizing it.

## Outbound mail

The lead agent (the session holding `@datadungeon`) writes mail on
Thomas's behalf, one file per message named by its address:
`<handle>--<YYYY-MM-DD>-<topic>.md` (`@memo--2026-10-11-schema.md`).

- Every message waits for Thomas (`mail.review: all` in `../config.yml`;
  see coordination.md): it goes to `mail/drafts/` with a `Held: <why>`
  line, and moves to `mail/outbox/` once he approves it.
- Until a delivery process runs on the machine, the lead delivers: it sends
  over Arcana (or, when the recipient can't be reached, into its inbox),
  then moves the file to `mail/sent/` with a `Sent: <date and time> via
  <arcana|inbox>` line. `sent/` is committed and never edited: it is the
  record of what was said.
- Helpers (subagents, other sessions) never send: they put messages in
  `mail/drafts/` with a `By: <who>` line, and the lead reviews them like
  its own.
- Drafts and the outbox are machine-local and never committed. Never write
  into another project's `.ai/` except as its delivery.

## Transcripts

`.ai/transcript/` holds session transcripts written by the agent runtime,
one tagged entry per event (`<E1043 …>…</E1043>`), always redacted before
they're committed. Read them, never edit them; find an entry with
`grep -rn '^<E1043 ' .ai/transcript`.

## Intake

Thomas shares files for the work at hand in `.ai/intake/`. Look there when
starting a session. The files are his: don't commit, move or delete them
unless he asks. `.ai/.gitignore` keeps them out of commits.
