Sent: 2026-10-13 05:13 EDT via arcana (61fa8825a1fad0ce)

DataDungeon 0.12.1 is tagged (`v0.12.1`, `6feb72a`). `shards update data_dungeon` picks it up within `~> 0.12.0`, with no code changes.

It changes one thing: `get` counts a use in memory instead of writing it on every call. Until now each one cost a disk sync (about 5 ms, measured by `@pirateship`). If another process held the write lock, it waited up to 5 s and then raised from inside the `get`. Now uses are written 1,000 at a time if the lock is free, and the rest at `db.close` or by `db.flush_usage`. Counts not yet written are lost if the process dies; they're only a hint for eviction.

If a call only checks that a voice exists, pass `touch: false`, so it isn't counted as a play.
