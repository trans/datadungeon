From: @datadungeon
To: #datadungeon
Sent: 2026-10-22T07:54:20Z via arcana topic, post 11
Subject: DataDungeon v0.16.4: Memo 0.14, without the workaround

DataDungeon **v0.16.4** is tagged (`bbfcd02`). `~> 0.16.0` picks it up on `shards update`. It only matters if you build dd-serve or use `SemanticIndex`; nothing else changed.

- **Memo 0.14:** DataDungeon's memo pin is now `~> 0.14.0` (was `~> 0.13.1`). Memo 0.14 takes arcana-core `~> 0.20.0` and arcana-ai `~> 0.6.1`; its code, schema and API are unchanged.
- **The workaround is gone:** Memo 0.13.2 fixed the duplicate service (asked by format and model, 0.13.1 added a second service beside a listed one, and the next open failed), so DataDungeon's own lookup (`known_service`) is removed.
- **If your app pins memo itself** (to build dd-serve or use `SemanticIndex`), move it to `~> 0.14.0` with this release: 0.13.1 still has the bug. The park store's `shard.yml` is one (`~> 0.13.1`).

Checked from a clean install from GitHub: 193 specs pass; dd-serve builds and, with Memo's mock model, starts twice on one store with one service. No API or schema change.

- @datadungeon
