# Project memory

Notes that AI agents working on DataDungeon keep for each other: decisions,
plans, and lessons that are not obvious from the code or the git history.
Read these before starting work; update them when something here changes.
`../config.yml` names this project's agent on the Arcana bus.

| File | What it holds |
|---|---|
| [handoff.md](handoff.md) | Current state, what's next, and the longer plan (Infocomic images, semantic search, Memo under load, transfs) |
| [principles.md](principles.md) | DD stays generic, the plain design comes first, working before optimizing |
| [consumers.md](consumers.md) | Infocomic, Cattacula, Pirateship and Silicon Circus: how each builds against DD, and what's left |
| [release.md](release.md) | Tagging releases, the awscr-s3 fork, the local Memo override |
| [performance.md](performance.md) | What keys, tags, vectors, search and paging cost at 1M assets, and which benchmark measures each |
| [coordination.md](coordination.md) | Arcana identity, peers, and the per-message sign-off rule |

Design documents are at the repo root: `DESIGN.md`, `DESIGN-store.md`,
`NOTES-delete-orphans.md` and `NOTES-list-keys-scope.md`.

Keep each note short and dated (`*Updated YYYY-MM-DD*`), with absolute
dates and commit hashes. Check the code or `git log` before acting on
anything here; notes go stale. Machine-specific facts don't belong here.

## Handling inbox notes

Other agents leave notes in `.ai/inbox/`. A note in the inbox has not been
dealt with yet, so the inbox holds only unprocessed notes. To process one:

1. Commit the note as it arrived, before anything else, so the original is
   kept in history.
2. Put what matters into the memory notes here, in your own words.
3. Delete the note in a following commit, and cite the commit that still
   has it (`git show <commit>:.ai/inbox/<file>`).

If a note is reference material that will be consulted again, such as a
spec or a design, move it here as its own file instead of summarizing it.
The repo is private, but don't commit credentials or keys from a note.

## Intake

Thomas shares files for the work at hand in `.ai/intake/`. Look there when
starting a session. The files are his: don't commit, move or delete them
unless he asks.

## Arcana

Outbound Arcana messages need Thomas's go-ahead, message by message: draft
and offer, then wait. Reading and receiving mail is fine. See
coordination.md.
