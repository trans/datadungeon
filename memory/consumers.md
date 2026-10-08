# Consumers

*Updated 2026-10-08*

| App | Checkout | Uses DD for | Builds against |
|---|---|---|---|
| Infocomic | `~/Projects/infocomics/infocomic` | images, transcripts, banter, decrees | this checkout (`../data_dungeon` → `infocomics/data_dungeon` → here) |
| Cattacula | `~/Projects/siliconcircus.lol/cattacula/service` | TTS voice audio (`voices.db`) | this checkout (`lib/data_dungeon` symlink) |
| Pirateship | `~/Projects/siliconcircus.lol/pirateship` | parrot TTS voices (`data/voices.db`) | GitHub, `~> 0.7.0` |
| Silicon Circus venues | via the `siliconcircus` agent | venue images, about one per attraction | — |
| Silicon Circus park store | `~/Projects/siliconcircus.lol/assets` | the park's shared assets: Cattacula's voices (copied), fronts, sprites, props | GitHub, `~> 0.8.0`; `just serve` runs dd-serve on 127.0.0.1:12782 |

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

## Builds from this checkout

Infocomic and Cattacula compile straight from this working tree, so any
uncommitted DD edit is live for them at once, including while the
`@infocomics` agent is working. Found 2026-10-05, before the 0.5.0 registry
rename, when a half-edited tree would have broken a collaborator's build.

- Develop breaking or multi-step changes in a git worktree (in the
  scratchpad, with `lib` symlinked to this checkout's).
- Keep deprecated aliases for renamed APIs for a release (`canonical_key`
  for `pool_key`, for example).
- Type-check consumers against the worktree before merging:
  `CRYSTAL_PATH="<dir holding a data_dungeon symlink>:lib:/usr/lib/crystal" crystal build --no-codegen`.

Pirateship installs from GitHub, so it only sees tagged releases (see
release.md).

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
  `@infocomics` asked us to **hold the registration requirement until they
  say Infocomic is done**. For them DD added `adopt`/`outside_store` and the
  opus/svg extensions (0.7.1), `open`/`find_by_hash`/`.pdf` (0.7.2), and
  dashed trait names with `rename_tag`/`rename_type` (0.7.3). Next it renames
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
  without re-keying (0.9.0 adds links: `link(id, "used-by", "boardwalk")`
  is the intended form). Cattacula still reads its own voices.db for now.
  Under 0.9 its database must be opened read-write once (adding the links
  and search tables) before a read-only `dd-serve` accepts it.
- **Silicon Circus** (before the park store) used DD per app, as a shard,
  not a shared service.
  Their case is single-best `db.store`/`db.get` with WebP normalizing.
  `check_consistency`/`vacuum` (0.3.5) is the orphan sweep they wanted.

Before editing Infocomic's image code, check with `@infocomics` (see
coordination.md).

## Reaching a store from elsewhere

Each app's DD database is SQLite on that app's server, which nothing can
open over the network. Since 0.8.0 an app can mount `DataDungeon::API`
(`data_dungeon/http`), or run `dd-serve` beside the database, so tools such
as `@curio`'s DD browser reach it over HTTPS with a read token, plus a write
token for edits.
