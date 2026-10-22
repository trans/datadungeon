# Releases

*Updated 2026-10-20*

## Tag every release

Shards resolves `~> X.Y.Z` from `vX.Y.Z` tags, not from `shard.yml` at HEAD.
Releases 0.4.0 to 0.6.x were committed and pushed but never tagged, which
blocked Pirateship's upgrade. `v0.7.0` was tagged at `dc38d81` on
2026-10-07, annotated, with a `vX.Y.Z: <summary>` message like `v0.3.5`,
and `v0.8.0` at `d01f4ec` the same day; `v0.9.0` at `2b79d46` on
2026-10-08; `v0.10.0` at `7618531` on 2026-10-09; `v0.11.0` at `9279ff1` the same day, `v0.11.1` at `e0e3a42` (image fields, media, `pool:` ignored), `v0.11.2` at `0ffdcac` (curio's list rows and view counts) on 2026-10-10. `v0.12.0` at `2698701` on 2026-10-11 (registration required, the type's own key an index, ranking by rating); `v0.12.1` at `6feb72a` on 2026-10-13 (uses counted in memory), `v0.12.2` at `616b752` the same day (written a hundred at a time, and at exit; a fresh `~> 0.12.0` install resolves it). `v0.13.0` at `ec9298e` on 2026-10-14 (recipes, descriptions as shared texts, cost basis, shared storage; a fresh `~> 0.13.0` install resolves it), `v0.13.1` at `4df221b` the same day (named texts take a purpose; a fresh `~> 0.13.0` install resolves it); `v0.14.0` at `401dd4a` on 2026-10-17 (the prompt as sent, the wordings in it, the ratings' words; no standard styles; a fresh `~> 0.14.0` install resolves it); `v0.15.0` at `58f1fa6` the same day (a cleanup: the purpose removed, `recipe_fields` dropped, no conversions from before 0.12; a fresh `~> 0.15.0` install resolves it); `v0.15.1` at `f9c4bc6` on 2026-10-19 (pictures added by hand, `POST /assets`; a fresh `~> 0.15.0` install resolves it); `v0.15.2` at `c7fb237` the same day (DataDungeon's asset types and the `subtype` tag; re-registering without `rekey` for what keys don't hold; a match index clears renamed types' files; a fresh `~> 0.15.0` install resolves it); `v0.15.3` at `7cca94a` the same day (a take's tracks; `rename_type` writes nothing once done; a fresh `~> 0.15.0` install resolves it; notice: `#datadungeon` post 2); `v0.15.4` at `a229a4a` on 2026-10-20 (TIFF masters with `data_dungeon/tiff`, `store_webp`, 16-bit PNGs read as stored; a fresh `~> 0.15.0` install resolves it and builds with the TIFF require; notice: post 3). `v0.15.5` at `5ad4fe9` the same day (deleting a transcript a clip names; where a recording's words go, in DESIGN-types; README's transfs figures; a fresh `~> 0.15.0` install resolves it and builds with the TIFF require; notice: post 4). `v0.15.6` at `8236d73` the same day (`map` renamed `pass`; `prop` and `transcript` reworded; a fresh `~> 0.15.0` install resolves it; notice: post 5). `v0.15.7` at `e31e97e` the same day (semantic search: `register_type(…, embed:)`, statements, one model per store, `catch_up`, dd-serve's `/search` with `DD_EMBED_MODEL`/`DD_EMBED_KEY`, needing memo `~> 0.13.1` and libmagic to build; `transcript` reworded; a fresh `~> 0.15.0` install resolves it and builds; notice: post 6). `v0.16.0` at `2f9d585` the same day (only DataDungeon's asset types: `register_type`, `rename_type`'s target and storing refuse others; `transcript_id` kept, deprecated; specs, benches and README on standard names; a fresh `~> 0.16.0` install resolves it and refuses `room`; notice: post 7; `@overlore` told separately, `f16f35f5`). `v0.16.1` at `6ae9fb0` on 2026-10-21 (wording only: `prop`'s "not a set or a figure" is about 3D models; `figure` also 2D on bones, media model and data; characters on the to-do list; a fresh `~> 0.16.0` install resolves it; notice: post 8). `v0.16.2` at `cb0a356` the same day (fixes from a Codex review: a bad PNG with `compression` no longer aborts; `ImageProbe.max_pixels` before any decode allocates; `max_upload`/`DD_MAX_UPLOAD` with 413; registration refresh under the lock; `store_webp` cleans up after a failed link; `catch_up` refreshes on its first pass; `data_dungeon/tiff` requires the core; a fresh `~> 0.16.0` install resolves it; notice: post 9). `v0.16.3` at `3f7d9bf` the same day (from a security review: `list_assets`/`count_assets` through `DB#uncached`, since crystal-db caches every prepared statement and listing SQL varies with the filters; a fresh `~> 0.16.0` install resolves it; notice: post 10). `v0.16.4` at `bbfcd02` on 2026-10-22 (memo `~> 0.14.0`, `known_service` removed: Memo 0.13.2 fixed the duplicate service; checked from a clean GitHub install with no path dependencies; a fresh `~> 0.16.0` install resolves it; notice: post 11; `@cyclops` told to build from it, `efa24520`). From 0.15.3 on, the release notice is a post on the `#datadungeon` topic (coordination.md), not a message to each app. 0.7.1-0.7.3 were held and never tagged. `~> 0.7.0`
(Pirateship) doesn't reach 0.8, and `~> 0.8.0` (the park store) doesn't
reach 0.9.

`scripts/garage-test` once failed to start Garage ("Unable to connect to
destination RPC host") and passed on a retry with another
`DD_GARAGE_PORT`: a startup race in the script, not yet fixed.

The consumers that symlink this checkout never notice a missing tag, so it
only shows when a GitHub consumer tries to upgrade.

v0.11.0 was pushed to GitHub's main from the worktree branch
(`keys-and-retiring`) without moving this checkout, which stayed at
`c7e5b48` so Overlore, still building from it, kept 0.10 until it moves to
GitHub (Thomas's call, 2026-10-09: consumers stop linking). Fast-forward
this checkout (`git merge --ff-only origin/main`) once it has. Done
2026-10-09, after Overlore's `889c4fa`; Cattacula still links here.

v0.12.0 went the same way, 2026-10-11: pushed to GitHub's main from the
worktree branch (`registration-required`), this checkout left at
`f8a0898` (0.11.2's code), because Cattacula still builds from it
(`path: ../../../datadungeon`) and 0.12's first open upgrades its
`voices.db` one way. Fast-forward this checkout when Cattacula has moved
to GitHub, or when Thomas says. **Cattacula moved 2026-10-12** (its
`9fe2421`), so nothing links here now. **Fast-forwarded to `2698701`
2026-10-13**, with Thomas's go-ahead.

When a commit that bumps `shard.yml`'s version is pushed, offer to tag and
push `vX.Y.Z` too (tag pushes are outward-facing, so confirm first). Check
that a fresh `shards install` in the scratchpad resolves it.

## awscr-s3 fork

`S3Storage` (`data_dungeon/s3`, optional; `S3Storage.r2` for R2) uses
`awscr-s3`, chosen 2026-10-07. DD handles three things itself: a pooled HTTP
client factory (upstream leaves pooling to users, issue #77), retry with
backoff on 429/503 SlowDown, and an `exists?` that reads the HTTP status.

The status gap is fixed in Thomas's fork, `github.com/trans/awscr-s3`
(cloned at `~/Projects/awscr-s3`, remote `upstream` is taylorfinnell),
branch `exception-status`, commit `ce5be24`. It adds
`status : HTTP::Status?` to `S3::Exception` and is open upstream as
**taylorfinnell/awscr-s3#168**. DD's `development_dependencies` use the
fork's branch until that's merged and released; then go back to upstream.
Check the PR's status before relying on upstream.

Upstream's full spec run crashes with "File not open for writing" on
unmodified master too (the integration spec wants MinIO from
`spec/integration/compose.yml`); run its unit specs file by file.
`scripts/garage-test` runs DD's own S3 specs against a throwaway Garage.

## Two upstream bugs S3Storage works around

Found 2026-10-07 (0.7.2), not yet reported upstream; Thomas decides.

- **awscr-s3:** `S3::Exception.from_response` does
  `XML.new(response.body || response.body_io)`. A streamed response's
  `body` is an empty string, which is truthy, so `body_io` is never read:
  a streamed GET of a missing object raises `XML::Error` ("Document is
  empty") instead of the status, and leaves the error body unread on the
  connection. S3Storage now does its own GET (`S3Storage#get`).
- **Crystal 1.21 `HTTP::Client`:** an exception raised inside `exec`'s
  block is caught and turned into a `break`; `retry_once` then sees no
  result, takes it for a stale connection and, on a reused connection,
  sends the request again, running the block twice. `S3Storage#get` raises
  nothing out of the block.
- Also: with a block, `HTTP::Client` closes an unread body without
  draining it and keeps the connection, so a pooled client must read each
  response to the end or close the connection.

## Local Memo

Memo lives at `github.com/openbohemians/memo` (moved from `trans/memo`
2026-10-07; GitHub redirects the old URL). `shard.override.yml` (ignored)
points `memo` at `../memo`, so local builds use the Memo checkout. A fresh
install gets Memo's `main` from GitHub, so push any Memo changes DD depends
on before DD's.

Memo 0.13 (main `8ecd4a5`, 2026-10-11; tagged `v0.13.0` at `5f51edd`, a changelog date and a spec fix on top) stores each distinct text once
(`memo_contents`; `memo_texts` is gone) and needs `arcana-ai` ~> 0.4 and
`arcana-core` ~> 0.16 (`shards update memo arcana-core arcana-ai arcana`).
It migrates a database's memo tables once, on first open, one way. DD's
spec reads `memo_contents` since `17d795f`. No DD consumer uses
`SemanticIndex`, so no stored database was affected.

Memo 0.13.1 (2026-10-14; main `6794fea`) reads token counts from `usage`,
since arcana-ai 0.6.0 drops `total_tokens`, and needs `arcana-ai` ~> 0.5.1.
DD's local lib had arcana-ai 0.4.0, so building with Memo's working tree
failed until `shards update arcana-ai` (0.5.3, done 2026-10-14; `shard.lock`
isn't committed). 162 specs pass with it. Nothing else in Memo changed for
DD (`@memo`).
