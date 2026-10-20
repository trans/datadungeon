# DataDungeon handoff

*Updated 2026-10-19*

**Today (Thomas, 2026-10-19): finish the remaining items and semantic
search.** Done today: the types decided and listed (0.15.2, with both
freeze fixes), piece 1 (Pirateship), a take's tracks (0.15.3, `7cca94a`),
and the `#datadungeon` topic. Next: pieces 2 and 3 (below), then semantic
search: built but unused; see "Embeddings registry" below and
`DESIGN-embeddings.md` (a draft, `a5febfd`) for where it stopped. Still
open: AI descriptions as linked text assets with their own recipe, and
search reading them; hashes as blobs and prompt compression; a word to Owl
on its depth maps' "depth of 1" descriptions; characters as assets
(Thomas). Waiting: Overlore's deploy (Thomas). Piece 2 is done
(2026-10-20).

## 0.15.4: TIFF masters (released v0.15.4 at `a229a4a`, 2026-10-20)

**Decided (Thomas, 2026-10-20):** the park's originals are tiled TIFF, 8-bit
("we don't need 16 bit. I can't see the difference"), and DD makes their
WebP. DD still stores an `.xcf` as given, for the odd one-off, with no
conversion. This answers `@boardwalk`'s question
(`mail/received/20261019-235320Z-@boardwalk--…`). XCF lost because nothing
outside GIMP reads it properly: ImageMagick refuses 16-bit files, libgimp
works only inside a running GIMP, and the Rust crates read 8-bit layers
without blending them. The reply was sent to `@boardwalk` (`7c4a5eb7`). The notice is
`#datadungeon` post 3, and `@curio` was sent the re-measure step for the park
store (`f42b5aea`).

**Checked by the apps (2026-10-20):**
- `@pirateship` is on 0.15.4 (`d055ec6`), live. Three starts with
  `rename_type` kept in boot: after the first, nothing changed in any
  table, and `asset_changes` stayed at seq 42.
- `@curio`, on a copy of the park store with a 0.15.4 dd-serve, measured
  all 76 pictures again; exactly the 17 16-bit pngs changed (#557
  `#514C50` → `#130D0F`). TIFF uploads were stored and measured, and their
  WebP was made and linked. curio 0.8.1 (`dd6b739`) thumbnails TIFF
  masters. The live park store moves when Thomas says.

**Decided (Thomas, 2026-10-20): keep deflate**, after the numbers below. They're in transfs-rs's chunk study (`92d56d9`). The question was whether the tiles should be compressed. `@curio` relays
(`mail/received/20261020-011926Z-@curio--…`) that Thomas wants the masters
left uncompressed because the store is to be on transfs, "though he thinks
Deflate is OK". 0.15.4 writes deflate. Measured as transfs stores a TIFF
(FastCDC 8 KiB, zstd level 3 per chunk, no dictionary; transfs-rs
`docs/file-types.md`, "anything else"), for a small stroke over 37 files:
- uncompressed 64×64 tiles: 1.9 MiB an edit, 69.7 MiB the first copy,
  162.7 MiB off transfs;
- deflate tiles: 2.7 MiB an edit, 57.0 MiB the first copy, 56.8 MiB off
  transfs.

Per picture that's 53 against 75 KB an edit, and 1.9 against 1.5 MB stored.
Uncompressed comes out cheaper only after about 16 edits a picture.

**Released** on Thomas's "tag and message @boardwalk"; the branch and worktree are removed:
- `require "data_dungeon/tiff"` links libtiff 4.5 or later; core DD links
  nothing new, so apps' builds can't break, and `dd-serve` requires it.
- A TIFF is stored as `.tif`, and `image/x-xcf` as `.xcf`.
- TIFFs are measured.
- `target_format: "tiff"` stores a TIFF or PNG as 8-bit 64×64 deflate tiles.
- `store_webp` and `POST /assets/:id/webp` make a picture's WebP.
- `POST /assets` takes `image`.
- 180 specs pass. The five apps type-check.
- dd-serve end to end: GIMP's 8.5 MB 16-bit export became 1.2 MB of tiles,
  and its WebP is 124 KB.
- DD's own tiles cost 2.6 MiB a small stroke over the study's 37 files,
  the same as libvips's.

**Bug found and fixed:** libpng's simplified reader took 16-bit PNGs with
no gAMA/sRGB chunk for linear light, so they measured too bright, and
interlaced ones came out wrong besides. Now such files are read raw and
rounded. All 27 park PNGs match ImageMagick: opaque exact, partly clear
within 1, alpha exact. 17 of them are 16-bit, so the park's colours need
`measure_images(all: true)` on 0.15.4. Example: the night front is
`#514C50` stored, `#130D0F` true.

**transfs-rs:** TIFF rows were added to `docs/chunk-study.md`, with
`tools/chunk-study/export_tiff.sh`; uncommitted there.

## 0.14: the prompt as sent, the wordings in it, the ratings' words (released v0.14.0 at `401dd4a`, 2026-10-17)

**Simplified (Thomas, 2026-10-16; plan `~/.claude/plans/delegated-doodling-hippo.md`,
approved), after an independent review** found DD over-engineered in places:
prompt modelling redesigned four times in three days, and on Overlore's
store the 0.13 field dedup took 426 KB against 295 KB for prompts kept
whole. Thomas: one solid simplification, a freeze on what no app uses, one
owner per store (principles.md). The template and the 0.15 plans below are
superseded.

**Committed on branch `0.14` as `4426581`** (on top of `c76640e`; the
branch isn't pushed):
- A recipe step: form, settings, `prompt` (exactly what was sent),
  `instructions` (speech's and text's second input; none for a picture),
  `wordings` (`Recipe.wording(kind, name, words)`), seed, cost, basis,
  time, references, steps. Fields, field orders, `joined`, `prompt_sent`
  and `Recipe::Text` are gone.
- Checks before writing: each wording's words appear verbatim in the
  prompt or instructions; a given `@version` matches; a new wording is the
  consumer's, a `dd:` one DD's existing words; a picture's `style` is
  `dd:`, a `flavor` named for that style. Names keep 0.13.1's
  `owner:name/purpose`.
- `named_texts` (kind, owner, name, purpose, version = 10 hex of the words'
  SHA-256, text_id); triggers refuse UPDATE and DELETE. `recipe_wordings`
  (asset, step, position, named_id). `recipes` gains prompt_id and
  instructions_id, loses sent_as_joined and prompt_sent_id. DD's owner is
  `dd`.
- Conversion of 0.13.1 and 0.13.0 stores (`migrate_prompts`): prompt =
  prompt_sent or a picture's fields joined in 0.13's order; speech text +
  style as instructions; text description + instructions; named fields
  become wordings; verified per step, raising with the store unchanged;
  `recipe_fields` kept, no longer written.
- Vocabulary, titles, the 14 approved style words, ViewWords and
  `GET /vocabulary` kept from the branch. `scripts/schema_diagram.cr`
  writes `DESIGN-schema.md` (Mermaid; 22 tables, 24 foreign keys).
- Docs: README recipes, the recommended order as advice, one owner per
  store; DESIGN-recipes.md rewritten with the history; DESIGN-types.md
  (uses, owner tags and the 409 dropped, hub deferred, 0.15 waits).
- **Checked (2026-10-16):** 170 specs pass (1 pending, S3). Fresh copies
  of all five live stores: every recipe reads back as 0.13.1 said it was
  sent (Overlore 916, Owl 97; 0 differ; 26 and 11 wordings); no other table
  changed, `recipe_fields` included; named texts kept with their ids and
  hash versions; integrity and foreign keys ok; an UPDATE on a wording is
  refused. Cattacula, Pirateship and dd-serve type-check; Overlore and Owl
  break on the removed `Recipe::Text`, as expected (they're pinned
  `~> 0.13.x`).

**Heads-ups sent 2026-10-16** (Thomas: "commit and let everyone know"):
`mail/sent/*-@overlore--0.14-simplified.md` to `@overlore`, `@owl`,
`@curio` and `@mj`, with each app's sites to change (curio's recipe panel,
`console.html:1327-1370`), answering Overlore's 492fa87f on keeping the
parts (the held template-parts draft is superseded and deleted);
`mail/sent/*-@cattacula--0.14.md` to `@cattacula` and `@pirateship`
(nothing to change).

**Rating words approved (Thomas, 2026-10-17),** r in his words, with "scenes" added
("For mature audiences: violence, blood and risqué scenes may be shown."); committed
in `98ed629`: `dd:g`, `dd:pg`, `dd:r`, `dd:x`, kind `rating`,
`db.rating_text`; the vocabulary value's `style` is now `wording`
(`vocabulary_values.wording_id`; nothing read it). 171 specs pass.

**From `@overlore` (2026-10-17;
`mail/received/20261017-065927Z-@overlore--naming-words-in-recipes-already-stored-d514ebca.md`,
`…-072951Z-@overlore--naming-our-fixed-rules-daecdcf1.md`):** Overlore is
on 0.14 on its branch `dd-0.14`, against our local `0.14` at `4426581`; a
copy of its store converted cleanly (916 recipes) and the app starts on
it. Thomas wants Overlore's own rating words named in its store as its own
(`overlore:g` … kind `rating`), DD's to be adopted later or not. 24 stored
pictures have them in their prompts, but `set_recipe(replace: true)`
refuses those recipes, whose pre-0.14 style wordings fail the `dd:` rule.
**Committed in `98ed629`:** `db.add_wordings(id, wordings, step: 0)` names
words a stored step was sent, checking only the new ones and skipping
those it names already (172 specs pass). Overlore also asks whether to name
its fixed rules (kind `rules`) and whether DD plans standard rules or a
check on `rules`: none planned (the freeze). Reply sent 2026-10-17
(`mail/sent/*-@overlore--naming-stored-words.md`): name them kind `rules`,
one wording per rule that changes on its own.

**Apps word their own styles (Thomas, 2026-10-17, through `@overlore`;
`mail/received/20261017-094046Z-@overlore--apps-make-their-own-styles-thomas-2026-10-17-f261bbae.md`).**
Overlore's same-seed comparison (64 pictures, klein, 8 styles): DD's words
alone held every style, both together looked best, but per-app flavors
make the "same" style differ anyway, and flavors were mostly mood, light
and framing. So a picture's `style` may be the app's own
(`overlore:silver-comic`); the `dd:` style check and the flavor rules are
gone, and flavor leaves the recommended order. (That art-style tags stay
standard and `style_text` stays was Overlore's ask, not Thomas's: wrong,
see "No standard styles" below.) Overlore's
eight style wordings, settled by Thomas:
`mail/received/20261017-095151Z-@overlore--overlore-s-own-styles-as-thomas-settled-them-3479273a.md`.
Also from Overlore (`…-074415Z-…-99e4db05.md`): `add_wordings` named 72
wordings in its 24 pictures (`overlore:no-text`, `overlore:no-marks`, kind
`rules`; `overlore:g`, `pg`, `r`), and a store opened by `4426581` failed
to open with `98ed629` (the `style_id` rename); now renamed on open.

**Flavor was a false lead, and the purpose with it (Thomas, 2026-10-17).**
Overlore wanted flavor, and `/purpose` (`silver-comic/figure`, `/place`,
added 2026-10-14), only because it mixed framing into its styles; with
framing in its own part one style wording serves both. **The purpose is
deprecated** in 0.14 (docs and comments; it still works) and goes in a
later release with `recipe_fields`, once Overlore and Owl are off it.
Thomas: rewriting the stored ones then is a fix to the design, despite
append-only. Proposed (not decided): each becomes a version of its name.
Owl has none (`owl:narrator`; checked its `main` and notes). Overlore's
`dd-0.14` still writes `overlore:<style>/<purpose>` as a flavor
(`prompts.cr:93`, 2026-10-17), and its 2026-10-14 store copy has 10 with
purposes; Thomas is checking with Overlore. Overlore relayed the same
(`…-162616Z-…-f15aa085.md`, `…-163203Z-…-9f72ef5a.md`): flavor out of the
docs and specs too, and "/purpose goes"; it thought its store had none.
**Committed `791b22a` (2026-10-17;** 172 specs pass, the specs' examples
without flavor; Cattacula and Pirateship type-check). **Sent 2026-10-17:**
Overlore the reply, with its 10 stored purposes and its `dd-0.14` still
on `bg`/`tile` and flavor; Owl, mj and curio the change (and `/vocabulary`'s
`style` → `wording`); Cattacula and Pirateship where 0.14 stands.

**Overlore took it (2026-10-17, `…-171508Z-…-b11c55aa.md`):** its
`dd-0.14` `ee7036d` uses its eight, one `overlore:<standard>` style
wording for places and figures, no `dd:` words, no flavor; 230 specs pass
on `791b22a`. Nothing of its reads by purpose; its 10 stored purposes are
only in old recipes, and it's fine with them becoming versions of
`overlore:<style>` whenever.

**No standard styles (Thomas, 2026-10-17): committed `401dd4a`.** Each
app names, words and tags its own styles; 0.14's vocabulary is `rating`
only. The 14 art styles, DD's words for them and `style_text` are gone; a
store opened by a pre-tag 0.14 build drops its `art-style` vocabulary rows
on its next open (assets' tags untouched, the words stay in
`named_texts`). **Shared styles fall to the hub, later** (Thomas): a
lookup table of the styles each store uses, so a store can adopt
another's and share from then on; not needed now. Lesson: I took
Overlore's "the vocabulary's art styles stay what pictures are tagged
with" (f261bbae) as Thomas's decision, and had recommended keeping them
myself that morning; Owl's notes were right. Overlore's `dd-0.14` type-checks
against it. Rechecked at `401dd4a` on the store copies (`p014/final4`): 0
differ, other tables unchanged, vocabulary `rating` only (+4 dd words);
a copy opened by `791b22a` loses its 14 art-style rows, its 3,432 asset
tags kept. Correction sent to all six 2026-10-17
(`mail/sent/20261017-175737Z-@all--no-standard-styles.md`).

**Checked at `791b22a` (2026-10-17), for the tag:** fresh copies of all
five live stores (`scratchpad/p014/final3`) convert with 0 differences
(Overlore 916 recipes, 26 wordings; Owl 97, 11), no other table changed,
integrity and foreign keys ok, 18 vocabulary values each with DD's words,
UPDATE and DELETE on `named_texts` refused, a second open changes nothing.
dd-serve, Cattacula and Pirateship type-check.

**Released v0.14.0 (Thomas: "tag", 2026-10-17):** `main` fast-forwarded to
`401dd4a` and pushed, tag `v0.14.0` pushed; a fresh `shards install` with
`~> 0.14.0` resolves 0.14.0. Notice sent to all six
(`mail/sent/20261017-185423Z-@all--v0.14.0.md`). painted-animation is moot
(no standard styles). No GitHub release page (none for earlier tags
either). The `0.14` branch and its scratchpad worktree can go once
Overlore installs from GitHub (its `dd-0.14` pins the local `0.14` branch).

**0.15.0, a small cleanup (Thomas, 2026-10-17; plan
`~/.claude/plans/delegated-doodling-hippo.md`, approved): released as
v0.15.0** (`58f1fa6`). Standard types and
tags aren't in it; they wait for a later decision. It's 0.15.0 and not
0.14.1, since apps on `~> 0.14.0` would take a patch unasked.
- The purpose removed: names are `owner:name[@version]`, `/` refused;
  `migrate_wordings` rebuilds a 0.13 or 0.14 `named_texts` without it,
  each purposed wording a version of its plain name (refused if two would
  become one).
- `recipe_fields` dropped after `migrate_prompts`.
- The pre-0.12 conversions removed (about 200 lines of `db.cr`); a store
  with `assets.pool_key` or no `asset_keys` raises "open it read-write once
  with DataDungeon 0.14". `load_types`' re-keying stays (generic).
- 166 specs pass. Store check (`scratchpad/p015/run1`): the five live stores,
  plus backups at 0.13.1, 0.13.0 and 0.12. Every recipe is as on 0.14 apart
  from the folded names (Overlore's 26 uses of its 10); other tables are
  unchanged; 0.13→0.15 direct is the same as via 0.14. All seven pre-0.12
  backups are refused unchanged, and two tried open after a pass through
  0.14. Overlore, Owl, Cattacula, Pirateship and dd-serve type-check.
  (`~/Projects/arcana-ai` moved to `~/Projects/Arcana/arcana-ai`, which
  breaks Overlore's `lib` link; type-checked with an override.)
- Live stores: Overlore's and Owl's converted to 0.14 on 2026-10-17
  (`…-185857Z-…-838f2310.md`), the park's too (assets `2c5fedd`, its
  dd-serve rebuilt; curio checked 564 assets and 27 queries against
  0.13.1, `…-200303Z-…-619b5810.md`); Cattacula and Pirateship are still
  0.13.1 until 2026-10-17 evening, when both moved after Thomas told them
  0.14 was tagged: Cattacula `cb0e66b` (488 voices checked), Pirateship
  `b16bc2a` (live store converts on its next restart, backed up as
  `voices.db.pre-0.14`). Owl's `2df2c41`/`eaecfea` (its own styles
  `owl:watercolour`, `owl:oil-painting`, `owl:90s-anime-film`; rules
  `owl:no-text`, `no-marks`, `no-people`, `no-seam`). curio 0.7.0
  (`ac96b8b`) reads 0.14 recipes, marking each wording in the prompt.
  Pre-0.12 stores are backups only; **open:** Thomas's OK that they stay
  backups (0.14 brings one forward).
- **Sent 2026-10-17:** the confirmation request to Overlore and Owl
  (`mail/sent/*-@overlore--0.15-confirm.md`). The tag waits on their
  answers and Thomas's go-ahead. **Both confirmed (2026-10-17):** Overlore
  (`…-204045Z-…-46777079.md`): 230 specs pass on `7cf4743`, a copy of its
  live store opened as its app starts (10 purposes folded, e.g.
  `overlore:silver-comic@860f00fedb`, 916 recipes, `recipe_fields` gone,
  `recipe_legacy` kept, which its startup reads). Owl (`…-203656Z-…-14636230.md`):
  no purposes, nothing reads `recipe_fields`, its two old backups stay
  backups; it bumps to `~> 0.15.0` once tagged.
- **The 26 pictures (Thomas, 2026-10-17): a clean start, no special
  versions.** Overlore's 10 purposed wordings were built on the mistake;
  its 26 pictures (24 door views 1161-1184, portrait 1138, room 1141; 6
  retired) are relinked to its current style wordings with
  `set_recipe(replace: true)`, the prompt taking the new words (Thomas:
  exact words don't matter, "not a hill of beans"). 0.15 (`58f1fa6`) drops
  a purposed wording nothing names (0.13 fields count only while a 0.13
  store converts), and folds one still named. Tested on a copy with the 26
  unlinked: 19 → 9 named texts, 916 recipes, integrity and fk ok. **Sent**
  the relink to Overlore (`mail/sent/*-@overlore--relink-26.md`); the tag
  waits on it being done on Overlore's live store. A picture's style is
  its tag (`art_style`); the wording is only the record of words sent.
  **Open:** Overlore tags `art_style` = `silver`, `realism`, `3d`, …
  while its wordings say `silver-comic`, `photorealism`, `3d-cartoon`:
  two names per style. **Thomas: retag (2026-10-17).** Sent Overlore the
  mapping (`realism`→`photorealism`, `silver`→`silver-comic`,
  `3d`→`3d-cartoon`, `golden`→`golden-comic`, `manga`→`dark-manga`,
  `pixel`→`pixel-16`, `modern`→`modern-comic`; `fantasy`, `retro` stay)
  via `update_asset(id, tags:)` with all tags, and its code to match
  (`mail/sent/*-@overlore--retag.md`).
- **Both done on Overlore's live store (2026-10-17, rehearsed first,
  backed up):** the relink (`…-215006Z-…-2d9af02d.md`; each became its
  whole style part, "The image MUST be made in this style: " plus the
  wording, as its new prompts read; only those 26 prompts differ) and the
  retag (`…-215830Z-…-3a3218e7.md`; 136 pictures, done at its startup by
  `StoreMigration.style_tags`, `5cb6ce5`, so its deployed store gets the
  same). Checked on a fresh copy with 0.15 (`p015/run2`): 27 → 17 named
  texts, the 10 gone, 916 recipes the same as on 0.14, Overlore's styles
  one version each (`silver-comic@2dbf21cd78`, …), integrity and fk ok.
  **Released v0.15.0 (Thomas: "tag", 2026-10-17):** `main` fast-forwarded
  to `58f1fa6` and pushed, tag pushed, a fresh `~> 0.15.0` install
  resolves it; notice sent to all six (`mail/sent/*-@all--v0.15.0.md`).
  The `0.14` branch and its worktree are removed (merged; nothing pinned
  it). Apps bump to `~> 0.15.0` when ready.
  **On 0.15 (2026-10-17):** Cattacula (`fc88509`), Overlore (`38d4190`;
  its local store converted, 10 purposed wordings dropped leaving 17; the
  deployed store moves when Thomas says deploy), Owl (`6d4aad9`), the park
  store (assets `bad3c6a`, curio 0.7.0 unchanged). None needed code
  changes. Pirateship too (`aaba8a1`, 2026-10-18; 14 voices play byte for
  byte). Not heard: mj.

## Standard types, in pieces (0.15.2 released at `c7fb237`, 2026-10-19)

**Decided (Thomas, 2026-10-19):**
- **Standard types stay:** "we can't drop standard types -- sharing would
  become completely impossible then." (I had recommended dropping them as
  styles went; wrong for types.) Types come before semantic search, since
  search records what's embedded in a type's registration.
- **In pieces:** "do one type first, make sure that goes smoothly, then a
  few more, and then the rest." So the strict check comes last: 0.16's
  `register_type` refuses unlisted names once every store has moved.
- **`register_type` stays** (one owner per store: the owner keys each
  standard type for its own lookups); shared tags beyond `rating`, several
  values per tag, the see-through check and "moving is video" wait.
- **`subtype`:** one shared tag for an app's own kinds of a type, its
  values the app's words. Thomas asked whether it should be a field; a tag,
  since it can be in a key, with one name so curio and copies can find it.
- **`automaton`:** a new type for a character's frame graph (mj's Bard,
  in mj's `TODO.md`, never mailed to us). `puppet` was mj's floated name;
  Thomas: marionette setups will come, so puppet and marionette are kept
  for rigs.

**Built in 0.15.2:** `DB::STANDARD_TYPES` (26 types, served by `GET
/vocabulary` as `types`), `DB.standard_type?`, `subtype` in the
vocabulary; the two freeze fixes, now needed by the moves (re-registering
with only non-key changes needs no `rekey`; MatchIndex deletes a renamed
type's files on open; it already followed renames and joins through the
change log). 169 specs; dd-serve type-checks.

**Pieces** (mapping in `DESIGN-types.md`, "Moving existing stores"):
1. Pirateship `voice` → `speech`. **Done 2026-10-19** (Pirateship
   `4fb2fde`, live store converted after a backup; 14 voices byte for
   byte; only type, keys, search rows and test-play counts differ;
   integrity and foreign keys pass; `mail/received/20261019-200327Z-…`).
   Its `boot` registers `speech` then calls `rename_type`, kept so
   production converts on first deploy. **Not smooth:** a `rename_type`
   with nothing to move still logged all 14 to `asset_changes` and
   rewrote search rows on every start. **Fixed in 0.15.3 (`7cca94a`):**
   it returns early when `from` has no assets, registration,
   indexes or tags (spec fails without it; Pirateship's boot run three
   times on a copy: dumps identical after the first). Opening a store
   still rewrites its triggers, so the file's bytes change but no rows.
   The 0.15.2 notice went out as post 1 of the new `#datadungeon`
   topic (coordination.md), not as mail to each.
2. Cattacula; the park (`stage-standup` → `speech`); Owl (two types join
   into `drop`). **Asked 2026-10-19** (Thomas: "go ahead with piece 2"),
   each by direct note after a rehearsal here on `.backup` copies made at
   23:49Z with 0.15.3 (scratchpad `piece2/`: `rehearse.cr` plus
   `compare.py`):
   - Cattacula `voice` → `speech`: 488 moved (`d54c150a`). It's on
     0.15.0, so it takes 0.15.3 first.
   - The park store goes to `@curio`, who keeps it until it's on the
     standard types and then hands it to `@boardwalk` (Thomas, via
     curio). `stage-standup` → `speech`: 488 moved; the 76 props are
     untouched (`aa12e52b`). Its import script reads Cattacula's `voice`.
   - Owl (`f3b980da`): first `subtype` `scene` and `frame` (38 tagged),
     then `drop` keyed `world subtype`; 26 + 12 → `drop`, 47 → `map`,
     11 → `speech`, 1 → `prop`. Its library also reads other stores'
     `background`, `backdrop` and `room`, which become `drop` in piece 3.
     After the join, a frame with a scene's bytes would get the scene's
     id back through `AlreadyStored`; none share bytes today.

   On each copy, nothing but the type, the keys, the search rows, the
   change log (and Owl's new `subtype` tags) differed. Integrity and
   foreign keys pass, and a second run changed nothing. curio told
   siliconcircus that Thomas expects the move "done with DataDungeon 0.15.4
   and 0.15.5"; piece 2 needed no new release.

   **Done by all three, live, 2026-10-20**, each rehearsed on a copy
   first, backed up, with the call kept in start-up. Each matched the
   rehearsal, and none found anything rough in DD:
   - the park store: assets `089a279`, backup in `data/before-speech/`.
     All 564 assets and 14 curator queries answer the same through
     dd-serve. The import script reads Cattacula's `voice`, or `speech`
     once Cattacula has it.
   - Cattacula `77621f1`, pinned `~> 0.15.3`.
   - Owl `d2a371c`. Its `style` tag now holds Owl's style name. Its
     remote searches read `drop` beside the old names and skip `subtype`
     `frame`.

   **Cattacula's warning, for piece 3:** a build from before the move,
   run against a moved store, finds none of its assets. Cattacula's would
   voice its whole library again through TTS. So an old build must not
   run against a moved store; no DD release can stop it, since the old
   build runs the old DD (mail/received/20261020-*).
3. Overlore (13 types into 6, subtypes, its transcripts go, `legacy` to
   decide).
Then 0.16: unlisted names refused. Then semantic search, on the
registrations.

**From `@mj`, 2026-10-19 (`mail/received/20261019-171409Z-@mj--…`),**
after a talk with Thomas. Only the first is settled:
1. **The automaton**, as mj stores it: the Bard's `graph.yml`, compiled to
   `graph.json` (nodes of body frame plus mouth shape, weighted
   neighbours, a walk rule per pose, moves between poses). Matches
   `DESIGN-types.md`, and adds: **one automaton per set of frames that
   connect**, so the cartoon and realistic Bards are two. In
   DESIGN-types.md since 0.15.3.
2. **Choreography is blocking in the script,** in Yarn markup on the word
   a pose starts (`[pose spread/]My friend!`), timed at play from the
   take's word timings; no new type. Thomas: "sounds like a good idea".
   Asked of us: should the script type's notes name the three kinds of
   direction (a moment `[sighs/]`; a state held until the next of its
   kind, like a pose; a span `[whisper]…[/whisper]`, ending at the line's
   end if unclosed), or leave each direction's meaning to the app.
   **Superseded** by Overlore's note below.
3. **Characters as assets** reopens Thomas's 2026-10-13 "no character
   entities". A character asset holds a sheet (description wording,
   reference pictures, voice id), with others linked to it (`depicts`,
   `voiced-by`). Thomas is leaning that way, undecided. Checked: links
   carry data (`DB#link`), but DD has no copy between stores, so "copying
   brings its kit along" needs a copy that follows links. A character's
   words are already a named wording (kind `character`, DESIGN-recipes),
   so a sheet should name that wording, not copy it. **Open.**

**From `@overlore`, 2026-10-19 (`mail/received/20261019-174900Z-@overlore--…`),**
after a talk with Thomas, sent to mj too:
- **Choreography is the app's, not the script's, and not in DD**
  (Thomas). Pose names would tie a script to one automaton (the cartoon
  Bard has 5 poses, the fantasy one 19). Instead an app's agent reads an
  automaton and a take (words with times) and makes its own, Rhubarb-like,
  perhaps varying at random each play, and keeps it in its own database.
  Thomas: "I am not sure we then need to store those in DD".
- **A script may pin a required pose** (the bow at the end; Thomas). Body
  directions mustn't reach the voice engine. Overlore's proposal:
  `pose` is the body's tag (`[pose=bow/]`), every other tag the voice's,
  turned into the engine's own syntax by the app; unknown tags are errors.
  Thomas: "I think that makes sense" (2026-10-19). Written into
  DESIGN-types' Scripts note in 0.15.3 as a convention DD doesn't read.
- **For DD:** a script stays a `script`; no choreography type; `sequence`
  stays rendered media. **Asked of us:** a take's two tool-made tracks,
  word times (Whisper) and mouth cues (Rhubarb `.cues.json`), go with the
  speech, as fields, as small `data` assets linked to it, or left to the
  app. Word times aren't kept anywhere today. **Decided (Thomas,
  2026-10-19): in with the speech,** as its own data ("yes, go ahead and
  let overlore know"). **Released as v0.15.3 at `7cca94a` (2026-10-19;
  Thomas: "let's move forward with 0.15.3"):** `asset_tracks` (asset, name,
  tool, cues as `[start_ms, end_ms, value]` JSON, made_at), `set_track` /
  `tracks` / `track`, `STANDARD_TRACKS` (`words`, `mouth`), `GET|PUT
  /assets/:id/tracks[/:name]`, `/vocabulary` `tracks`. A read-only open
  of a store no 0.15.3 has opened reads no tracks rather than refusing.
  174 specs; tried with dd-serve on a Pirateship copy with Overlore's
  real Rhubarb cues. **Overlore told** (`mail/sent/20261019-191518Z-…`).
  Thomas: "let's check with Overlore and then we can tag", so Overlore
  was asked to check the shape (`mail/sent/20261019-191828Z-@overlore--before-0.15.3-is-tagged-does-the-tracks-shape-fit.md`);
  **Overlore's answer** (`mail/received/20261019-192407Z-@overlore--…`):
  the shape fits. One change, made on the branch: a `words` value is the
  word as written (punctuation kept) when the tool aligns a known text,
  as heard when it transcribes. Also written down: `tool` names the
  options that change the result (`rhubarb 1.14.0 --dialogFile`); only
  the start order is checked (zero-length words, ends past the next
  start). 174 specs; a fresh `~> 0.15.0` install resolves 0.15.3. The
  notice is `#datadungeon` post 2; the `tracks` branch and worktree are
  removed.
  The speaker is left out: who speaks is a character (open); the voice
  is in the recipe.
- For mj: a line per pose on what it expresses, which poses are rests and
  endings; and whether one-way links in the graph are by design (all
  within-pose links go both ways today; moves between poses go one way).

## 0.15.1: pictures added by hand (released v0.15.1 at `f9c4bc6`, 2026-10-19)

**Decided (Thomas, 2026-10-19):**
- dd-serve gets an upload route, and curio a button for it: such assets
  "will occur".
- The prompt isn't the description. An asset added by hand has no recipe,
  `generated: false`, and its words as its `description`; no flag is
  needed. (Thomas first asked for a boolean marking a prompt as only a
  description; told a prompt exists only in a recipe: "Good thinking.")
- Later, an AI's description of a picture is its own text asset, linked
  to the picture, with its own recipe (vision model, what it was asked, the
  picture as reference): "How the AI describes an image has a recipe too."
  Search reads only description and tags, so that text needs adding to it.

**Built:** `POST /assets`, multipart `file` + `asset` JSON {type, tags,
custom, description, permanent, made_at, supersedes}; 409 with `asset_id`
when the type holds the bytes. README: `description` is the asset in words,
not its prompt (it said a generated image's description holds the prompt).
`shard.yml` 0.15.1. 167 specs pass; dd-serve type-checks; a real PNG
uploaded with curl to dd-serve on a copy of the park store came back
byte-identical, measured, with no recipe; the repeat gave 409.

**How apps use `description` today** (copies, 2026-10-19): Overlore the
game's room text the prompt was built from; speech the words spoken (= the
prompt); Owl's scenes words that differ from the prompt and read like the
finished picture described ("at sunrise or sunset"); Owl's depth maps a
label ("depth of 1"). Pictures with no recipe already exist: the park's 76
props, Overlore's 11 backdrops.

**Released (Thomas: "commit, tag and send", 2026-10-19):** `main`
fast-forwarded to `f9c4bc6` and pushed, tag pushed, a fresh `~> 0.15.0`
install resolves 0.15.1. Sent to @curio only: the route and a request to
plan the button (`mail/sent/*-@curio--datadungeon-v0.15.1-*`). The other
apps weren't told; they need nothing, though a `dd-serve` serves the route
only once rebuilt. The `upload` branch and its worktree are removed.
**curio's button is out:** curio 0.8.0 (`f5ed8fb`, tag `v0.8.0`), built
against `POST /assets`. curio passes the form through with its own write
token, so the token never reaches the browser. curio tried it on a copy of
the park store under 0.15.3: an add, a 409 for the same bytes with other
tags, a repeat, and a new take
(`mail/received/20261019-225928Z-@curio--…`, `…232718Z-@curio--…`).

**Next (as of the 0.14 tag; every app has since moved):** the apps move (Overlore switches to GitHub `~> 0.14.0`; Owl moves
its prompt and narrator code; Cattacula, Pirateship and the park bump, the
park's `dd-serve` rebuilt). Later: remove the purpose (rewrite stored ones
as versions of their names; Overlore agrees) and drop `recipe_fields`
once Overlore and Owl are off them; the standard types and tags (0.15),
starting with an inventory of each store's types and tags.

**Prompt as one template (`@mj` with Thomas, 2026-10-16; proposal in
`mail/received/20261016-172503Z-@mj--prompt-as-template-867b37d4.md`,
reply in `mail/sent/*-@mj--prompt-as-template.md`).** Replaces the fields
before the tag: a recipe stores one prompt, the app's words with Mustache
tags for registered wordings, pinned by DD at expansion
(`{{style datadungeon:golden-comic@1}}`); the field order, `prompt_sent`
and order 1/2 go; stored recipes convert once. **References are full names
(Thomas, 2026-10-16),** not codes or row ids: ~108 bytes a prompt is ~3.5%
of a million-asset store; zlib took Overlore's 32 template prompts from 659
to 399 bytes on average, and compression can come later without a format
change (SQLite options: sqlite-zstd, sqlite_zstd_vfs, ZIPVFS, compress.c).
**Open (DD's answers sent, not settled):** bare `{{style}}`/`{{rules}}`
need 0.15's standard tags on the asset; a bare `{{rules}}` naming rule
(`overlore:g`?); light as plain words, not a tag; a (recipe, named text)
reference table; every form, not only pictures; no plain Mustache renderer;
`character` as a named text field; a literal `{{` refused. **Sent
2026-10-16** (`mail/sent/*-@overlore--0.14-hold.md`): Overlore and Owl
asked to hold off on the 2026-10-15 changes.

**Wording versions and style tags (Thomas with `@mj`, 2026-10-16; mj's
`mail/received/20261016-191705Z-*-af9ffbc5.md`, reply
`mail/sent/*-@mj--wording-versions.md`):**
- A version is a hash of the words exactly as sent: the first 10 hex
  characters of `texts.hash` (SHA-256), not mj's base 32. Numbered
  versions convert in 0.14. Triggers refuse UPDATE and DELETE on a
  wording; a rename is a new name.
- DD's owner is `dd`, not `datadungeon`. The standard styles are `dd`'s,
  not the proposing app's: `dd:` marks standard and shareable, an app's
  custom style later is its own (`owl:kiddy-cartoon`).
- **Style and flavor are one tag:** the app writes
  `{{style dd:silver-comic overlore:place}}`, stored pinned as
  `{{style dd:silver-comic@<hash> overlore:place@<hash>}}`; no `flavor`
  tag, so no flavor without its style and no match check. A flavor's name
  is its purpose (`overlore:place`), filed per style; `/purpose` goes
  (`overlore:silver-comic/place` converts to `overlore:place` under
  silver-comic). DD's words take no purpose. DD's words changing under a
  flavor is fine (Thomas).
- **Thomas, 2026-10-16 (through `@mj`, `a190f035`):** a style with no
  wording of the named flavor falls back to DD's words alone, not refused;
  names don't nest (`place-cave` doesn't fall back to `place`); one flavor
  per tag; a change to a standard wording only refines it and isn't
  announced.
- **Ratings (Thomas's view, not final; our reply
  `mail/sent/*-@mj--rating-words.md`):** one DD wording per rating
  (`dd:g` …) for every form, saying what's suitable rather than listing
  what's forbidden; speech needs none; a per-form wording only if one
  fails. The words themselves are still to write and approve.

**`@overlore`, 2026-10-16 (`492fa87f`; Thomas wants it clear):** the
template keeps the fields' ideas. framing, staging, light and directives
stay parts a prompt considers, and the worked-out order stays the
recommended one, in DD's docs (how a template is built), not dropped with
the stored fields. Overlore still renames `preamble` to `framing` and
follows the order. Reply held: `mail/drafts/@overlore--2026-10-16-template-parts.md`.

**Before release:**
- **Open:** Thomas is asking `@owl` about `painted-animation` (where it
  came from: Owl's mail `b0e68bb8`, approved 2026-10-14). A value seeded
  into stores can't be taken back by a later release.
- **Sent 2026-10-15** (`mail/sent/*-@overlore--0.14-changes.md`), to
  `@overlore` and `@owl`, copied to `@mj`: the `flavor` field (missing
  from the order sent to mj), framing, directives, `style_text`; Overlore's
  oil-painting wording; Owl's "change ONLY this:" edits.
- Then: merge, tag v0.14.0 (ask before pushing the tag), GitHub release
  notes, notices.
- **After the template rework (Thomas, 2026-10-16):** a schema diagram,
  `DESIGN-schema.md`, a Mermaid ER diagram generated by a script from a
  fresh store (tables and declared foreign keys; the FTS5 `asset_search_*`
  internals left out), so it's regenerated rather than kept by hand.

**To settle before 0.15:** whether a use is a tag or a table
(DESIGN-types.md vs our 2026-10-15 mail to mj); how several values sit in
an index key; the JSON shape for tags (Owl's `as_s?` rating filter fails
open if values become arrays); the `lighting`/`condition` names. Overlore
wrote its own `named_texts` row directly to rename `pixel` to `pixel-16`
(its `c8332d9`): fine here, but apps editing DD's tables is worth a word.

## 0.11 part 1: keys as an index (released v0.11.0, 2026-10-09)

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

**Released on GitHub, not yet in this checkout** (release.md): Overlore
still builds from this checkout, and its startup migrations (`level_voices`,
`voices_to_mp3` in `store_migration.cr`, `6f83d76`) re-store clips and rely
on the store replacing in place; 757 clips were pending in its live store on
2026-10-09. Under 0.11 they'd need `supersedes: id` and `retired_at IS
NULL` in their queries, or to run under 0.10 first. Told 2026-10-09, and
asked to install DD from GitHub; its TODO.md (`29bb187`) plans the move.

## 0.11 part 2: image fields (released v0.11.1, 2026-10-09)

Thomas asked for the rest of 0.11 the same day; 0.11.1 because it only
adds. It also fixed `media` (below) and stopped comparing the deprecated
`pool:` in registrations (`@overlore`'s request: dropping it raised). On `keys-and-retiring`:
DD measures pictures on store (`ImageProbe`: PNG and WebP fully, still or
animated; GIF size and frames, JPEG size, from headers); application
fields (view, light, anchor, real size) with the readable `Direction` and
named directions (search words, `image_views` SQL view); `image_animation`
(the animation fields moved out of `image_meta`) and `image_keyframes`
(`set_keyframes`, content box measured per checkpoint); `ImageFilter`
(ranges, view or light within an angle, named direction, matching at any
checkpoint); `update_asset(image:)`, `measure_images`; best match
`cycles:` and `match_fields:`. HTTP for each. 135 specs, S3 specs, Overlore
and Cattacula type-check; a copy of Overlore's store measured 232 pictures
in 1.7 s.

`media` came out as "image" for any content type DD didn't know (older
than 0.11: Overlore's 100 JSON banter scripts). Thomas asked for it fixed
(2026-10-09): `DB.media_of` takes the top-level type (image, audio, video,
text, model, font), JSON/XML/YAML as text, the rest "data"; the first open
by 0.11.1 relabels the rows marked image that aren't (a copy of Overlore's
store: scripts became text, in a 0.04 s open). **Open:** field filters are
checks on each candidate, not starts: a listing by fields alone walks the
type.

**0.11.2 (released 2026-10-10):** two items from `@curio`'s API
list that we told it we'd adopted (2026-10-09) but the design doc never
recorded, so 0.11.1 missed them: picture fields in list rows
(`GET /assets?meta=1`, `load_image_meta_batch`) and counts per named
direction (`view_counts`, `GET /types/:type/views`). Views keep their name
(`image_meta.view_name`), counted under the reserved tag `@view` in
`asset_tag_counts` by triggers, which every read-write open now recreates;
tag names starting with `@` are refused. Lesson: put a consumer's
accepted asks into the design doc when accepting them.

**0.12 released 2026-10-11: `v0.12.0` at `2698701` on GitHub's main
(this checkout fast-forwarded to it 2026-10-13, see release.md).** Storing needs a registered type; the type's own
order is an index in asset_keys (consumer and name empty); the
`pool_key` and `pool` columns go on the first read-write open (one-way;
a read-only open before that fails); `AssetRecord#key` and `key_for`
(the `pool_key` names deprecated, JSON carries both through 0.12);
`get`/best matches rank by rating then newest and skip flagged. 141
specs, S3 against Garage; copies of Overlore's, Cattacula's, Pirateship's
and the park store upgraded with every asset found by traits; Overlore,
its specs (one deprecation warning), Cattacula and the park's types.cr
type-check against it. The park's `bin/dd-serve` must be rebuilt after
the park store is opened by 0.12. Release notes drafted for Thomas.

The plan as written (Thomas, 2026-10-09): fold `pool_key` into the index table,
with the registration requirement. Storing requires a registered type;
the type's own trait order becomes its entry in `asset_indexes` (its
default index) and its keys move to `asset_keys`; the `pool_key` column
and caller-built keys (`store(…, pool_key:)`, `canonical_key:`) go;
`AssetRecord#pool_key` reads from that index (maybe renamed `key`); the
planner loses its two kinds of range. `get(key)`, `find_pool(key)`,
`find_group(prefix)` and SemanticIndex's key filters keep working through
the default index. Deprecated in 0.11's docs, and announced 2026-10-09 to
`@overlore` (it builds keys for `portrait` and `background` and stores
`legacy` unregistered), `@curio`, and Cattacula's inbox. **Unblocked
2026-10-11:** `@overlore` registered all three and stopped passing
`pool_key:` (its `5e34196`); we asked it to register before its one-time
migration, since 0.12 refuses stores into unregistered types; done the
same day (its migration renames `tile` to `panel` with `rename_type`). `@curio` (2026-10-10):
its card captions had read `pool_key` in `public/console.html` (our search
of its Rust sources missed it: search every file); since curio `c479811`
only a display-only "index key" row is left, and it reads
`registration.pool_traits` from `GET /types` for trait order, so renaming
that needs a line in the release notes.

**Also in 0.12: rank by `rating`, not `version`/`quality` (Thomas,
2026-10-11).** Among the takes `get` chooses from, and among equal scores
in best matches: higher `rating` first (no rating counts as 0), then the
newest `made_at`. `get` and best matches skip flagged assets; listings
still show them, for review in curio. `rating` has one owner: Overlore
keeps players' reactions (wow!, love!, hate!, report!) and writes their
total into `rating`, report! into `flagged`. An admin's reaction in curio
goes to Overlore as one more (maybe weighted) reaction, not straight into
`rating`; the admin's hard calls are flag/clear and retire/reinstate,
which win whatever the rating. DD never learns the reaction words.

**Embeddings registry (draft, Thomas, 2026-10-11): `DESIGN-embeddings.md`,
committed as a draft in `a5febfd`.** Semantic search is built but unused:
not in `dd-serve`, no consumer. Decided: named entries per consumer and
type; same set of parts shares one recipe and its vectors; a recipe is a
set, written in one fixed order (measured: order moves vectors about as much
as a changed value in the whole asset). Proposed, to confirm: parts =
tags + `description`, `prompt`, `view`; `default` entry; one model per
store. **Next:** Thomas reads it through.

**Recipes (Thomas, 2026-10-12: tables, not a compressed log;
`DESIGN-recipes.md`, a draft, `a5febfd`).** `generation` leaves the assets row,
split into parameter sets and long texts each stored once by hash, with a
small row per asset; prompts passed in parts; a part equal to the
description points at it; measurements (loudness, `kept`) move out. About
the savings of compressed segments (considered first, 2026-10-11), with
direct reads and SQL queries. Records become complete enough to reproduce a picture (the full
request, `staging_prompt` included); references as `derived-from` links.
Measured on Overlore's store: 916 records, 194 KiB, gzip 29x. Answers
(2026-10-12): `@curio` wants a separate call (`GET /assets/:id/recipe`,
fetched when its panel opens) and a cheap flag on the row saying a record
exists; keep `generator` and `generated` on the row. `@overlore` reads
records by id only, never at runtime; three startup migrations read
`generation` (two by `json_extract` in SQL), which it will drop or
rewrite before the move; its cost ledger already logs each request as
sent. `@mj`: by id a few times a week by hand; a drift audit by camera
and date range twice a year, a slow scan is fine, don't cut segments for
it; keep `staging_prompt` verbatim; only `klein` honours a seed, so other
cameras' records are evidence, not exact reproduction.

2026-10-12, revised: **a standard recipe shape per media type, defined by
DD and shared by every app, not registered per consumer** (Thomas: the
point is sharing). Picture prompt slots preamble, subject, description,
theme, style, rules, staging; speech: model, voice, speed, style, text.
Settings stored once by hash; named texts (`style = silver`) versioned by
hash order (`silver@1`, `@2`); descriptions one table, role per asset;
`prompt_sent` checked, kept only if it differs. Non-standard bits go in
the app's own table keyed by asset id. `@mj`: its camera adds no words
(final prompt = caller's + staging), `prompt_sent` in every result,
offers `prompt_parts` with roles; goal reworded to "say exactly what was
asked". `@overlore` confirmed fit; measurements unread (`leveled-to` is a
setting). Settled since (Thomas): named texts as fields (slot, owner, name,
version) pointing into one untyped texts table, owner = consumer name,
`overlore:silver@2` only the written form; slots joined with one space,
empty skipped; Overlore's measurements dropped; Overlore names concurrent
wordings apart (`silver`, `silver-figure`). **Open:** `@mj` on
measurements; the asset's description as a text reference; release.

**0.13 also gets `update_asset(id, permanent:)`** (Thomas, 2026-10-13,
rather than a 0.12.1): `@owl` stored its older scenes, props and frames
`permanent: false` and wants to mark them. Tell `@owl` when it's tagged.

**Standard asset types (from `@overlore` and Thomas, 2026-10-13; written
up in `DESIGN-types.md`, uncommitted).** DD defines a short list of types by role,
each spanning media (pictures: backdrop, panel, overlay, sprite, texture,
icon, map; sound: speech, dialogue, music, ambience, effect, recording;
text: prose, script, transcript, log; document, data; 3D: set, prop, figure,
motion; sequence; font), with rules (a backdrop or panel has no
transparency) and properties (tileable, loopable, template, language).
**Thomas, 2026-10-13: an app's use is not a registered type.** A room is
just a backdrop image; `overlore:room` is a tag saying how Overlore uses it,
so Overlore finds it easily. (I had read `@overlore`'s "subtype, registered
under a type with its traits" as a registration.) Also in the message:
scripts in Yarn Spinner's line syntax; recipe shapes for chat text,
dialogue, steps and assemblies; the description as a text reference
(`@overlore`: yes); and whether the per-asset recipe row is one row or one
per field (one per asset plus one per field used; the doc needs fixing).
Settled the same day (Thomas): **tags are claims** ("something in it has
red hair"), no character entities; so tags hold several values, and the
shared standard is the tag vocabulary, a type naming only the tags in its
key; uses never in a key. Names: `drop` (backdrop), `scrim` (overlay);
the panel's name, `sprite`/`prop` and `map` still open.

**0.13 released: `v0.13.0` at `ec9298e` (2026-10-14),** after the reviews
sent 2026-10-13 to `@overlore`, `@mj`, `@owl` and `@curio` came back and
were answered (`.ai` `029db8b`). All five apps type-check against it,
copies of all five stores upgrade cleanly, S3 specs pass on Garage.
Upgrade notices sent 2026-10-14 to `@overlore`, `@owl`, `@curio` (with the
park store's move) and `@pirateship` (`.ai/mail/sent/*-v0.13.0.md`); none to
Cattacula, then thought to have no agent (it has: `@cattacula`).
**Thomas, through `@overlore` (2026-10-14): the description is the fallback
field.** An app fills what fields it can from the front (preamble, subject)
and the back (style, rules) and leaves the rest in the description, in
order, so the fields joined are exactly what was sent and no prompt is kept
whole; a prompt that fills no field is all description. Overlore splits its
916 records that way; Owl was told the same.
**The order gets tested** (Thomas, 2026-10-14): `@mj`, with Thomas's help,
will analyse whether another field order works better, after researching
whether the image providers give guidance on prompt order. Until then the
0.13 order stands. Owl told the same day. **If the order changes,**
records stored as "sent as joined" must keep their old join: `recipe()`
rebuilds `prompt_sent` from the fields in the *current* `Recipe::FIELDS`
order (`recipes.cr`), so a new order would silently rewrite what old
records say was sent. Before changing it, store those records'
`prompt_sent` explicitly (or record the order with each recipe). Owl is on
0.13 with every record converted (consumers.md). **Done 2026-10-14:**
`@mj`'s design replaces the order (below, "Picture prompts redesigned").

**Style wordings (`@overlore`, 2026-10-14).** Thomas's rule, passed on by Overlore: no custom top-level
styles; a variant of a style is the same style. `overlore:silver-figure`
reads as a style of its own, which DESIGN-recipes.md invites ("two wordings
in use at once get two names"). Overlore suggests: a wording filed under
the standard style with its purpose as a qualifier (`figure`, `place`), so
the picture's style tag stays standard; a small label table for curio
(style, owner, purpose, version: "Silver Age comic, Overlore's figure
wording, v2"); versions per style and purpose, no supersedes link.
Meanwhile Overlore stores style fields as plain texts, found by hash, and
asks whether naming them later converts nothing on its side. As built it
would leave them unfound by name: `with_text` follows
`recipe_fields.named_id`, which a plain text leaves empty, so naming a
wording later must also name the records already holding that exact text
in that field (a backfill on DD's side, or matching on `text_id`).
**Thomas, 2026-10-14: yes to a purpose column,** if it fixes this without
other grief. Checked: the only named text in any live store is Owl's
`owl:narrator` (11 records); Overlore's store isn't on 0.13, so it can
convert once, with names and purposes, on 0.13.1 (no backfill needed). The
cost is one rebuild of `named_texts` in 0.13.0 stores (its unique
constraints change; ids kept, checked before the old table goes), and a
`/purpose` in the written form that curio must parse. DESIGN-recipes.md
updated (not yet committed); reply sent 2026-10-14
(`mail/sent/20261014-081331Z-@overlore--style-purpose.md`). **0.13.1
built 2026-10-14, not yet committed:** `named_texts.purpose`, names
`owner:name/purpose`, `with_text`/`texts:` narrowed by purpose,
`named_texts` returning `name/purpose`; `migrate_named_texts` rebuilds a
0.13.0 table inside setup_schema (ids kept, compared before the drop,
foreign keys checked after). 164 specs; the five apps type-check; copies
of the four 0.13.0 stores (Owl, Cattacula, Pirateship, park) change in
`named_texts` alone, and Overlore's 0.12 copy upgrades with 0 differences.
**Released: `v0.13.1` at `4df221b` (2026-10-14);** a fresh `~> 0.13.0`
install resolves it. Notices sent the same day to all five (`mail/sent/*-v0.13.1.md`):
curio told about `/purpose`, Overlore answered on "first seen" (the order
of calls).
`@overlore` accepted it the same day, having read the held draft through
Thomas (`mail/received/20261014-083946Z-@overlore--style-purposes-yes-it-works-for-us-go-ahead-with-0-9aeed7b6.md`);
the reply went anyway, as the record. **Its question, to answer in the
0.13.1 notice:** in a conversion, is "first seen" the order of
`set_recipe` calls or the recipe's `generated_at`? As built, the order of
calls (`put_named` takes the next number when it inserts).

**Style bases for 0.14 (Thomas, 2026-10-14; `@overlore` asked, reply in
`mail/sent/20261014-162208Z-@overlore--style-base.md`).** Each art style in
the vocabulary gets a base, short prompt text, and a picture's style is the
base followed by the app's wording, which holds only the flavouring: it
narrows the style or serves the purpose, never asks for another style. DD
gives an app the base before it generates and records the base each picture
got, so a base improved later doesn't rewrite older records. Thomas turned
down a word-for-word prefix check on wordings (brittle, and it repeats the
base). Bases stay short ("Silver Age comic" may do alone), adding key
differentiators only where a model may not know a style; refinements, not
new descriptions. Overlore's pixel art is `pixel-16` (Thomas). Records
before 0.14 keep their wordings. **Settled (Thomas, 2026-10-15):** the
base is the `style` field, and the app's wording is a field of its own,
`flavor`, after it (see 0.14 above).

**Picture prompts redesigned (`@mj` with Thomas, 2026-10-14; mj's
`notes/picture-prompt-design-v1.md` at its `f712770`; originals in
`mail/received/20261014-2*-@mj--*`).** The 0.13 order was mj's habit, not
measured (its slot-order test came back null on `klein`). Agreed, with
Thomas's changes (our reply, `mail/sent/20261015-001446Z-*--picture-prompts.md`,
to `@mj`, copied to `@overlore` and `@owl`):
**rules · framing · style · theme · subject · description · staging · light · directives.**
- `rules` are the fixed ones, the same for every picture (the rating's
  limits, no signature). A fixed rule mustn't contradict a description
  (Thomas: a number on an apartment building needs text, so "no text unless
  the description asks for it").
- `framing` replaces `preamble`: how much is in frame, the overall shape.
- `staging` is the DM's words for where each figure is and the view, no
  longer the camera's words. Mood is part of `theme`.
- `light` is new: the standing light, inherited from the place's measured
  light.
- `directives` (Thomas's name, replacing mj's `changes`): the kind's own
  rules for this picture ("each named thing drawn once" for a room) and what
  an edit or a reference shot changes and keeps. mj's note found Overlore's
  "each thing once" held better last than in the middle.
- **No `kind` setting** (Thomas agreed): the type (`drop`, `plug`) and the
  app's tag (`overlore:room`) already say it; turning a kind into framing,
  rules and directives is the app's code.
- **Thomas decided DD owns turning `view`/`light` vectors into words.** mj
  handed over `src/arcana/view.cr` (mj `f5c0f45`, 176 lines, `json` only,
  no specs; its message has a table of outputs to spec from). The phrases
  are lowercase fragments; the caller punctuates.
- **To build, in one release:** each recipe records which field order its
  prompt was joined in (records already stored keep the 0.13 order; no whole
  prompts stored); `preamble` renamed `framing` on old rows
  (`recipe_fields.field`, `named_texts.field`; an update, nothing deleted);
  `light` and `directives`; `view.cr` with specs. Owl's store copy
  (2026-10-14) had 13 picture records rebuilt from 3-4 joined fields, which
  a plain order switch would silently rewrite. Overlore can convert its 916
  records now, under the 0.13 order.
- Answered for Thomas: `template` (DESIGN-types.md) came from Overlore's
  2026-10-13 proposal, its decrees being prose with blanks filled from the
  player's input; it marks a text as fill-in-the-blanks, with Mustache slots.

**The hub: what `@curio` needs from each store** (2026-10-14, `.ai`
`8ba2938`; Thomas: the hub waits until current work is done): the bucket
itself marked shared, checked on open, rather than each app's `shared:`
(one app leaving it out deletes others' files; a store older than 0.13
must never use the bucket); each store registering itself in the bucket
(name, where served, last opened), so the hub clears only when every
registered one answers; `GET /objects` paged or streamed, a page in one
transaction; the run's start judged by the bucket's clock (a marker's
date); a copy recorded without the bytes, over HTTP (tags, description,
recipe, image fields, `copied-from`), checking the file and refreshing its
date; text hashes in a recipe's JSON (versions are per store); a stable
sort with a cursor for merging; `GET /store` (name, version, shared, which
bucket); later a change feed (`asset_changes`).

**Reviews in (2026-10-13; `@mj` still out; originals at `.ai` `0905d20`).**
For 0.13 (recipes): `@curio`: references can't be followed to assets
(wants `?file_hash=` or automatic links), no HTTP for `with_text` (wants
`text.style=overlore:silver[@2]`), a shared description can't be fixed
once for all its assets, `description: ""` stores an empty text instead of
clearing, `cost` has no unit. `@overlore`: a cost basis beside the cost
(rate-table edition, reported by the service, estimated). `@owl`: a step
should reference an earlier step's output (low priority); where a placement
instruction ("where the red ring is") goes; old records with only settings
and `prompt_sent`; `q` to search descriptions and recipe text.
For types, Thomas's decisions relayed: **each app gets its own store**,
plus a common store to copy from, files deduplicated in R2 (so deleting a
file must know every store: DD today deletes an object no row *in its own
store* uses, and vacuum treats its prefix as its own); **an app keeps tags
of its own**, searchable and usable in its index keys; texts content-addressed,
so an index keys on the description's hash (Overlore's `content_hash` and
`look` tags go); **custom art styles** (Owl: Thomas asked), promoted when
several apps use one; ground recorded wherever possible (a prop's anchor;
a drop's ground line with scale). Also: Overlore's retro leaves the art
styles (`ascii` later); `panel` suits Overlore; pools stay as tag
filters (`find_pool`, `count_pool_assets`); Owl's frames are drops
(`owl:frame`, `derived-from` with position); `rating` in the first
vocabulary; areas in 0-1 fractions; links across stores by file hash;
curio's HTTP needs (vocabulary, per-type tag order, multi-value shape,
uses filters/counts/edits with curio's override, 409 on deleting what's in
use, retype, image fields on video). `@mj` (in at 21:07, `.ai`
`826a50e`; it had been reading another mailbox): picture order should be
**preamble · subject · description · staging · theme · style · rules**
(rules last; with staging last every mj `prompt_sent` differs and is
stored whole; order effect on models unmeasured); keep staging's text (the
renderer's wording changes with a camera version), but file it with the
repeating short fields, and never query staging prose (the vectors are the
truth; words get left/right backwards); width/height must be the returned
size (DD measures the file, so it is); `bytes`; cost with an estimated
flag (arcana-ai 0.5.2 now prices OpenAI exactly); seed only meaningful for
`klein`; a refusal is not an asset. Vocabulary: three pixel tiers kept at
once (`pixel-32`, `pixel-16`, `pixel-8`: a narrative degradation stage),
or `pixel` plus a coarseness tag; `night` must not imply dark (projectors
on). Types: whether a picture tiles, a field (DESIGN-types already has
`tileable` as maker-set).

**Thomas's answers (2026-10-13):** the 0.13 list yes; shared descriptions
will grow a good deal, so fix-for-all goes in too; **one shared bucket**,
with another service (maybe curio) clearing unused files; the panel is a
**`plug`** (stagecraft: a scenic insert), plus **`placard`** (intros, title
cards, end credits); an app's own tags as two fields (owner, name), written
`overlore:room-id`; **a use carries no data** (placement is a `placed-on`
link); ground in whatever form gives perspective and scale (written up:
points with a metre's size each, a raised stage its own set); pixel tiers
`pixel-32`/`-16`/`-8`, `pixel` matching all. Thomas talks to `@owl` about
custom styles and whether frames should be one video.
**Built, not committed (2026-10-13):** picture order with rules last;
`cost_basis` (USD); a blank description clears; `description_hash` in JSON
and `list_assets(description_hash:)`; `update_asset(everywhere: true)`;
filters `file_hash:` and `texts:` (`text.<field>=` over HTTP);
`Storage#shared?` (`shared: true`, `DD_SHARED_STORAGE=1`: no deletes,
always writes), `object_keys` / `GET /objects`. 162 specs; dd-serve
type-checks; copies of all five live stores upgrade with 0 differences, 0
FK violations, and a store opened by unreleased 0.13 gets `cost_basis` and
the index. Design docs updated, release notes too. Replies to all four
drafted, held.

**From `@owl`, 2026-10-14 (Thomas's decisions; originals at `.ai`
`c747a84`):** custom art styles wait for a 2.0 (maybe paid): Owl uses the
standard values, a world's art style, theme and rating set apart. Owl asks
for two values, `watercolour` (storybook) and `painted-animation`
(hand-painted animation backgrounds). Frames stay stills (3-5 blended live
with the depth map, scrubbed both ways; the last is the next place's
picture); a video model's clip later would be one video. **The hub**
(Thomas's idea): a DD service on the bus that knows every store, searches
them as one, merges duplicates by hash, filters by rating and art style,
counts use across stores, and clears the shared bucket (deleting a file
only when no store uses it). Apps copy what they choose into their own
store (`copied-from`), so a store going down breaks no other; the bytes
stay one file in the bucket. Owl's library code is a small version and
would be its first user. **Thomas, 2026-10-14: `@curio` builds the hub**
(it's almost set up for it), so it's no DataDungeon release; DD offers each
store's search, use counts, uses (0.14), `GET /objects` and shared storage
(0.13), and perhaps later a copy that records a row for a file already in
the bucket. Thomas also approved `watercolor` (spelled to match `color`)
and `painted-animation`; art style takes no label in keys.

Recipes (`recipe.cr`, `recipes.cr`): texts, recipe_settings, named_texts,
recipes (a row per step), recipe_fields, recipe_legacy; `store(recipe:)`,
`recipe`, `set_recipe`, `with_text`, `named_texts`;
`has_recipe`, `GET /assets/:id/recipe`; description as a text reference;
`update_asset(permanent:)`; `pool_key` aliases gone. After Thomas's "be very
careful with DELETE": `set_recipe` keeps an existing recipe and the old
record unless told, `prune_texts` removed, `description_id` a foreign key,
the column drops verified first (principles.md). Changed from the plan:
DD keeps old `generation` values whole (each app converts its own with
`set_recipe`), since it can't read their formats. 155 specs; all five apps
type-check; copies of all five stores upgrade with every description and
record intact (Overlore 1,165 assets, 900 descriptions -> 859 texts, 916
records kept, 26 ms); `get` unchanged (26.7 us). Release notes drafted.

**Plan (Thomas left the order to me, 2026-10-13):** 0.13 recipes (with
the texts table, the description as a text reference,
`update_asset(permanent:)`, 0.12's deprecated `pool_key` names removed);
meanwhile the tag vocabulary with Thomas; 0.14 standard types (each app
then moves its own, one at a time); 0.15 embeddings and semantic search in
`dd-serve`; later areas, dialogue/sequence/document recipes, audio
measuring, 3D. `DESIGN-types.md` (main `a8d1d08`, not pushed) holds the
settled names (drop, scrim, prop, map), the art styles (golden-comic,
silver-comic, modern-comic, dark-manga, fantasy, photorealism, pixel,
3d-cartoon, ascii), lighting vs condition, uses, areas, pruning.

**0.12.1: usage counted in memory (Thomas, 2026-10-13; released `v0.12.1`
at `6feb72a`).** From `@pirateship`'s finding
(performance.md). `touch_asset` counts in memory; every 1,000 uses
(`USAGE_WRITE_AT`) are written in one transaction if the write lock is
free (`busy_timeout` 0 for that try; if busy, again 100 uses later), the
rest at `close` or by `flush_usage`. Thomas chose a cap alone over riding
on DD's own writes or a timer. Lost on a crash: a hint for eviction, not
a record. 143 specs; `synchronous` stays FULL.

**0.12.2 (`v0.12.2` at `616b752`, 2026-10-13):** `@pirateship` found 1,000
too many for a quiet server and wanted counts kept at shutdown. Uses are
written 100 at a time (busy: again 10 later); read-write DBs register
themselves and one `at_exit` writes their uses, which covers Kemal (it
calls `exit` on SIGINT/SIGTERM; checked with a real SIGTERM: 0 uses before,
7 after). Every app runs on Kemal; only Overlore closes its DB itself.
Measured on xfs: a get counting a use averages 40.5 us against 26.7 us
(one ~1.4 ms sync per 100). Lesson: the 0.12.1 figure (22 vs 21 us) was
measured on tmpfs (`/tmp`), where syncs are free; time disk costs on a
real disk (`touch_bench.cr` takes a directory).

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
- **`prefer:` Closed, not built (Thomas, 2026-10-11).** `@mj`'s `version`
  and `quality` are camera facts: Overlore's `generator` already names the
  camera and its version per picture (`mj:camera:flare@1`), and quality is
  `@mj`'s current camera rank, which would go stale copied onto pictures.
  Ranking comes from reactions through `rating` instead (0.12 TODO above).
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
