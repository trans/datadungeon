# Backups: a store's database in the cloud

*Draft 2026-10-25, rewritten 2026-10-28, with Thomas. Not built.
Snapshots, not Litestream (Thomas, 2026-10-25). A snapshot is an object
like any other, kept by its hash in the assets bucket, and found by a name
in a `names` bucket (Thomas, 2026-10-28; `@cyclops` reports the same model
settled with him, e4b649f0).*

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
  new dependency) with the header's time set to zero, since the default is
  the time of writing and would make every snapshot a new object.
- **Only the database:** Memo's index and the match files beside it are
  rebuilt from it when they're missing (Memo's from the vectors it stores,
  the match files from tags). The embeddings are in the database
  (`memo_vectors`, 16-bit floats), so a restore calls no embedding API.
- **A readable export** of the same store, files to diff and keep in git,
  is DESIGN-export (2026-10-27).

## Everything is an object; names find them

Thomas, 2026-10-28: "everything is cas. everything. to find something by
name requires indexing by name", so a `names` bucket "could have files with
regular names that just contain a hash that point to the actual asset in
dungeon/". That's git's shape (objects by hash, refs that name them) and
transfs's (blobs by SHA-256, names in a log, SQLite a rebuildable index).

- **The snapshot is an object** in the assets bucket (`dungeon`), by the
  SHA-256 of the gzipped bytes: `xx/<sha256>.db.gz`, `xx` the hash's first
  two characters, as every asset object is. The hash names it and checks
  it after a download (Thomas: "Not sure why it can't be a hashed file
  too").
- **Its key list is an object too,** `xx/<sha256>.keys`: the object keys
  the snapshot's rows use (`object_keys`), sorted, one a line. The cleanup
  (below) reads lists, not databases.
- **A name points at them,** in the `names` bucket:
  `<project>/<database file>`, so `overlore/assets.db`. It's a short text
  file, one line per backup, the newest last:

      2026-10-25T120000Z <snapshot's sha256> <key list's sha256>

  The last line is the current backup and the lines above are the history,
  so the name is its own log. Restoring an older backup is reading an
  earlier line. Thomas found the time first compelling; it's still first.
- **Nothing new, nothing written:** when the snapshot's hash is the last
  line's, the backup stops there.
- **Order:** both objects are written before the name, so a name never
  points at an object that isn't there.
- **One writer per name** (the app's timer). S3 can't append: a backup
  reads the name, adds its line and writes the whole file back. A
  conditional write (`If-Match` on the name's ETag) would refuse a lost
  update; whether R2 takes it on PUT is to check.
- **The assets bucket holds only objects by hash.** No `_index/` or other
  prefix (Thomas leaned toward `_index/`, 2026-10-28, before this). The
  `names` bucket is never served: the asset Worker in `worker/` (deployed
  for Overlore, 2026-10-29) binds only the assets bucket.
- **The Worker must never serve a snapshot or a key list,** even signed: a
  database holds prompts, recipes and costs. It serves any
  `hh/<sha256>.<ext>` with a valid signature, and apps sign only asset
  keys. Its pattern takes one extension, so `.db.gz` already fails it, but
  `.keys` passes. How to make that a rule is to settle with `@cyclops`
  (Thomas, 2026-10-29): a list of the extensions it serves (every new asset
  type then needs a Worker change), or assets with one extension and
  everything else with two (`.db.gz`, `.keys.gz`), which needs none.
- **Names, limited for now:** backups, and the export if it goes to R2.
  DataDungeon goes on naming assets by type and key in its database. A
  name for every asset would be a second index of what the store holds,
  which is the transfs direction, later. Names could also be where each
  store registers itself for the hub (DESIGN-types, "Pruning, eviction and
  shared files").

## Nothing deletes what it doesn't know

Thomas, 2026-10-25: "Nothing should [ever] delete something if it doesn't
know what it is."

- **Names are the roots.** An object stays while any store's rows, or any
  line of any name, reaches it: a line reaches its snapshot, its key list,
  and every object the list names. A snapshot looks like any other object
  and no store row names it, so a collector that read only the stores
  would take it for an orphan.
- **No collector deletes a name,** or a line of one. Only the name's owner
  trims it (the retention policy, below).
- **Vacuum doesn't keep this today.** `vacuum(delete_orphan_objects: true)`
  deletes every key under its storage's root that no row uses, whatever it
  is (`check_consistency` lists them as orphans). Shared storage refuses
  it, so the R2 bucket is safe, but under an unshared store's root a
  snapshot, a key list or anything else would go. The fix:
  - count only keys of an object's shape, `xx/<sha256>.<ext>`;
  - count what the names reach as used;
  - until vacuum can read names, refuse to delete orphans where backups
    are kept.

  The first part is small, and can come before backups.
- **The hub's clearing** of the shared bucket keeps the same rules: objects
  only, names as roots.

## Cleaning up

- **Old backups** go by a retention policy, once Thomas is sure no
  rollback to them is needed ("eventually we will want to GC old versions,
  when we are sure no rollback will ever be necessary"). The policy trims
  a name's oldest lines. Until there is one, nothing is trimmed.
- **What a trimmed line reached** (its snapshot, its key list, the asset
  files only it needed) goes on the collector's next run, if nothing else
  reaches it. Restoring a kept backup needs every file its list names, and
  the roots keep them. Today nothing deletes from the shared bucket at all.

## Running it

- `DB#backup`: snapshot, gzip, hash; write the snapshot and its key list
  as objects through the storage DataDungeon already has for R2; then add
  the line to the name, through a second storage for the `names` bucket.
- dd-serve: `POST /maintenance/backup`, with the write token.
- A timer on the box calls it (`@cyclops`'s side).
- Restoring: stop the app, read the name's last line (or an earlier one),
  download the snapshot, check its hash, gunzip, put it in place, start.
  An older database is upgraded on its first read-write open, as any is.

## Later

- **Pages, not files:** transfs stores a SQLite file as page-sized chunks,
  so a new version adds only the pages that changed. A snapshot stored that
  way (its pages as objects, a list of them as the snapshot) would make
  frequent backups nearly free.

## Open

- The `names` bucket isn't created yet (`@cyclops`, 2026-10-29). R2
  tokens scope to one bucket and a key prefix, so each app's key can write
  only its own project's names; that's why `names` is a bucket of its own
  and not a prefix in `dungeon`. The `backup` bucket is another project's
  (encrypted database dumps) and isn't used here.
- How often, and the retention policy.
- The name: the project and the database file's name (`overlore/assets.db`),
  or the store's consumer name.
- The name file's format: plain lines here; perhaps C0DATA, as for the
  export.
- A restore command: dd-serve's, or a script.
