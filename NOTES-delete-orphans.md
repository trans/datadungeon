# Note: object/row divergence

## Resolved in 0.3.4

The original subject of this note — `delete_asset` removing the row but never
the backing object, leaking one blob per delete — was fixed in `9cb1d4b`
(v0.3.4): `delete_asset` now reads `file_path`, deletes the row, and unlinks via
`Storage#delete`, while a private `delete_asset_row` serves the internal replace
path in `store_asset`. The replace path unlinks the superseded object only when
`old_path != file_path`, which avoids the silent data loss a naive unlink would
have caused (non-pool keys carry no hash, so a same-key rewrite would have
deleted the object `store.write` had just written) and also sweeps the stray
left by an extension-changing re-store.

Verified downstream in siliconcircus `boardwalk` on 0.3.4: delete removes row
and object; re-store with different bytes under the same tags stays readable;
identical-bytes re-store still hits write-skip; store left with no orphans.

## Still open: nothing reconciles divergence in the other direction

`get` / `get_with_meta` self-heal a *missing object* into a miss but leave the
row in place (`db.cr` — `return nil unless store.exists?(rec.file_path)`). A row
whose object vanished out-of-band (manual cleanup, restore from a partial
backup, a half-failed write) becomes a permanent silent miss that nothing
reports or removes.

That's benign for reads, but it means the store can drift from the index with no
way to notice or repair it. Worth a `vacuum` / `fsck` helper that walks both
directions:

- rows whose object is absent → report, optionally delete the row
- objects with no owning row → report, optionally unlink

The second half also matters for existing deployments: any store that ran 0.3.3
or earlier has already leaked a blob for every delete performed back then, and
0.3.4 does not retroactively clean those up. `boardwalk`'s store had one such
orphan, removed by hand.

Suggested coverage: a row with a deleted object is reported and repairable; an
object with no row is reported and repairable; a healthy store reports clean;
dry-run mode changes nothing.
