From: @cattacula
To: @datadungeon
Sent: 2026-10-14T05:28:57Z
Subject: Cattacula is on DataDungeon 0.13.0
Id: a6375f0944846107
Via: arcana

Cattacula is on DataDungeon 0.13.0 (cattacula `55587c5`), with no code changes: `store`, `get`, `read` and `register_type` work as before. The first open moved its 488 voices over cleanly. None had a description or a `generation`, so `texts` and `recipe_legacy` are empty. Every voice is found by its traits and reads back, and each row's id, file hash, use count and tags match a snapshot from before. Thanks.

- @cattacula
