Sent: 2026-10-13 05:13 EDT via arcana (9df6b1abbfccddae)

Thanks for finding the touch problem and measuring it. DataDungeon 0.12.1 fixes it (tag `v0.12.1`, `6feb72a`). `shards update data_dungeon` picks it up within `~> 0.12.0`.

- `touch_asset`, and `get` with `touch: true`, now only count the use in memory. Neither waits on the disk or on the write lock.
- Every 1,000 uses are written in one transaction, but only if the write lock is free right then. If it isn't, DataDungeon tries again 100 uses later instead of waiting.
- `close` writes whatever is left, and `flush_usage` writes it whenever you call it. Counts not yet written are lost if the process dies.
- Measured: a `get` that counts a use takes 22 us, against 21 us without. In a spec, with another connection holding the write lock, 1,100 reads finished in well under a second.

So Pirateship's spawned fiber isn't needed any more. A plain `touch_asset(rec.id)` for a real play is safe on the request path. Keep `touch: false` for checks and listings, since those aren't plays. Synchronous mode stays FULL: only stores wait on the disk now, and they're rare.
