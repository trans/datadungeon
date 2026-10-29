# DataDungeon asset Worker

A Cloudflare Worker that serves content-addressed objects from a **private**
S3/R2 bucket, over your own domain, with signed expiring URLs. It is the
counterpart to `DataDungeon::S3Storage`'s `sign_key` mode (`src/data_dungeon/s3.cr`).

DataDungeon is used as a **library**, embedded in the apps. This Worker is a
separate edge artifact deployed on its own with `wrangler`; it lives here only
so the signer (the app, via DataDungeon) and the verifier (this Worker) share
one scheme and can't drift apart.

**Status: deployed** for Overlore on `assets.overlore.xyz` (`@cyclops`,
2026-10-29), checked end to end against `S3Storage#resolve`'s signatures.

## How it fits together

- The bucket (`dungeon`) is the shared asset store for several products and
  stays **private** — no public access, no `r2.dev`. Objects are
  content-addressed (`hh/<sha256>.<ext>`); non-asset keys like `_index/`
  (the index/backup DBs) share the bucket but are never routable here.
- The app builds asset URLs with `S3Storage` configured with `public_url`
  **and** `sign_key`. `resolve(key)` then returns
  `https://<host>/<object>?exp=<unix>&sig=<hex>`, where
  `sig = HMAC-SHA256(sign_key, "<object>\n<exp>")`, valid for `url_expires`.
- The browser fetches that URL from this Worker's host. The Worker re-computes
  the HMAC, checks `exp`, and only then streams the object from the private
  bucket (no egress charge) with immutable cache headers (edge-cached).

So a leaked/shared URL dies when `exp` passes; rotating `ASSET_SIGNING_KEY`
(both sides) revokes everything at once.

## Deploy (when ready)

1. Confirm the bucket's public access / `r2.dev` is **off** (Cloudflare → R2 →
   bucket → Settings). This Worker is the only read path.
2. Set the shared secret on the Worker:
   `wrangler secret put ASSET_SIGNING_KEY` (32+ random bytes; e.g.
   `openssl rand -hex 32`). Store the same value in the vault.
3. `wrangler deploy`.
4. Point `assets.overlore.xyz` DNS at the Worker (the `custom_domain` route
   provisions the cert). Add more hostnames in `wrangler.toml` as needed.
5. Wire the app: give it `ASSET_SIGNING_KEY` in its env and pass it as
   `sign_key` to `S3Storage` (with `public_url: https://assets.overlore.xyz`
   and an **empty** `prefix` — the Worker serves root-level keys).

Until step 5, `public_url` with no `sign_key` emits plain (unsigned) URLs, and
with no `public_url` DataDungeon falls back to presigned `r2.cloudflarestorage.com`
URLs — either way this Worker is simply unused.

## Notes

- `prefix` must be empty for signed-public mode: the signed subject is the
  object path, and the Worker matches root-level `hh/<sha256>.<ext>`. A
  prefixed layout needs the regex widened to match.
- Range requests (video/large audio) aren't handled yet; add `obj = DUNGEON.get(key, { range })`
  and pass through `Range`/`Content-Range` if a product needs them.
