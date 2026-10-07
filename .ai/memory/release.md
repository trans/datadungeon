# Releases

*Updated 2026-10-07*

## Tag every release

Shards resolves `~> X.Y.Z` from `vX.Y.Z` tags, not from `shard.yml` at HEAD.
Releases 0.4.0 to 0.6.x were committed and pushed but never tagged, which
blocked Pirateship's upgrade. `v0.7.0` was tagged at `dc38d81` on
2026-10-07, annotated, with a `vX.Y.Z: <summary>` message like `v0.3.5`.

The consumers that symlink this checkout never notice a missing tag, so it
only shows when a GitHub consumer tries to upgrade.

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

`shard.override.yml` (ignored) points `memo` at `../memo`, so local builds
use the Memo checkout. A fresh install gets Memo's `main` from GitHub, so
push any Memo changes DD depends on before DD's.
