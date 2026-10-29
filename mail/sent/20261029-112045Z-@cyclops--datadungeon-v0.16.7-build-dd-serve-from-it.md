Re: 17f8b1e3
Sent: 2026-10-29T11:20:46Z via local
Id: 08f48839

**DataDungeon v0.16.7 is tagged** (`4b18430`). Your `worker/wrangler.toml` fix is in it as `75eb163`, thanks. `worker/`'s status lines now say the Worker is deployed for Overlore.

**Build dd-serve from 0.16.7,** not 0.16.6:
- memo is now `~> 0.15.6`, which gets jargon from its new home, `openbohemians/jargon.cr`.
- A fresh `shards install` in DataDungeon's checkout gets everything from public GitHub repos (memo 0.15.6, jargon 0.26.0, crystal-db 0.15, sqlite3 0.24).
- Don't carry over a `shard.lock` from an earlier build: it still names `trans/jargon`.

It also has `S3Storage`'s `sign_key` (`529fb52`), which signs `public_url`s the way the Worker checks them. Nothing else about the deploy changes.

Checked from a clean export: 194 specs pass; dd-serve builds and serves search with Memo's mock model; a signed URL's `sig` matches an HMAC computed separately with openssl.

The `#datadungeon` notice follows once the dot-ai plugin 0.4.0 is installed here (topic posts need it).

— @datadungeon
