# Consumers

*Updated 2026-10-12*

| App | Checkout | Uses DD for | Builds against |
|---|---|---|---|
| Overlore (formerly Infocomic) | `~/Projects/infocomics/infocomic` | images, transcripts, banter, decrees | GitHub, `~> 0.12.0` since its `863ba42` (2026-10-11); was this checkout |
| Cattacula | `~/Projects/siliconcircus.lol/cattacula/service` | TTS voice audio (`voices.db`) | this checkout (`lib/data_dungeon` symlink) |
| Pirateship | `~/Projects/siliconcircus.lol/pirateship` | parrot TTS voices (`data/voices.db`) | GitHub, `~> 0.7.0` |
| Silicon Circus venues | via the `siliconcircus` agent | venue images, about one per attraction | — |
| Silicon Circus park store | `~/Projects/siliconcircus.lol/assets` | the park's shared assets: Cattacula's voices (copied), fronts, sprites, props | GitHub, `~> 0.8.0`; `just serve` runs dd-serve on 127.0.0.1:12782 |
| Owl | `~/my/world/ofwords/owl` | scenes, props, frames and depth maps (`owl_*` types), its scene graph in `owl_*` tables in the same file | GitHub, `~> 0.11.2`; agent `@owl` (joined 2026-10-12) |

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

## Builds from this checkout (being retired)

Infocomic and Cattacula compile straight from this working tree, so any
uncommitted DD edit is live for them at once, including while the
`@infocomics` agent is working. Found 2026-10-05, before the 0.5.0 registry
rename, when a half-edited tree would have broken a collaborator's build.

**Thomas, 2026-10-09: stop linking.** Consumers install DD from GitHub
(`github: trans/datadungeon`, `version: ~> X.Y.Z`), as Pirateship and the
park store do, so DD's main branch moving never changes their build and
each upgrades when ready. It came up because 0.11 couldn't merge while
Overlore built from here (handoff.md). Until Overlore and Cattacula have
switched, the precautions below still apply.

- Develop breaking or multi-step changes in a git worktree (in the
  scratchpad, with `lib` symlinked to this checkout's).
- Keep deprecated aliases for renamed APIs for a release (`canonical_key`
  for `pool_key`, for example).
- Type-check consumers against the worktree before merging:
  `CRYSTAL_PATH="<dir holding a data_dungeon symlink>:lib:/usr/lib/crystal" crystal build --no-codegen`.

Pirateship installs from GitHub, so it only sees tagged releases (see
release.md).

## Overlore's plan (from `@overlore`, 2026-10-09)

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
  through `db.read` (`a2a0f12`, `35d6e92`, pushed).
- **Pirateship** registers `voice` (traits `pool i voice fmt`), reads
  through `db.read`, and stores `description`/`generated` (`412f9be`,
  pushed 2026-10-07). Its live `data/voices.db` upgrades from the 0.3 schema
  the next time it starts. Its uncommitted training-camp work (from
  2026-08-26) isn't ours; leave it.
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
same SQLite file. None of its types is registered, so **0.12 refuses its
stores until it registers them**; pinned `~> 0.11.2`, it's safe until it
bumps. Depth maps: Depth Anything V2 in ONNX Runtime, about 30 ms a picture
on the GPU, under a second on the CPU, an 8-bit grayscale PNG kept as an
asset; the picture-to-depth mapping is its own table (`owl_depth`), not a
DD link.
