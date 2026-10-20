# Consumers

*Updated 2026-10-16*

| App | Checkout | Uses DD for | Builds against |
|---|---|---|---|
| Overlore (formerly Infocomic) | `~/Projects/overlore` (moved from `~/Projects/infocomics/infocomic` 2026-10-14) | images, transcripts, banter, decrees | GitHub, `~> 0.15.0`, live store on 0.15.6 (its lock) and the standard types since 2026-10-20 (`f9c472ee`); earlier: `~> 0.13.1`, live store on 0.13.1 since 2026-10-15 00:33 UTC (916 records as recipes, ten style wordings named); `~> 0.12.0` since its `863ba42` (2026-10-11); was this checkout |
| Cattacula | `~/Projects/siliconcircus.lol/cattacula/service` | TTS voice audio (`voices.db`) | GitHub, `~> 0.15.4`, 0.15.4 since its `46bab79` (2026-10-20); 0.13.1 since its `4d39011` (2026-10-14); 0.13.0 since `55587c5`; `~> 0.12.0` since `9fe2421` (2026-10-12); agent `@cattacula` |
| Pirateship | `~/Projects/siliconcircus.lol/pirateship` | parrot TTS voices (`data/voices.db`) | GitHub, 0.15.4 since its `d055ec6` (2026-10-20); 0.13.1 since its `84491af` (2026-10-14); `~> 0.13.0` since `a4dcabe`; agent `@pirateship`, with its own `.ai/` (handle `pirateship`) since 2026-10-19 |
| Silicon Circus venues | via the `siliconcircus` agent | venue images, about one per attraction | — |
| Silicon Circus park store | `~/Projects/siliconcircus.lol/assets` | the park's shared assets: Cattacula's voices (copied), fronts, sprites, props | GitHub, 0.15.4 in the repo (`3a074cf`), the live dd-serve when Thomas says (2026-10-20); 0.13.1 since 2026-10-14 (assets `2f1d1ca`; `@curio` checked 564 assets and 27 queries against 0.13.0); `just serve` runs dd-serve on 127.0.0.1:12782 |
| Owl | `~/Projects/owl` (moved from `~/my/world/ofwords/owl` on 2026-10-19) | scenes, props, frames and depth maps (`owl_*` types), its scene graph in `owl_*` tables in the same file | GitHub, `~> 0.15.0`, 0.15.4 since its `8f50950` (2026-10-20, live); 0.13.0 (2026-10-14; was `~> 0.12.0` since its `03ffc98`); agent `@owl` (joined 2026-10-12) |

## Where the files are

All on local disk as of 2026-10-07; no app uses `S3Storage` yet.

- **Infocomic:** `~/.local/share/infocomic/assets.db` (`INFOCOMIC_ASSET_DB`
  overrides). Its older rows index its own files under
  `~/.local/share/infocomic/` (`images/`, `audio/`, `banter/`) by absolute
  path (`store_asset`); new ones go through `DB#store` into
  `INFOCOMIC_OBJECTS_DIR` (default `<data dir>/objects`), or a bucket when
  `INFOCOMIC_S3_BUCKET` is set. `DB#adopt` moves the older rows in.
- **Cattacula:** `service/data/voices.db`, objects in `service/data/voices/`.
- **Pirateship:** `data/voices.db`, objects in `data/voice-blobs/`.

## Builds from this checkout (retired 2026-10-12)

**No consumer builds from this checkout any more** since Cattacula's
`9fe2421` (2026-10-12); every app installs from GitHub. The rest of this
section is the history.

Infocomic and Cattacula compile straight from this working tree, so any
uncommitted DD edit is live for them at once, including while the
`@infocomics` agent is working. Found 2026-10-05, before the 0.5.0 registry
rename, when a half-edited tree would have broken a collaborator's build.

**Thomas, 2026-10-09: stop linking.** Consumers install DD from GitHub
(`github: trans/datadungeon`, `version: ~> X.Y.Z`), as Pirateship and the
park store do, so DD's main branch moving never changes their build and
each upgrades when ready. It came up because 0.11 couldn't merge while
Overlore built from here (handoff.md). The precautions below applied until both had
switched.

- Develop breaking or multi-step changes in a git worktree (in the
  scratchpad, with `lib` symlinked to this checkout's).
- Keep deprecated aliases for renamed APIs for a release (`canonical_key`
  for `pool_key`, for example).
- Type-check consumers against the worktree before merging:
  `CRYSTAL_PATH="<dir holding a data_dungeon symlink>:lib:/usr/lib/crystal" crystal build --no-codegen`.

Pirateship installs from GitHub, so it only sees tagged releases (see
release.md).

## Overlore's plan (from `@overlore`, 2026-10-09)

**2026-10-14, recipes:** its live store stays on 0.12 (the server never
restarted on its 0.13.0 build) and converts once, straight to 0.13.1,
asset by asset in id order, passing no version numbers. Each art style's
wording is named `overlore:<standard style>/<purpose>` (golden →
`golden-comic`, silver → `silver-comic`, modern → `modern-comic`,
`fantasy`, realism → `photorealism`, 3d → `3d-cartoon`, manga →
`dark-manga`, `pixel`), with purposes `place` (rooms, backdrops, hero
shots, centerfolds, door views) and `figure` (portraits, panels); each
style has exactly those two wordings. Style fields that aren't a style's
wording ("in the same style as the reference image", a room's neighbours)
stay plain texts.

**2026-10-15:** live store converted (above). Its pixel wording was renamed
in place to `overlore:pixel-16/place` @1 (it edited the one `named_texts`
row; Overlore `c8332d9`), and new pixel pictures are filed `pixel-16`
(`/place`, `/figure`). Its `art_style` tag still says `pixel` until 0.15's
standard tags. It plans to compose in the new order when 0.14 lands; it
doesn't yet know about `flavor` (the held 0.14 draft tells it).

**Heads on other bodies (Thomas, 2026-10-16):** `@mj` is testing swapping
generated heads onto other bodies, to reuse heads and bodies freely. If it
works, Overlore uses it first for its "coming soon" landing page, then in
the game: the player picks a DM, and that DM's head travels with the party
on the quest. DD already has what matching needs (art style, view and light
vectors, best match), a composite's recipe as steps referencing both by
hash, and links. **Gap to raise when mj's results are in:** an image has
one anchor; a body needs at least a ground point and a neck point, a head
its neck, so named points (`neck`, `ground`) would cover it. Not 0.14.

- Waits for 0.11.1, then passes `supersedes:` in `level_voices`,
  `voices_to_mp3` and `TTSBase#clip`, adds `retired_at IS NULL` to their
  SELECTs, prunes comics with `keep_last: 1`, and moves to `~> 0.11.1`. The
  leveling runs at Thomas's next restart, under 0.10.
- Toward 0.12: pictures, voices and text are in the store; left are its
  repo's own art (a manifest drafted) and retiring the old folders.
  `portrait` waits on its traits being settled; the 29 `background` rows
  (rooms from before the judge) get registered or become rooms; the 4
  `legacy` assets get a registration. It will say when all three are
  registered and `pool_key:` is gone.

## 0.11 (keys as an index), for each consumer

- Every store adds, so code that re-stores to replace an asset must name it
  (`supersedes: old.id`), and raw SQL picking work must skip retired rows
  (`retired_at IS NULL`). Overlore's `level_voices` and `voices_to_mp3` do
  both kinds of thing (see handoff.md); Cattacula only stores what's
  missing, so nothing changes for it.
- Storing bytes the type already holds raises `AlreadyStored`, unless it's
  an exact repeat. Neither live store had such a pair (2026-10-09).
- The first read-write open re-keys (scheme 4), counts the tags and fills
  `made_at`; a read-only open (dd-serve) of an older store fails until then.

## 0.11.1 (image fields), for each consumer

Only additions, except that an image's `animated`, `frame_count` and
`duration_ms` moved to `ImageMeta#animation` (JSON `meta.animation`); no
consumer set them (checked 2026-10-09). Every picture stored is measured,
so `width`/`height` are what the bytes say, not what was asked. Overlore's
128 picture rows and the park store's props need `measure_images` once.

## Where each stands

- **Cattacula** registers `voice` (traits `bit beat voice fmt`) and reads
  through `db.read` (`a2a0f12`, `35d6e92`, pushed). On 0.12 from GitHub
  since `9fe2421` (2026-10-12), no code changes; its `voices.db` was backed
  up and upgraded, all 488 voices found by traits. Moving its voices into
  the park store waits until the park store is on 0.12 (`@cattacula`,
  2026-10-13). On 0.12.1 since its `26738f1` (2026-10-13): `voice_generate`'s
  cache check passes `touch: false` (at boot it ran once per beat, counting
  about 488 plays each start); `voice_audio`'s `get` is a real play and
  counts. **On 0.13.0 since its `55587c5` (2026-10-14), no code changes:**
  the first open moved its 488 voices over; none had a description or a
  `generation`, so `texts` and `recipe_legacy` stay empty. Ids, file
  hashes, use counts and tags all match a snapshot from before
  (`@cattacula`'s report). **On 0.13.1 since its `4d39011` (2026-10-14):**
  the first open rebuilt only the empty `named_texts`; all 488 voices found
  by traits and read back, every row as before, integrity ok.
- **Pirateship** registers `speech` since piece 1 (`4fb2fde`, 2026-10-19; was `voice`, traits `pool i voice fmt`), reads
  through `db.read`, and stores `description`/`generated` (`412f9be`,
  pushed 2026-10-07). On `~> 0.12.0` since its `46e4713` (pushed
  2026-10-13, at Thomas's request). Its only change: `touch: false` where
  it checks or lists, and a fire-and-forget `touch_asset` for real plays
  (performance.md); since 0.12.2 (its `e87f1cf`) a plain `touch_asset`
  after the clip is read, with no fiber. Measured on a copy (xfs): a play
  0.4-0.95 ms; 120 plays while another process held the write lock for
  6 s all answered, the slowest 2.4 ms (before 0.12.1 the same test
  stalled 5 s); counts written at SIGTERM through DD's `at_exit`. Its live `data/voices.db` went from the 0.3 schema
  straight to 0.12 at Thomas's `just dev` the same day, after a backup:
  all 14 voices found by traits, every clip byte for byte, nothing
  regenerated. On a copy first, the same: 14 assets current, keys `voice.<pool>.<i>.onyx.mp3` in
  `asset_keys`, `canonical_key` and `pool` gone, objects untouched, every
  clip byte-identical, nothing re-voiced. **On `~> 0.13.0` since its
  `a4dcabe` (2026-10-14), no code changes:** a copy of the live store gained
  only the recipe and text tables, all 14 voices current with their keys,
  clips byte for byte; the live store upgrades at Thomas's next restart,
  backed up as `data/voices.db.pre-0.13`. **0.13.1 installed since its
  `84491af` (2026-10-14; `shard.yml` stays `~> 0.13.0`):** on a copy of the
  live store every row of assets, tags, keys, audio_meta, asset_types and
  asset_indexes identical, every clip byte for byte; the live store upgrades
  at Thomas's next restart, backed up as `data/voices.db.pre-0.13.1`. **Thomas, 2026-10-14 (through
  `@pirateship`): Pirateship keeps its own store for good** and won't merge
  into one Silicon Circus store; each venue can keep its own. It holds the
  parrot's voices today and will hold all of Pirateship's assets (this
  replaces "decided later", 2026-10-13). Its uncommitted training-camp work (from 2026-08-26) isn't ours;
  leave it.
- **Infocomic** is moving every asset except its favicon to `DB#store`
  (Thomas's call, 2026-10-07), in stages: storage and serving, pictures,
  voices, text, its repo art, then the existing rows (its TODO.md,
  "Storage: every asset through DataDungeon"). It registers each type as it
  moves. Renames: `tile` -> `panel`, `background` with `centerfold=true`
  -> `heroshot`; panel and heroshot key on art style, rating, portrait (its
  file's hash) and prompt hash. The 29 other `background` rows are pre-judge
  room pictures; Thomas decides their fate. It serves `/media/<key>`:
  local objects read and served, bucket objects redirected to `resolve`.
  `@overlore` (then `@infocomics`) asked us to **hold the registration requirement until they
  say Infocomic is done**. For them DD added `adopt`/`outside_store` and the
  opus/svg extensions (0.7.1), `open`/`find_by_hash`/`.pdf` (0.7.2), and
  dashed trait names with `rename_tag`/`rename_type` (0.7.3). It runs on
  0.9.0 unchanged (2026-10-08) and plans `derived-from` links from panels to
  portraits once panels are judged. Next it renames
  its traits and types without underscores (`art_style` -> `art-style`,
  `banter_script` -> `banter-script`) and merges `room`, `background` and
  the seed backdrops into one `backdrop` type.
- **Voices are MP3 in every app** (Thomas, 2026-10-07). Safari plays Opus
  in Ogg only from 18.4 with macOS 15.4 / iOS 18.4 (March 2025), so current
  Macs still on Sonoma or Ventura, and iPhone 8/X and older, can't. Opus in
  WebM was unreliable in iOS `<audio>` into 2024. MP3 plays everywhere, and
  R2 doesn't charge for egress. Infocomic's 105 Opus clips predate this.
- **Silicon Circus park store** (Thomas's decision, reported by `@curio`
  2026-10-08): one DD for the whole park, in its own repo. Types name an
  asset's shape, not its venue, and every key leads with `venue`:
  `stage-standup` (venue act bit beat voice fmt), `front` (venue attraction
  look), `sprite` (venue attraction look scale), `prop` (venue thing look
  style variant fmt). Only the store repo's `types.cr` registers them;
  venues mustn't, since a drifted definition would re-key everyone's assets.
  Who uses an asset is a plain, unkeyed tag (`used-by`), so use can change
  without re-keying: since 0.9.0 a `used-by` link, which the 58 boardwalk
  props now carry (2026-10-08). The store is on `~> 0.9.0`; its `types.cr`
  passes `rekey: true` only for `just types --rekey`. Cattacula still reads its own voices.db for now.
  Under 0.9 its database must be opened read-write once (adding the links
  and search tables) before a read-only `dd-serve` accepts it.
- **Silicon Circus** (before the park store) used DD per app, as a shard,
  not a shared service.
  Their case is single-best `db.store`/`db.get` with WebP normalizing.
  `check_consistency`/`vacuum` (0.3.5) is the orphan sweep they wanted.

Before editing Overlore's image code, check with `@overlore` (see
coordination.md).

## Reaching a store from elsewhere

Each app's DD database is SQLite on that app's server, which nothing can
open over the network. Since 0.8.0 an app can mount `DataDungeon::API`
(`data_dungeon/http`), or run `dd-serve` beside the database, so tools such
as `@curio`'s DD browser reach it over HTTPS with a read token, plus a write
token for edits.

## Owl (found 2026-10-12)

Owl keeps every picture in DD (`Store#put_image`: types `owl_scene`,
`owl_prop`, `owl_frame`, `owl_depth`, and `owl_voice` for clips; tags
`world` (slugs like `the-valley-c092`), `kind`, `style`; a `generation`
record) and its scene graph in its own `owl_*` tables in the
same SQLite file. Depth maps: Depth Anything V2 in ONNX Runtime, about
30 ms a picture on the GPU, under a second on the CPU, an 8-bit grayscale
PNG kept as an asset.

**On 0.12 since its `03ffc98` (2026-10-12)**, tested on a copy; its live
store upgrades on its next start, backed up. All five types registered at
start-up with `pool_traits` `world` (`kind`, `style` plain tags). Depth
maps are `depth-of` links from the map to its picture (its `owl_depth`
table moved over and dropped), stored `permanent: false`; everything else
`permanent: true` now. On `AlreadyStored` (the same bytes under another
world's tags) it reuses the held asset by id.

**Asked 2026-10-12:** its older scenes, props and frames were stored
`permanent: false`; can that be changed? Not in 0.12 (`update_asset`
doesn't take it). Nothing evicts on its own (only `eviction_candidates`
reads the flag, and owl doesn't call it), so nothing is at risk. Thomas
(2026-10-13): `update_asset(permanent:)` comes in 0.13, not a 0.12.1;
reply drafted saying so. Owl will send its view on recipes separately.

**On 0.13 with recipes (2026-10-14, its own report):** new pictures stored
with recipes, prompts built as fields and sent as `Recipe#joined`; a lift
is two steps (removal, then a matte referencing both pictures by hash), a
cut-out prop a picture step plus a cutout step, a depth map form `""`
referencing its source; narration is speech with the named text
`owl:narrator`. All 97 old records converted, none left in recipe_legacy:
13 split into fields that join back exactly, one cut at 500 characters
(its recipe says so), the rest settings only. Descriptions now say what
each picture shows; old pictures marked permanent (depth maps not);
anchors filled as ground points; `copied-from` names the file hash.
