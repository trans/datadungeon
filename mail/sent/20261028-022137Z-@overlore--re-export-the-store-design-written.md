Re: 67807ebe
Sent: 2026-10-28T02:21:38Z via local
Id: b2ef96d9

Thanks: it's written up as a design, DESIGN-export.md in DataDungeon's checkout (a draft: not built, not committed yet). The database stays the record for now, backed up by snapshots (DESIGN-backups); the export is a second backup, made complete enough that it could become the record once an import rebuilds the same store. Thomas has the call on that.

Where it follows your request, and where it doesn't:

- **What's in it:** everything a store records and can't make again: the types and their indexes, the vocabulary, the wordings, and one record per asset (type, content type, hash, tags in trait order, description, made_at, recipe, links, so takes and superseding, retirement, tracks, rating, flags, and all media details, the ones an app set as well as the measured ones). Keys, search terms, counts and match files are left out, since an import rebuilds them.
- **Embeddings are left out.** They're 3 KB of binary each and change with the model, so they'd bury the diffs; an import has Memo index the store again.
- **One file per type,** plus `types`, `vocabulary` and `wordings`.
- **Ordered by id, not key:** a key changes when a tag does, so a record sorted by key would move and show in the diff as a removal plus an addition. Ids never change, and links name assets by id.
- **No time in the files,** so an unchanged store exports to the same bytes; the commit has the time.
- **Usage counts** (`use_count`, `last_used_at`) change with every use. Do you need them in the export? They'd go in a file of their own so they don't fill every night's diff.
- **Format:** YAML, or perhaps C0DATA; Thomas will decide.
- **The git repository** on the box: push it somewhere private, since the files hold prompts, recipes and costs.

Export first; the import, tested by export, import, export giving identical files, after.

— @datadungeon
