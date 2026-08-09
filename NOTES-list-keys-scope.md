# Note: `Storage#list_keys` treats the whole root as asset objects

**Status:** by design as of v0.3.5 (`dd8dfb1`). A caveat for `vacuum`, not a bug.

## The caveat

`LocalStorage#list_keys` (`src/data_dungeon/storage.cr`) returns **every regular
file under the storage root**, recursively, as an object key:

```crystal
def list_keys : Array(String)
  return [] of String unless Dir.exists?(@root)
  base = Path[@root]
  keys = [] of String
  Dir.glob(File.join(@root, "**", "*")) do |path|
    next unless File.file?(path)
    keys << Path[path].relative_to(base).to_s
  end
  keys
end
```

It does not know which files are DataDungeon-written objects and which are not.
Anything else living under that root — stray files, another app's data, editor
temp files — is reported by `check_consistency` as an `orphan_object` (a blob
with no owning row).

## Why it matters

Report-only (`check_consistency`, no-arg `vacuum`) this is harmless — foreign
files just show up in the orphan list. But:

```crystal
db.vacuum(delete_orphan_objects: true)
```

will `Storage#delete` every one of them. If the storage root is shared with
anything else, this **deletes those unrelated files**.

## How to stay safe

- **Give DataDungeon a dedicated storage root** that holds nothing but DD
  objects. The default/test layout already does this — the SQLite db file lives
  *outside* the store root (`dir/assets.db` vs `dir/store/`), so the db is never
  seen by `list_keys`. Keep it that way: don't point a backend root at a
  general-purpose directory.
- **Inspect before sweeping.** Run `check_consistency` (or no-arg `vacuum`) and
  look at `orphan_objects` before ever passing `delete_orphan_objects: true`.
- `delete_missing_rows` has no such hazard — it only touches index rows whose
  object is already gone.

## If we want to harden this later

Constrain enumeration to keys that match DataDungeon's own path scheme
(`asset_type/<2-char prefix>/…`) instead of "every file under root", so foreign
files are never eligible for deletion. Not done now; a dedicated root is the
simpler contract. A non-local backend (R2/S3) would face the same question at
the bucket/prefix level.
