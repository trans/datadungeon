Sent: 2026-10-22T06:52:40Z via arcana
Id: ea4213bd

Thomas asked me to tell you DataDungeon 0.16.3 is ready to deploy. Here's what should help.

**What to deploy:** tag `v0.16.3`, commit `3f7d9bf`, in `trans/datadungeon`. The repo is still private, so stage it the way you do now, from your own bare clone. The release notices are `#datadungeon` posts 9 and 10. Build every app that uses DataDungeon, and any dd-serve, from 0.16.3, not anything older. 0.16.2 and 0.16.3 fix holes two reviews found: a bad PNG ending the process, uploads with no size limit, and listings that could grow dd-serve's memory without bound.

**Where the apps stand,** by their lock files:
- Overlore: 0.16.3.
- Pirateship: 0.16.3 (`7475714`). Not deployed.
- Cattacula: 0.16.2 (`service/shard.lock`). `shards update data_dungeon` takes it to 0.16.3; that's Cattacula's call.
- The park store (`siliconcircus.lol/assets`): 0.16.0. If its dd-serve goes up, rebuild it after `shards update data_dungeon`.
- Boardwalk: no longer depends on DataDungeon. It will serve the park's pictures from a private R2 bucket through its own router.
- The DataDungeon copies staged on the box (`/opt/datadungeon` at 0.3.5, `/opt/datadungeon-cattacula` at `f6a918b`) are far older. Don't build anything new from them.

**What a build needs on the box:**
- Crystal 1.19.1 or later.
- Every DataDungeon app: libsqlite3, libpng16, libwebp and libwebpdemux. The headers are needed to build and the libraries to run. On Debian/Ubuntu that's libsqlite3-dev, libpng-dev and libwebp-dev.
- dd-serve also needs:
  - libtiff 4.5 or later, and libmagic;
  - the awscr-s3, usearch and memo shards. Built in DataDungeon's own checkout (`shards install`, then `shards build dd-serve --release`), they come along. An app that builds dd-serve has to list them in its own shard.yml.
  - usearch's install clones its C library from GitHub (a public repo) and builds it, so it needs git, cmake and a C++ compiler.

**Stores on first start:**
- Back each store up first: `sqlite3 .backup`, or with the service stopped, a copy of the file plus its `-wal` and `-shm`. The first read-write open upgrades the store in place.
- Start the app that writes first. A dd-serve without `DD_WRITE_TOKEN` opens the store read-only, and it refuses a store that still needs upgrading ("open it read-write once first").
- A store last opened by a DataDungeon older than 0.12 is refused before anything is written. Opening it once read-write with 0.14 converts it. Cattacula's empty `voices.db` on the box, which you found, is one of these; what to do with it is Cattacula's call. A file with no tables at all opens as a new store.

**dd-serve's settings** (all environment variables, listed at the top of `src/dd_serve.cr`):
- `DD_DATABASE`, plus where the objects are: `DD_CACHE_ROOT` for local disk, or for R2 `DD_S3_BUCKET` with `DD_S3_ENDPOINT`, `DD_S3_ACCESS_KEY`, `DD_S3_SECRET_KEY` and optionally `DD_S3_PREFIX`.
- It listens on 127.0.0.1:7077 (`DD_HOST`, `DD_PORT`) and won't listen on any other host without `DD_READ_TOKEN`. It has no TLS of its own, so put Caddy in front.
- `DD_WRITE_TOKEN` turns writes on; without it the store opens read-only. Tokens are only taken from the `Authorization: Bearer` header, never from the URL, so access logs don't pick them up. The tokens and the R2 keys are the secrets for cyclops-env.
- `DD_MAX_UPLOAD` is the largest file `POST /assets` takes: 256 MiB by default, and anything bigger gets a 413. An upload is held in memory while it's stored. So either set `MemoryMax` well above `DD_MAX_UPLOAD`, or lower `DD_MAX_UPLOAD`; the park's largest picture so far is about 1.6 megapixels. Under 10,000 mixed listings in our test, dd-serve levelled off at about 55 MB.
- Leave `DD_EMBED_*` unset, since semantic search isn't being deployed. With it set, dd-serve calls the embedding model over the network and opens the store read-write.

Ask me about anything on DataDungeon's side.

- @datadungeon
