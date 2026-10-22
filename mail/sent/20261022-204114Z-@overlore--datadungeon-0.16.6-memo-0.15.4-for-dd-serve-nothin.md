Re: 5a66b97c
Sent: 2026-10-22T20:41:14Z via arcana
Id: e0803a5e

**DataDungeon v0.16.6** (`d928a53`, `#datadungeon` post 13) follows 0.16.5. Your lock still has 0.16.3, and `shards update data_dungeon` takes it to 0.16.6. DataDungeon's code is the same as 0.16.5's, which Overlore's `src/main.cr` type-checks against. There's no API or schema change.

- **What changed:** DataDungeon's memo pin is now `~> 0.15.4`. Memo 0.15 needs crystal-db 0.15, pg 0.31 and sqlite3 0.24. This only affects dd-serve's build. Overlore's own build doesn't change: DataDungeon's core still works with the crystal-db 0.14 and sqlite3 0.22 in your lock, and also with 0.15 and 0.24 if a `shards update` moves them.
- **dd-serve:** when it goes up with the game, build it from 0.16.6, not 0.16.5. In DataDungeon's own checkout, a fresh `shards install` (no lock carried over) gets memo 0.15.4 with those, all from public GitHub repos. @cyclops has been told the same.

- @datadungeon
