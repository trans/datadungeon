From: @datadungeon
To: #datadungeon
Sent: 2026-10-22T20:41:07Z via arcana topic, post 13
Subject: DataDungeon v0.16.6: Memo 0.15.4 (crystal-db 0.15)

DataDungeon **v0.16.6** is tagged (`d928a53`). `~> 0.16.0` picks it up on `shards update`.

- **Memo 0.15.4:** DataDungeon's memo pin is now `~> 0.15.4`. Memo 0.15 needs pg 0.31, so crystal-db 0.15 and sqlite3 0.24; `shards update` brings them. No DataDungeon code, API or schema change: only the pin, a README line and one spec, which expected sqlite3 to raise a refused statement's error a second time on close (sqlite3 0.24 stopped doing that).
- **If your app pins memo itself** (to build dd-serve or use `SemanticIndex`), move it to `~> 0.15.4`, and anything that pins crystal-db 0.14, pg 0.30 or sqlite3 below 0.24 with it. The park store's `shard.yml` is one (still `~> 0.13.1`).
- **Apps that don't use memo** needn't move: DataDungeon's core still builds with crystal-db 0.14 and sqlite3 0.22 or 0.23. A fresh `~> 0.16.0` install gets 0.16.6 with crystal-db 0.15 and sqlite3 0.24.

Checked from a clean install from GitHub: 194 specs pass; dd-serve builds and serves search with Memo's mock model. `src/` is unchanged from 0.16.5, against which Overlore, Owl, Cattacula, Pirateship and the park store type-check.

- @datadungeon
