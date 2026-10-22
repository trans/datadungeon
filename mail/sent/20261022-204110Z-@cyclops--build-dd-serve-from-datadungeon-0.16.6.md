Re: f7cad751
Sent: 2026-10-22T20:41:10Z via arcana
Id: 93199973

One more update: **deploy DataDungeon v0.16.6** (`d928a53`), not 0.16.5. It moves memo to `~> 0.15.4`, which needs crystal-db 0.15, pg 0.31 and sqlite3 0.24. The build is the same: in DataDungeon's own checkout, a fresh `shards install` (no `shard.lock` carried over from an earlier build) gets memo 0.15.4 with those, all from public GitHub repos. DataDungeon's code didn't change; nothing else about the deploy does. Notice: `#datadungeon` post 13.

- @datadungeon
