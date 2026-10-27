# Backups: a store's database in the cloud

*Draft 2026-10-25, with Thomas. Not built. Snapshots, not Litestream
(Thomas, 2026-10-25). Where they go is open: `@cyclops` is asked about
the `backup` bucket.*

## Why

A store is its SQLite file plus its files in storage. The files are in R2,
kept once by their hash, in a shared bucket no store deletes from. The
database is only on the app's server, and it's the record: descriptions,
wordings, recipes, tracks, ratings, tags, links and registrations exist
nowhere else. Lose it and the bucket is a heap of files named by hash. So
the first job is to get the database into the cloud too (Thomas,
2026-10-25).

## Snapshots

- **Snapshots, not streaming** (Thomas, 2026-10-25). Litestream was
  weighed: it streams changed pages to R2 every second and restores to any
  second in its window, but it's another process on the box, with its own
  layout. A snapshot can lose up to an interval's work, and is one file to
  keep, check and restore.
- **A consistent copy:** `VACUUM INTO` a scratch file while the app runs,
  compacted as it goes. Copying the live file could miss what's still in
  `-wal`, or catch it mid-write. Then gzip (Crystal's standard library, no
  new dependency), and the SHA-256 of the bytes uploaded.
- **Only the database:** Memo's index and the match files beside it are
  rebuilt from it when they're missing (Memo's from the vectors it stores,
  the match files from tags). The embeddings are in the database
  (`memo_vectors`, 16-bit floats), so a restore calls no embedding API.
- **Nothing is uploaded** when the hash is the last backup's.

## Names: time, then hash

    <where>/<store>/2026-10-25T120000Z-<sha256>.db.gz
    <where>/<store>/2026-10-25T120000Z-<sha256>.keys

- **A hashed file** (Thomas: "Not sure why it can't be a hashed file
  too"): the hash names it and checks it after a download.
- **The time first** (Thomas found that compelling) makes a listing the
  history, oldest first, the last name the latest backup. Nothing has to
  hold "the last hash": the listing gives it.
- **Its key list beside it:** the object keys its rows use (`object_keys`),
  one a line, for the cleanup (below), which then reads lists, not
  databases.
- **The store records its backups too** (time, key, hash, size), so an app
  or `@curio` can show the last one. That's a convenience, not the record:
  a snapshot can't hold its own entry, and a list inside a lost database is
  lost with it. The bucket is the record.

## Where: open

Asked of `@cyclops`, 2026-10-25:

- **The `backup` bucket,** by project (`backup/overlore/`), which Thomas
  already has. Its own credentials: an app's asset key couldn't touch its
  backups, but a backup key is one more secret on the box.
- **An `index/` path in the assets bucket** (`index/overlore/`,
  `index/park/`): every program keeping a store of the bucket's files (an
  index of them; Overlore isn't the only one) puts its database there,
  beside the files, with the credentials it already has. One bucket then
  holds everything a restore needs. It could also be where each store
  registers itself for the hub (its name, where it's served, when last
  opened; DESIGN-types, "Pruning, eviction and shared files"). The
  boardwalk's router serves the bucket's files by key and mustn't serve
  `index/`: a database holds prompts, recipes and costs.

## Nothing deletes what it doesn't know

Thomas, 2026-10-25: "Nothing should [ever] delete something if it doesn't
know what it is."

- **Vacuum doesn't keep that today.** `vacuum(delete_orphan_objects: true)`
  deletes every key under its storage's root that no row uses, whatever it
  is (`check_consistency` lists them as orphans). Shared storage refuses
  it, so the R2 bucket is safe, but a backup, a key list or anything else
  under an unshared store's root would go. The fix: vacuum, and the
  orphans it's given, count only keys of DataDungeon's own shape,
  `xx/<sha256>.<ext>`, `xx` the hash's first two characters. It's small,
  and can come before backups.
- **The hub's clearing** of the shared bucket keeps the same rule: asset
  objects only, never `index/` or anything else it doesn't know.

## Cleaning up

Two collections, linked.

- **Old backups** go by a retention policy, once Thomas is sure no
  rollback to them is needed ("eventually we will want to GC old versions,
  when we are sure no rollback will ever be necessary"). Until there's a
  policy, nothing deletes a backup. Dropping one drops its database and
  its key list.
- **Asset files:** restoring a backup needs every file it names. That
  holds now, since nothing deletes from the shared bucket. When the hub
  clears it, a file goes only when no store's list and no kept backup's key
  list names it. Once a backup is dropped, the files only it named go on
  the next run.

## Running it

- `DB#backup`: snapshot, gzip, hash, upload the database and its key list,
  and record it, through the storage DataDungeon already has for R2, or a
  second one for the backup bucket.
- dd-serve: `POST /maintenance/backup`, with the write token.
- A timer on the box calls it (`@cyclops`'s side).
- Restoring: stop the app, download, check the hash, gunzip, put it in
  place, start. An older database is upgraded on its first read-write open,
  as any is.

## Open

- Where (above), and the credentials it takes.
- How often, and the retention policy.
- The `<store>` in a name: the project's (`overlore`) or the store's
  consumer name.
- A restore command: dd-serve's, or a script.
