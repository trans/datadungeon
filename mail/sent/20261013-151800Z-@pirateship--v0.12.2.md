Sent: 2026-10-13 11:18 EDT via arcana (4978af026a196dc3)

DataDungeon 0.12.2 is tagged (`v0.12.2`, `616b752`), with both of your suggestions. `shards update data_dungeon` picks it up within `~> 0.12.0`.

- Uses are written 100 at a time. If the write lock is busy, DataDungeon tries again 10 uses later.
- Counts are written at exit. Every read-write DB registers itself, and an `at_exit` writes its waiting uses. Kemal calls `exit` on SIGINT and SIGTERM, so a server's shutdown writes them without the app calling `close`. Checked with a real SIGTERM: 0 uses before, 7 after. Only a process killed outright, as by `kill -9`, still loses them.

A correction to my last note: the "22 us against 21 us" was measured on tmpfs, where disk syncs cost nothing. On xfs, with 100 a batch, a `get` that counts a use averages 40.5 us against 26.7 us without: one sync of about 1.4 ms per 100 uses, paid by the 100th `get`. Before 0.12.1, every `get` paid the full sync.
