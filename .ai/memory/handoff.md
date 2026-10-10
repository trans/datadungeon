# DataDungeon handoff

## 0.11 part 1: keys as an index (2026-10-09, not merged)

Built on branch `keys-and-retiring`, in a scratchpad worktree, from
`DESIGN-image-fields.md` ("Keys as an index", "Retiring", "Indexes per
consumer"); 118 specs pass, S3 specs pass against Garage, Overlore and
Cattacula type-check against it, and copies of both live stores upgrade
cleanly. What it does:

- Every store adds; `get` prefers the newest current take by `made_at`.
  `store(…, supersedes: id)` / `supersede`, `retire`, `reinstate` (down a
  chain of takes too), `prune(type, keep_last:, retired_before:)`.
  `AlreadyStored` for bytes the type holds, except an exact repeat. `pool:`
  is deprecated and ignored. `TraitKey::SCHEME` 4 re-keys once on open, so
  every asset of a registered type has a key (single-best collisions had
  left some without).
- Per-consumer indexes: `DB.new(…, consumer:)`, `register_index`,
  `unregister_index`, `indexes`; tables `asset_indexes`, `asset_keys`.
- `asset_tag_counts`, kept by SQLite triggers: browse counts and the tag
  planner's sizes. The planner starts from the smallest of the type's key
  range, each consumer index's range and each tag, or for a page walks
  the newest assets when that costs less (performance.md).
- Links carry JSON `data`; name filters take `x.*` and `x*`. HTTP: retire,
  reinstate, prune, `retired=only|include`, retired counts and indexes in
  `/types`.
- Retired assets leave listings, counts, MatchIndex and SemanticIndex.

**Blocks merging:** Overlore's startup migrations (`level_voices`,
`voices_to_mp3` in `store_migration.cr`, `6f83d76`) re-store clips and rely
on the store replacing in place; 757 clips were pending in its live store on
2026-10-09. Under 0.11 they'd need `supersedes: id` and `retired_at IS
NULL` in their queries, or to run under 0.10 first. Tell `@overlore`
(with Thomas's go-ahead) before merging, since it builds from this checkout.

**Next:** part 2, image fields (the rest of `DESIGN-image-fields.md`).

## Current state (2026-10-07)

Everything below "Where we stopped (2026-10-04)" predates this week and is
partly superseded; README.md describes the current API. DataDungeon main is
pushed at `7618531`, tagged `v0.10.0` (2026-10-09; `v0.9.0` is `2b79d46`, `v0.8.0` `d01f4ec`, `v0.7.0` `dc38d81`, 0.7.1-0.7.3 untagged); `crystal spec` gives 97 examples, 0 failures,
1 pending (S3, which needs `scripts/garage-test`). What landed since 0.4.0:

- **Storage:** objects are content-addressed, `<h2>/<sha256>.<ext>`, shared by
  identical bytes and unlinked only when unreferenced (0.4.1).
- **Type registry** (0.5.0-0.5.5): `register_type` with traits in priority
  order; DD derives `pool_key` = type + dotted normalized values
  (`portrait.golden.pg.f.human.tan-skin.red-hair`); `group_traits` are the
  leading traits; prefix lookups; labels; set-valued traits (`sets:`); custom
  flags with `custom_values`/`promote`; `find_pool`/`find_group`/`find`; the
  key alone finds a pool. `canonical_key` is a deprecated alias of `pool_key`.
- **Tags** carry their asset type; tag filters start from the narrowest range
  (0.5.1). Foreign keys and `busy_timeout=5000` are set on every connection.
- **Semantic search:** filters by `pool_key`/`key_prefix`; no default score
  cutoff; index saves left to Memo's policy; **facets** (0.5.7): per-type tag
  groups embedded separately, `search(facet:)` and `search_facets` (weakest
  facet scores).
- **Concurrency** (0.5.6): write transactions use BEGIN IMMEDIATE, so several
  processes on one database wait instead of failing; `bench/concurrency.cr`.

Consumers: Cattacula and Pirateship register `voice` (pushed). Infocomic
registers transcript, banter, decree (by `game`), room and backdrop;
narration, portrait, background and tile are still unregistered. See
consumers.md.

- **S3 storage** (0.6.0, 2026-10-07): `DataDungeon::S3Storage` in the
  optional `data_dungeon/s3` (R2 via `S3Storage.r2`), on `awscr-s3` from
  Thomas's fork `trans/awscr-s3` branch `exception-status` until upstream
  PR #168 is released. `DB#read` reads from any storage; `scripts/garage-test`
  runs the S3 specs against a throwaway Garage. Item 6 below is done.

- **Infocomic-only code removed** (0.7.0, `dc38d81`, pushed): Prompts,
  PortraitIndex, Cache and the art-style/body data moved to Infocomic
  (`be028b3`). DD keeps WebP.
- **Cattacula reads through `db.read`** (`35d6e92`, pushed). Done.

Next:

- **Pirateship is on DD 0.7** (`412f9be`, pushed 2026-10-07):
  pins `~> 0.7.0` from GitHub (`v0.7.0` tagged and pushed; no
  tags exist for 0.4-0.6), registers `voice`, reads via `db.read`, and
  stores `description`/`generated`. Ran against a copy of `data/`: all 14
  voices re-keyed and served byte-identical. Its live `data/voices.db` is
  still 0.3 schema until Pirateship next starts. The migration note was
  removed. Pirateship's unrelated uncommitted training-camp work
  (`training.js`, `public/training-camp/`, six webp assets, from
  2026-08-26) was left as it was.
- Then require registration for storing. Cattacula and Pirateship
  register. Infocomic is moving everything to `DB#store` and registering
  each type as it moves (see consumers.md); `@overlore` (formerly `@infocomics`) asked us to hold
  the requirement until they say they're done.
- 0.7.1 (`644f1e5`: `adopt`, `outside_store`, opus/svg extensions) and
  0.7.2 (`8a20a96`: `DB#open`/`Storage#open` streaming, `find_by_hash`,
  `.pdf`, and the S3 read fix) and 0.7.3 (`44fbf6e`: dashes in trait
  names, `rename_tag`, `rename_type`) were never tagged; 0.8.0 (`d01f4ec`:
  browsing calls, `update_asset`, read-only open, the `data_dungeon/http`
  JSON API and `dd-serve`) is tagged `v0.8.0`.
- **DD web UI:** Thomas wants one to filter by tags, see what's there and
  curate, read-only by default with a big red "update mode" switch. DD stays
  UI-free; `@curio` (Rust) is rebuilding curio as that UI over DD's JSON API
  (0.8.0), with Thomas's go-ahead. We answered its questions 2026-10-07:
  stores and their paths, copies need one read-write open first (Cattacula's
  and Pirateship's live DBs are pre-0.4), curio makes thumbnails keyed on
  `file_hash`, no CORS (curio proxies and holds the tokens). Open: listing
  without a type, other sort orders, and whether update mode re-locks itself.
- **`@curio`'s requests, 2026-10-08: Done in 0.9.0 (`2b79d46`).** Search
  across types (whole words; `catt*` for a start, since Thomas said exact
  matching is the common case), listing with no type, the `register_type`
  guard (`rekey: true`), and links instead of multi-valued tags (Thomas
  agreed; relations named as transfs does: `derived-from`, `supersedes`,
  `used-by`). Numbered pages (`page=`) as well as the cursor, at Thomas's
  request. `@curio` uses all of it (2026-10-08). **Open:** HTTP Range on
  objects (later); an estimated total (performance.md).
- **Best match: Done in 0.10.0 (`7618531`).** `MatchIndex`
  (`data_dungeon/matches`), designed with Thomas: see
  `DESIGN-best-match.md`. `dd-serve` always has it (Thomas asked why it
  was a setting; the usearch shard builds its own C library, so no flag).
  **Open:** building is single-threaded (~11 min per 1M).
- **`prefer:` (Open, next release):** `@mj`'s images carry `version` and
  `quality`; prefer higher ones among candidates, never discard. Thomas
  isn't sure yet how it should work (2026-10-09); see coordination.md.
- **0.11: image fields, views and placement (Open, design drafted
  2026-10-09, `DESIGN-image-fields.md`, uncommitted until settled).**
  Key = what it is; image fields = real columns; links = who and where;
  link data = placement. Views and light stored as unit vectors (Thomas
  agreed), shown as side/yaw/pitch/roll in quarter turns. Includes
  `@curio`'s link-name prefixes (`boardwalk.*`) and `cycles:`. Thomas
  settled its first questions the same day (content box measured; named
  directions, but no field in any key; animation as time-0 `image_meta`
  plus keyframes). Reviewed by `@curio`, `@overlore` and `@mj` the same
  day; Thomas then decided: 3D real size, light in the picture's frame,
  keys as an index (the app defines pools; supersede, copy uses,
  `reinstate`, app-called pruning), storing a held file errors except an
  exact repeat, provenance in `generation`, soft newest-first preference,
  `dominant_color`. Replies sent to all three. **Next:** build 0.11 from the
  doc once Thomas has read it through.
- Memo stays in DD's SQLite file for now; working first, then optimize.

## Where we stopped (2026-10-04)

DataDungeon's metadata/API changes and optional Memo semantic index are
implemented and committed locally. Infocomic's matching API migration is also
committed. **The application does not yet use the semantic index, and the new
portrait/camera generation and reuse flows are not implemented.** Cattacula has
one remaining uncommitted consumer migration.

The earlier coordination block with Infocomic is resolved: its agent committed
their overlapping image changes and explicitly cleared our migration to land.

## Repositories and saved work

| Project | Local checkout | Relevant commit / state |
| --- | --- | --- |
| DataDungeon | `/home/trans/Projects/datadungeon` | `a89e709` — canonical asset keys and optional Memo semantic search; version 0.4.0 |
| Memo | `/home/trans/Projects/memo` | `9931865` — optional read-only searches, synchronized query cache, bound SQL filter arguments, USearch capacity growth |
| Infocomic | `/home/trans/Projects/infocomics/infocomic` | `bfba3a7` — DD 0.4 API migration, on top of the other agent's `5a18ed7` image changes |
| Cattacula | `/home/trans/Projects/siliconcircus.lol/cattacula` | DD adaptation remains uncommitted in `service/src/cattacula.cr` |
| MJ / mjanime | `/home/trans/Projects/mjanime` (was `minanime` until 2026-10-08) | Consult its agent for image workflow design; no separate MJ service is planned for this integration |

The three named DD/Memo/Infocomic commits **have not been pushed during this
session**. Each checkout reports one commit ahead of its locally recorded
`origin/main`; these refs were not refreshed from the network for this handoff.
DD and Memo were clean before this document was added. Infocomic has no remaining
tracked edits, but does have unrelated untracked files listed below.

Local dependency links hide a release dependency: DD's `lib/memo` points to the
Memo checkout through an ignored `shard.override.yml`. Infocomic and Cattacula
both link to this DD checkout. A fresh install from remote repositories will not
receive these local commits. When publishing, make Memo's required changes
available before DD's semantic integration, then publish the consumer changes.

## Decisions to preserve

- DD is a serving-oriented, type-aware asset store. Images, audio, text, and
  video all matter. Preserve media processing such as PNG-to-WebP conversion.
- Use SQLite plus Memo/USearch. PostgreSQL and mandatory partitioning by art
  style were considered and set aside. Art style is common but optional.
- Keep one `description` field. For generated assets it carries the prompt;
  `generated` is a boolean. Provider/model and parameters belong in `generator`
  and `generation`. Do not reintroduce a separate top-level `prompt` field.
- **Superseded in 0.5.0 (2026-10-05):** applications no longer supply opaque
  keys. Each type registers its traits, most important first
  (`register_type`); DD derives `pool_key` from the tags as the dotted values
  in that order (`golden.pg.f.human.tan-skin.red-hair`), so leading-trait
  lookups are key-prefix range scans. Labels suffix ambiguous values; custom
  values are keyed like any other and flagged on the tag. `canonical_key` is
  a deprecated alias of `pool_key`. See README "Asset identity".
- Application identity and storage are different things. Since 0.4.1 (decided
  2026-10-04, preparing for transfs) `DB#store` keys objects by content:
  `<first two hex chars>/<sha256>.<ext>` (extension from the content type),
  shared by identical bytes and unlinked only when no row references them.
- Compatibility with the older DD API is not required; update both consumers.
- **No separate MJ generation service.** Infocomic implements its image flows,
  with MJ helping design them. If they become useful to other applications they
  can move out later. The old question of DD calling an MJ service is superseded.
- DD orchestration (`find_or_make`, supplied with an application generation
  callback) remains optional. Infocomic can search, generate, and file in DD.
  No such orchestration API has been implemented yet.
- The future `transfs` storage adapter remains deferred. Keep local filesystem
  storage as another adapter when that work starts.

## Portrait selection and shared reuse

This was the most important clarification in the conversation:

1. Search existing stock portraits using the requested traits/description and
   present close choices. The player has not yet chosen a specific appearance.
2. If none suits them, they may spend coins to request a new portrait.
3. That new portrait can be enhanced with a stronger model, then stored as the
   master reference. Its enhancement is a proposed workflow to validate, not an
   implemented or measured quality guarantee.
4. **A requested/custom portrait becomes stock too.** It is offered to future
   players. Custom creation does not imply a private, player-specific catalog.
5. After selection, the exact chosen portrait asset ID defines the character
   reference. A faster, cheaper model can use that master for later pictures.
6. Every player choosing that portrait can reuse its associated pictures, when
   the scene/action and other constraints fit. New pictures expand this shared
   catalog. The portrait ID alone is not enough to match a different moment.

Before selection, similarity finds candidate portraits. After selection, exact
portrait identity constrains picture search; similarity evaluates scene content
within that constraint. Shared rooms/backdrops can be reused across portraits.

The "catalog associated with a portrait" above does not automatically mean DD's
`pool: true` database flag. Decide record/key semantics deliberately. A chosen
master must stay stable: another variant with the same traits must not overwrite
it through a canonical-key upsert. A revised/enhanced master should have a new
asset identity so old pictures remain associated with the right reference.

## Work left, in suggested order

### 1. Finish the remaining consumer migration and release coordination

- Review, verify, and commit the DD adaptation in Cattacula's
  `service/src/cattacula.cr`. It adds the application-owned voice key and new
  `description`/`generated` arguments. Cattacula's other artwork edits are
  unrelated; preserve them.
- Recheck each repository's state on return, then arrange publication of the
  local Memo/DD/Infocomic commits. Infocomic's agent requested a push; only a
  local commit has been made so far.
- Tell/check with `@infocomics` before editing its image code again. They already
  received the `bfba3a7` commit and test-status update via Arcana.

### 2. Make image identity safe before sharing pictures

Infocomic's `src/infocomic/web_app/turn.cr` currently builds DD image keys from
prompt hash, art style, and rating. **It still omits the portrait reference and
camera/workflow version.** Fix this together with the generation cache: a wrong
cache hit can occur before an image ever reaches DD.

Relevant files:

- `src/infocomic/asset_key.cr`
- `src/infocomic/img_gen/base.cr` — `parameter_hash_for`, `cache_location_for`
- `src/infocomic/img_gen/runware.cr` — provider-specific parameter hash
- `src/infocomic/web_app/turn.cr` — DD keys/tags and picture filing
- `src/infocomic/routes/portraits.cr` — portrait lookup and creation

The generator accepts an identity argument, but current hashing only uses some
settings affected by that argument; it does not distinguish the actual reference
image contents. Use a stable portrait asset/version and/or content digest rather
than a mutable file path. Include camera/workflow ID and version, prompt, and
all rendering inputs that should prevent reuse. DD should continue to receive
the resulting opaque application key.

Verify that two different reference portraits cannot share a cached picture,
that changing a workflow/camera invalidates the relevant cache entry, and that
retrying an identical request can reuse its previous result.

### 3. Connect semantic search to the application

DD's semantic implementation exists, but Infocomic currently creates a plain
`DataDungeon::DB` without a `SemanticIndex`. Portrait preview still uses exact
lookup followed by tag scoring and a filesystem fallback.

- Add/configure the Memo dependency and embedding provider in Infocomic.
- Attach `DataDungeon::SemanticIndex`, choose descriptive tags to embed, backfill
  existing assets, and run `process_queue` in a single background worker.
- Backfill meaningful descriptions where old assets lack them. DD does not
  automatically invent descriptions for old media.
- Connect stock portrait search to the onboarding choices, preserving selected
  portrait identity for later pictures.
- Keep hard constraints such as chosen portrait, style, media/type, and rating
  as filters. Include art style only when supplied; it is not universally required.
- Evaluate reuse thresholds with real images and queries. A high embedding score
  is not proof that a picture depicts the requested action correctly. Returning
  choices at onboarding and automatically reusing a scene need different care.
- Keep storage reusable across media types; don't make the semantic API image-only.

### 4. Implement the Infocomic image flows and their metadata

Latest design **reported by `@infocomics`**: a player can swap cameras during
play, choose an auto-shutter rate that gives the DM picture tokens, and take a
picture manually. This supersedes the older "panel every turn" assumption.
Camera selection belongs to each picture and must participate in identity.
The toolbar/workflows are not implemented in the code inspected for this handoff.

- Implement shared stock selection, paid creation, optional stronger-model
  portrait enhancement, and reference-based picture generation in Infocomic.
- Test identity preservation across poses, lighting, and art styles before
  choosing the fast/strong model combination.
- Current hero-shot code deliberately omits a portrait reference pending the
  camera workflows. Do not assume reference-based hero shots already work.
- Store and return actual generation information: effective prompt, model and
  settings, workflow/camera version, reference, seed, dimensions, cost, and time.
  Current `generation_params` can reflect defaults rather than effective request
  overrides; inspect it when implementing this.
- Report whether an asset was found or made, its ID, and a similarity score when
  semantic search supplied the match. Generation cost for a reuse is zero for
  that request; preserve original generation provenance separately.
- Handle generation success followed by filing failure without blindly paying
  for regeneration. Retain the result for retry and make filing idempotent.
- If adding DD `find_or_make`, supply the application workflow and its version
  before lookup. Keep model/workflow behavior in Infocomic for now.

The old `notes/mj-brief-images.md` in Infocomic is useful context but is partly
superseded (MJ service, panel cadence, and some model/identity recommendations).
`notes/comics.md` contains exploratory pose ideas, not a committed requirement
for a pose library or character-cutout compositing.

### 5. Verify capacity with the actual application

The earlier target was about 1,000 simultaneous players, with an estimate of two
query embedding calls per turn. Revisit that estimate after the camera/search
flow is settled. Provider throughput/latency and embedding cost still matter.

`bench/semantic_filter.cr` measures local search/filter cost using mock embeddings;
`bench/sqlite_identity.py` compares lookup approaches. These are not evidence of
an end-to-end 1,000-player load test. Test real retrieval quality and the resulting
traffic pattern, including popular styles and rare portrait filters.

### 6. R2 storage adapter (added 2026-10-06; wanted before transfs)

DD can only store locally today (`LocalStorage`). Add an R2 `Storage` adapter,
and test it against an R2-compatible server running locally (Thomas is
checking options with @memo). Keep `LocalStorage`. Not started.

Points to settle when it starts:

- R2 speaks the S3 API (endpoint `https://<account>.r2.cloudflarestorage.com`,
  region `auto`, SigV4). `write`/`read`/`exists?`/`delete`/`list_keys` map to
  PUT/GET/HEAD/DELETE/ListObjectsV2; `resolve` would return a public or signed
  URL instead of a file path. A PUT is already atomic, so the temp-file rename
  `LocalStorage` does isn't needed.
- `get`, `get_by_id` and `get_with_meta` call `exists?` on every lookup to
  self-heal stale rows. On R2 that's a network round trip per read; decide
  whether to skip it for remote storage and leave drift to `check_consistency`.
- Consumers read objects through `path_for` + `File.open` (Cattacula
  `cattacula.cr:214`, Pirateship `quips.cr:100`), which only works locally.
  They'd need a DD read call, or to serve the URL. Infocomic writes its own
  local files via `store_asset`, so it would have to move to `DB#store`.
- `list_keys` treats the whole bucket or prefix as DD's (see
  `NOTES-list-keys-scope.md`); give DD a dedicated bucket or prefix.

### 7. Later: Memo under load (optimization, after things work)

@memo's checklist (2026-10-07) for extending `bench/concurrency.cr` with a
semantic mode, deferred by Thomas until things work end to end: concurrent
searches while storing and embedding (no errors, no failed queue jobs);
everything stored becomes searchable; searches during background saves (small
`index_save_changes`); identical texts stored at once share one embedding;
store/delete races leave a consistent index; crash recovery without
re-embedding; never two SemanticIndexes on one database in a process. For
realistic timing, a fake embedding API with 150-300 ms delays and occasional
429s (Memo's spec/http_pool_spec.cr has one); report p95 search latency during
inserts and saves.

### 8. Later: transfs

Implement another `Storage` adapter when the user returns to that project phase.
Preserve `LocalStorage`. Review filesystem assumptions in consumers and the
existing consistency-sweep notes before moving media. No transfs adapter exists.

## What DD and Memo already do

See [README.md](../../README.md) for current API examples.

- Nullable `canonical_key`, independent tags, description, and generated flag.
- Application-supplied exact keys; non-pool stores update the same type/key,
  while keyless records remain independent.
- `DB#store` owns media processing and file writes; `store_asset` indexes media
  already written by the caller. Infocomic currently uses the latter.
- Optional [SemanticIndex](../../src/data_dungeon/semantic.cr) uses Memo tables in the
  same SQLite DB and a USearch file alongside it.
- Embeddings use description plus only explicitly selected descriptive tag keys.
  Numeric generation parameters, IDs, hashes, and bookkeeping are not embedded.
- Store/update queues work; deletion removes the Memo entry; backfill is repeatable.
  Queued changes become searchable when the worker runs. Backfill can repair
  vectors missing after an interrupted process.
- DD configures Memo with `track_matches: false` and
  `persistent_query_cache: false`; semantic search leaves usage/match counters
  unchanged and caches query embeddings in memory. General Memo defaults still
  retain their previous behavior unless configured otherwise.

## Verification at the pause point

| Check | Last observed result |
| --- | --- |
| DD `crystal spec` | 24 examples, all pass |
| Memo `crystal spec` | 117 examples, all pass |
| Infocomic application build against DD 0.4 | Passes |
| Infocomic selected current specs | 114 examples, 2 failures listed below |
| Infocomic full `crystal spec` | Stops at `spec/image_gen_spec.cr`, which requires deleted `src/infocomic/image_gen` |
| Cattacula latest migration | Not revalidated in the final verification pass |

The two Infocomic failures match those reported by its agent before our migration
landed: `GameMemory` failed movement expects 0 edges but gets 1, and
`SQLiteSessionDB` market prices expects 9 items but gets 10. The 114-example run
excluded `image_gen_spec.cr` and `infocomic_tts_spec.cr`; the TTS spec was not
revalidated. Do not describe the complete Infocomic suite as passing.

Reproduce from the corresponding repository:

```sh
# DataDungeon
CRYSTAL_CACHE_DIR=/tmp/dd-crystal-cache crystal spec

# Memo
CRYSTAL_CACHE_DIR=/tmp/memo-crystal-cache crystal spec

# Infocomic application
CRYSTAL_CACHE_DIR=/tmp/infocomic-crystal-cache crystal build src/main.cr -o /tmp/infocomic-dd-check

# Infocomic subset used at the pause point
CRYSTAL_CACHE_DIR=/tmp/infocomic-spec-cache crystal spec \
  spec/cost_ledger_spec.cr spec/dice_spec.cr spec/dm_prompt_spec.cr \
  spec/game_memory_spec.cr spec/games_spec.cr spec/image_prompts_spec.cr \
  spec/infocomic_spec.cr spec/session_store_spec.cr spec/sqlite_session_db_spec.cr \
  spec/stats_spec.cr spec/vocabulary_spec.cr spec/world_key_spec.cr
```

## Coordination and local files to preserve

Use Arcana identity **`@datadungeon`**. In this project, **"check mail" means
Arcana, not Gmail**. Check the directory on resuming and register if needed;
automatic registration did not reliably happen earlier. Then inspect/receive
the inbox. Relevant peers are `@infocomics`, `@mj`, and `@memo`.

Last incoming messages from `@infocomics` cleared file ownership and requested
landing our migration. We replied that `bfba3a7` is committed locally, builds,
has the test limitations above, and has not been pushed. Camera/reference key
work remains to coordinate with them.

Preserve these unrelated worktree items:

- Infocomic: untracked `notes/`,
  `assets/props/backdrops/common/room-mirror-tailor.webp`, and
  `stories/zork1-invclues-r52-s871125.z5`.
- Cattacula: deleted old portrait/frame files and newly named
  `assets/art/cattacula.main-pose.*.webp` assets, separate from our source migration.

On return, read this file, check Arcana and repository status for newer work,
finish the Cattacula migration, and coordinate the portrait/camera key changes
before enabling shared picture reuse.
