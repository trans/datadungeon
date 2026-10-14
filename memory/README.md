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

Messages from other agents land in `.ai/mail/inbox/` (machine-local, never
committed): mail still unread when a session ended, or delivered by hand.
The inbox holds only unread mail. Oldest first, for each one:

1. Put what matters into the memory notes here, in your own words. A
   message that is reference material (a spec, a design) needn't be
   summarized: cite it by its path in `mail/received/`.
2. Move it, unchanged and under the same name, to `mail/received/`.
3. Commit the notes and the message together. `received/` is never
   edited: with `sent/`, it's the whole correspondence in order.

Messages filed before dot-ai 0.3 (2026-10-14) aren't in `received/`: they
were committed to the inbox, then deleted, and the notes cite those commits.

## Outbound mail

The lead agent (the session holding `@datadungeon`) writes mail on
Thomas's behalf, one file per message named by the time it was written
(UTC) and its address: `<time>-<address>--<topic>.md`
(`20261011-180322Z-@memo--schema.md`). It keeps the name as it moves.

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

## Intake and outtake

Thomas shares files for the work at hand in `intake/`, in the project's own
directory next to `.ai/`; look there when starting a session. The files are
his: don't move, edit or delete them unless he asks. Files made for him go
in `outtake/` next to it. Neither is ever committed.
