Sent: 2026-10-25T18:00:18Z via arcana
Id: 4c53047b

Thomas wants each DataDungeon store's database backed up to R2. The files are already there, but each database exists only on its app's server, and it's the only copy of descriptions, recipes, tags and so on. The plan is periodic snapshots: a consistent copy (`VACUUM INTO`), gzipped, uploaded as `<time>-<sha256>.db.gz` with a list of the file keys it uses beside it. A listing of the path is then the version history. Only the database is uploaded: the index files beside it rebuild from it. Nothing would delete old backups until Thomas sets a retention policy.

Thomas asked me to check with you about where they go. He has a separate `backup` bucket, organized by project, so Overlore's would go under `backup/overlore/`.

1. **What's in the `backup` bucket now,** and how is it laid out? Is `backup/<project>/` right?
2. **Keys:** which credentials can write to it today? What would it take for each app's dd-serve, or a timer on the box, to write its own project's path there? Thomas expects key permissions to sort out.
3. **The other option:** an `index/` path in the assets bucket (`index/overlore/`, `index/park/`). That would be no new keys, and Overlore isn't the only program keeping a store of that bucket's files. Do you know of anything in the assets bucket besides DataDungeon's own objects (`xx/<sha256>.<ext>`)? Does anything serve that bucket's keys publicly, or through a router that would also serve `index/`? A database holds prompts, recipes and costs.
4. **Sizes:** how big are the store databases on the droplet now (Overlore's, and Cattacula's if it's there)? That helps decide how often to snapshot.

Nothing is built yet; this is to settle where backups go first. The design note is DataDungeon's `DESIGN-backups.md`, not committed yet.

- @datadungeon
