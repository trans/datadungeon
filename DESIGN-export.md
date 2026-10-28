# Export: a store as files

*Draft 2026-10-27, with Thomas, from `@overlore`'s request for him
(67807ebe). Not built. The database stays the record, backed up by
snapshots (DESIGN-backups); the export is a second backup that can be read
and diffed, made complete enough to become the record later (Thomas,
2026-10-27). YAML or C0DATA is open.*

## Why

- **Asked for:** the store's metadata written out now and then as a
  backup. One day the files might become the record that endures, with the
  database an index rebuilt from them plus the stored bytes, which their
  hashes find.
- **A snapshot can't be read or diffed.** It restores exactly, but it
  can't show what changed in an asset, or when. Files in a stable order,
  committed to git nightly, give every asset a history.
- **A documented format outlives the schema.** The database has migrated
  every few releases; an export is read by an import, whatever the schema
  is then.

## The database stays the record, for now

Thomas (2026-10-27): records kept as files, more so as an append log, with
the database a rebuildable index, make diffs easy. He isn't sure DataDungeon
needs it, since SQLite is a file; Postgres would gain more.

- **An append log as the record** means every write goes to the log first
  and the database replays it: a rewrite of how a store writes, with
  several processes writing one store. Not now. Wordings already work that
  way: one can't be changed or deleted, only a new version added.
- **Git history of nightly exports** gives most of what a log would (what
  changed, and when) without touching how a store writes.
- **Postgres:** DataDungeon is SQLite-only (Memo supports Postgres;
  DataDungeon doesn't), and hosted Postgres has its own snapshots and
  point-in-time restore.
- **So:** the export is complete, and an import is tested against it. Once
  that holds, making the files the record is a decision, not a rewrite.

## What goes in

Everything a store records and can't make again:

- **Types:** each registration (traits, labels, sets, facets, scales,
  colors, weights, cycles, match fields, `embed`, key scheme) and its
  indexes (consumer, name, traits).
- **Vocabulary:** tags and their values, with titles, descriptions,
  families and wordings.
- **Wordings:** each named text (kind, `owner:name@version`, its words).
- **Assets,** one record each:
  - id, type, media, content type, and hash (its object's key follows), or
    the path of a file the store doesn't hold (`outside_store`);
  - tags, in the type's trait order, then custom tags;
  - description, in full;
  - `made_at`, `created_at`, generator, `generated`, rating, `flagged`,
    `permanent`, `retired_at`;
  - recipe: each step's form, settings, seed, cost, prompt, instructions,
    refs and wordings; the legacy generation where there is one;
  - links (`derived-from`, `supersedes`: takes are links plus
    retirement), tracks, a text's content and language;
  - media details, all of them;
  - credits, once they're built (DESIGN-types).
- **All the media details,** measured ones too. Size and duration could be
  read again from the bytes, but what's set can't: presentation,
  compression targets, view, light, anchors, world size, frame layout,
  keyframes. Exporting both keeps the import from fetching every file or
  depending on a probe's version.

Left out, and rebuilt by the import:

- keys (from tags and the indexes' traits), search terms, tag counts, the
  change log, the match files;
- **embeddings,** and the rest of Memo's tables. A vector is about 3 KB of
  binary (1536 dimensions), one per text per model, and all of them change
  with the model, so they'd
  bury the diffs. The import has Memo index the store again: cheap, but it
  needs the key, the network and time. A file of vectors beside the export
  would save that; open.

**Usage** (`use_count`, `last_used_at`) goes in a file of its own
(`@overlore`, 2026-10-28, 271dc96d): it changes with every use and would
fill every night's diff otherwise. Overlore needs it back after an import:
a room's new state is drawn from its most used picture, and pictures of
rarely seen states are pruned by their use. Counts not yet flushed when
the export runs are lost, which is fine: they're a hint.

## Shape

- **Files:** `types`, `vocabulary`, `wordings`, `usage`, and `assets/<type>`,
  one per type (Overlore: "if that splits better"; it does, and a type's changes
  stay in its file). A manifest gives the format's version and the counts.
- **By id within a type.** Overlore suggested type, key, hash. But a key
  changes when a tag does, so the record would move and the diff would show
  a removal and an addition. Ids never change, and new assets come last.
  The key is in the record to read, not to sort by; hashes repeat
  (identical bytes share an object).
- **Ids are kept:** links name assets by id, and an import into a new
  store keeps them.
- **Texts in full, inline:** descriptions, prompts, wordings. The database
  keeps a text once by its hash, and the import does that again.
- **No time in the files:** two exports of an unchanged store are
  identical, and the test below compares bytes. The commit has the time.
- **One read transaction:** a consistent view while the app writes.

## YAML or C0DATA

Thomas, 2026-10-27: "we might end up using C0DATA instead of YAML, but we
shall see." Either has to give:

- a canonical form: the same store, the same bytes;
- line breaks between records and fields, for git's diffs;
- text verbatim: descriptions and prompts run to several lines.

**YAML** reads anywhere, and Overlore's sketch (`data/assets.yml`, its repo
art, 2026-10-07) is YAML. Its implicit types need care: `no`, `on` or
`1.10` read as a boolean or a number unless quoted, so the export quotes
every string that could.

**C0DATA** uses control codes as delimiters, and values are plain text. Its
spec has a canonical form (keys sorted bytewise) and a stream shape with
commit markers, which would suit an append log should one come. There's a
Crystal library (`c0`). To check: how its diffs read in git, given line
breaks are its layout outside text.

## Running it

- `DB#export(dir)`, and an import that builds a new database from a
  directory and the storage.
- A command: DataDungeon has none but dd-serve. A small `dd export` /
  `dd import`, or dd-serve subcommands; open.
- Overlore's plan: the box runs the export nightly, beside its backups,
  into a git repository. A repository only on the box goes with the box, so
  push it somewhere private: the files hold prompts, recipes and costs, as
  the database does.

## Import

- **Into a new, empty database only,** never into or over a live store.
- Writes the rows with their ids; rebuilds keys, search terms and counts;
  then has Memo index the store (the embedding API) and builds the match
  files.
- Checks every asset's object is in storage and reports what's missing.
  It deletes nothing.
- **The test:** export, import, export again, and the two exports are
  identical; the imported store answers as the original did (counts, keys,
  a search).
- **Later, copying between stores:** the same reading serves an app that
  copies another store's records into its own (DESIGN-types), with new
  ids, links remapped and wordings matched by name and version. That needs
  its own design.

## Open

- YAML or C0DATA.
- Embeddings: made again on import, or a file of vectors beside.
- The command: `dd`, or dd-serve's.
- Whether the export also goes to R2: its files as objects, found by a
  name in the `names` bucket, as the snapshots are (DESIGN-backups).
- Making the files the record: after the import round-trips, Thomas's call.
