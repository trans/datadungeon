# Recipes: a shared standard for how assets were made

*Draft 2026-10-12, with Thomas, `@overlore` and `@mj`; updated 2026-10-13. Nothing here is built yet. The types it applies to are in `DESIGN-types.md`.*

## Why

An asset's `generation` record says how it was made. The goal is a record
complete enough to say exactly what was asked: every setting, every word the
model was given, what it cost. Not a way to redraw the same pixels: as of
2026-10-12 only `mj:camera`'s `klein` honours a seed, and even it reproduces
only until its provider changes the model behind an unchanged name (`@mj`). A
dated run of records is the only evidence that a model moved.

Complete records kept whole would be large (1-3 KiB each, 1-3 GiB at a million
pictures), and nearly all of each one repeats in others. Programs find
settings that work and reuse them; a character speaks in one style; a picture
prompt is a preamble, a subject, a description, a theme, a style and rules, of
which mostly the description is new. On Overlore's store (2026-10-12), 916
records came to 29 parameter sets and 32 long texts once per-clip
measurements were taken out.

Reads are rare: `@curio`'s "How it was generated" panel on an asset's page,
`@overlore` by asset id, `@mj` a few times a week by hand, and a drift audit
by camera and date perhaps twice a year.

## A standard, shared by every app

**One recipe shape per kind of media, defined by DataDungeon, the same for
every app** (Thomas and `@overlore`, 2026-10-12). Records from Overlore,
`@mj` and curio then read alike, an asset made by one app can be used and
understood by another, and tools work across apps without adapters. It is not
registered per app or per consumer, as indexes are: the point is that it is
shared. It grows by agreement, in a DataDungeon release, when a need comes up
that several apps share.

- **A picture:** camera and its version, model, size, format, the camera's
  own settings (`klein`'s steps and CFG, `dhero`'s input fidelity), seed;
  the prompt in fields: **preamble · subject · description · staging ·
  theme · style · rules** (`staging`: the camera's words for `view` and
  `light`, `@mj`); and `prompt_sent`, what the provider received. The rules
  come last, where a model takes them as the final word: "nothing else in
  frame" means little if words follow it (`@mj`, 2026-10-13, from its
  practice; whether models mind the order is unmeasured). Staging was last
  only because `@mj`'s `shoot` took one string and added its words at the
  end; once it takes the fields, it puts staging in its place, and its
  `prompt_sent` equals the fields joined, so it isn't stored again. A
  placement instruction ("make the change where the red ring is drawn",
  `@owl`) is a rule (proposed): staging is only the camera's words.
- **Speech:** model, voice, speed, format and the processing settings
  (`playback-rate`, `leveled-to`, …); the **style** (the speaking
  instructions); the **text** spoken.
- **Per asset:** cost in US dollars, and how it was reached (its basis:
  the service's own bill, `reported: runware`; a rate table,
  `priced: arcana-ai 0.5.2`; or `estimated`), since a cost without it can't
  be audited and the same camera's basis changes over time (`@overlore`,
  `@mj`); `generated_at`; seed (only `klein` honours one, so elsewhere
  `@mj` returns none); and references by file hash. A reference is found
  with `list_assets(file_hash:)`; DataDungeon makes no `derived-from` link
  from it, since the file may be in another store or never stored.

Shapes still to add (`@overlore`, 2026-10-13):

- **Text from a chat model** (banter scripts, decrees): model and settings;
  the instructions as a named text (`overlore:banter@1`); the part that
  changes (a decree's quest title; nothing, for a banter script); and the
  output's format.
- **A dialogue** spoken in one take (ElevenLabs's Text to Dialogue): the
  script by reference, a cast (each speaker's voice and settings), and the
  provider's own settings. Overlore would keep each take and cut it into a
  speech clip per line, linked to the take; a cut's recipe is the take by
  hash and the turn's times, so a recut costs nothing.
- **Made in steps:** a layer is a camera edit of its drop, then a matte
  that keeps what the edit changed. The edit isn't stored, so the recipe
  needs both steps. A recipe as a list of steps covers that, and the
  depth map below.
- **Assembled:** a document or a sequence is made of other assets, so its
  recipe is its layout (the parts in order, the exporter's version) or its
  timeline.
- **Not made here:** imported files have no recipe.

What doesn't fit the standard isn't forced into it: an app keeps it in a
table of its own in the same database, keyed by asset id (as Memo's tables
sit beside DataDungeon's). Overlore's list of the neighbours a room picture
was drawn with is one. Something several apps add can join the standard
later.

Measurements of the result are not part of a recipe: a clip's loudness before
levelling, a layer's `kept` (how much an edit changed). They vary per asset,
which is what turned 29 parameter sets into 449. Overlore's two are dropped
(`@overlore` and Thomas, 2026-10-12): `kept` is counted again from the
layer in 0.5 ms (its opaque pixels over the backdrop's size), and the
loudness is in the clip's ID3 tag, with the original recording kept,
retired. A measurement someone does need would be a field of the asset, as
a picture's dominant colour is. `@mj`'s (2026-10-13) are facts about the
file, so they're fields: the size it snapped to, which DataDungeon measures
from the file itself (the size asked for is the recipe's, and the two
can't be told from each other later), and its size in bytes. A refusal
isn't an asset: there's no picture, and the same prompt may pass next
time.

A derived asset made by a deterministic model, such as a depth map from a
picture, is the opposite of a generated one: its recipe (the source's file
hash, the model and its version, the size) makes it again exactly. It's an
asset of its own, linked to its picture (`depth-of`) and found by that link,
stored with `permanent: false` so eviction can drop it when recomputing is
cheaper than keeping it, and with `compression: "original"` (the default),
since converting it to lossy WebP would lose depth. Owl does this today:
Depth Anything V2, about 30 ms a picture on the GPU and under a second on
the CPU, one 8-bit grayscale PNG per picture, kept as an `owl_depth` asset.

## How it's stored

Every wording, named or not, is one row of one table of texts (id, hash,
text), stored once; the rows aren't typed. Around it:

- **Settings:** a parameter set (camera, version, model, size, the camera's
  settings), stored once by hash; a few hundred at most, since programs reuse
  what works.
- **Named texts:** the short prompt fields that repeat (preamble, theme, style,
  rules; speech's style), each named by its owner: a row with **field,
  owner, name, purpose, version** pointing at its text (Thomas,
  2026-10-12: fields, not one string; the purpose 2026-10-14). The owner is the app that made it,
  its consumer name (`DB.new(…, consumer: "overlore")`); only it adds
  wordings under its names. DataDungeon numbers a name's wordings by their
  hash, in the order first seen: the first is version 1, a changed one 2,
  and the old wording again is 1, so nobody bumps a version by hand.
  `overlore:silver-comic@2` is how one is written and shown, and taken apart on
  the way in, as a view is shown as `back-left` and kept as numbers. Names
  are shared: any app uses `overlore:silver-comic` as it is, which is what makes
  its pictures comparable to Overlore's; nobody renames another's (no
  aliases, until a need shows). Searchable like tags: every picture of one
  style, any version, or one version. Versions are for a wording that
  changes over time. **No custom top-level styles** (Thomas, 2026-10-14,
  through `@overlore`): a variant of a style is the same style, so a style
  wording is named for its standard style (DESIGN-types.md), and two
  wordings in use at once differ by **purpose**, what each is for:
  `overlore:silver-comic/figure` and `overlore:silver-comic/place`. Each
  purpose numbers its own versions, so nothing flips back and forth, and
  the picture's style tag stays the standard one. The purpose is optional
  (`owl:narrator` has none). The row is also the label a person sees
  ("Silver Age comic, Overlore's figure wording, v2", the style's label
  from the vocabulary): no second table, and no supersedes link, since
  versions already say which wording came after which. Once the vocabulary
  is in, DD can check that a picture style's name is a standard style.
- **Staging:** no caller names it, but `@mj`'s renderer has a small closed
  set of phrasings (a few bearings by a few heights), so a million
  pictures have a few dozen, each stored once. It's kept, not rebuilt from
  `view` and `light`: the wording changes with a camera's version, and
  rebuilding old records in today's phrasing would make `prompt_sent`'s
  check pass or fail for reasons that aren't the record's. Nobody should
  search its words: the vectors are the truth (within 20° of a view is one
  dot product), and words get a picture's left and right backwards.
- **Descriptions:** the long texts that are mostly new (a room's LOOK text,
  a character's description, a spoken line), unnamed texts in the same
  table. "Subject" and "description" are prompt fields, as "style" is: where an
  asset uses a text, its row says in which field (`(900, subject, 123)`), not
  the text. So a portrait (`(356, description, 123)`) and every panel of that
  character (`(900, subject, 123)`) point at one text, which ties them
  together in the data. A room's LOOK text is shared by its pictures in
  every style, theme and rating.

Each asset with a recipe has one small row for what's its own (its
settings, seed, cost, `generated_at`, references), plus one row for each
prompt field it uses (asset, field, text), whether the text is named or
not. `@overlore` asked which was meant (2026-10-13); this is it. Reading a record back is one query; a drift audit (every
picture from one camera with one parameter set, by `made_at`) is plain SQL.

Prompt fields are joined with one space, an empty one skipped; each is whole
sentences with their own end punctuation (`@overlore` and Thomas,
2026-10-12). `prompt_sent` is checked, not stored: if it equals the fields joined, nothing
more is kept; if not, it's kept whole, so a camera that added words of its
own shows up (`@mj` returns it in every result so this can be checked rather
than trusted).

**The description is the fallback field** (Thomas, through `@overlore`,
2026-10-14). An app fills what fields it can, from the front (preamble,
subject) and from the back (style, rules), and leaves the rest in the
description, in its order. An empty field (say, theme) means the
description covered it, as far as it mattered. Since the description sits
in the middle, the fields joined are exactly the prompt that was sent, so
no prompt is kept whole: one that fills no field is all description. Old
records are split this way as far as each goes.

Size: a few dozen bytes per asset, the distinct settings and named texts
(hundreds), and the descriptions. On a million pictures, about 50 MB besides
the descriptions; descriptions are the one part worth compressing, if they
grow large (a shared zstd dictionary measured 4.7x on single records; see
below).

### Filling it

- `store(…, recipe:)` takes the standard shape, with each prompt field's text
  given whole (named texts with their name). `generation:` is accepted for a
  release and kept as the old free-form record until moved.
- `@mj`'s `shoot` returns its prompt in labelled parts (`prompt_parts`, roles
  matching the fields) beside `prompt_sent`, since only it knows where its
  seams are; a preamble it might add later then arrives labelled.
- Overlore composes every picture prompt from named parts already, so it
  passes the fields and sends the joined string. Its `description` on an
  asset becomes only the part that changes.

## 0.13: the calls

```crystal
recipe = DataDungeon::Recipe.new("picture",
  settings: {"camera" => "mj:camera:flare", "camera-version" => 1, "model" => "flux-dev",
             "size" => "1024x1024", "steps" => 4},             # stored once by hash
  fields: {"preamble" => DataDungeon::Recipe.named("overlore:house", "Draw …"),
           "subject"  => DataDungeon::Recipe.text("A tall elf with red braids."),
           "style"    => DataDungeon::Recipe.named("overlore:silver-comic/figure", "Silver Age comic …")},
  prompt_sent: sent,                  # kept only if it differs from the fields joined
  seed: 1234, cost: 0.04, cost_basis: "reported: runware", generated_at: time,
  references: [portrait.file_hash.not_nil!])
db.store("panel", tags, bytes: png, content_type: "image/png", recipe: recipe)

db.recipe(id)                         # => Recipe?, named texts as handles: "overlore:silver-comic/figure@2"
db.set_recipe(id, recipe)             # give an asset its recipe later (moving old records);
                                      # replace: true to replace one, drop_generation: true
                                      # to let the old record go
db.with_text("style", "overlore:silver-comic")         # asset ids, any purpose or version;
                                                       # "…/figure" for one purpose, "…/figure@2" one version
db.list_assets(texts: {"style" => "overlore:silver-comic"})  # the same, with the other filters
db.list_assets(file_hash: hash)       # the assets holding a recipe's reference
db.update_asset(id, description: "…", everywhere: true)  # for every asset sharing it
```

- **Forms and their fields,** in joining order. A field another form
  doesn't have is refused.
  - `picture`: preamble, subject, description, staging, theme, style, rules.
  - `speech`: style (the speaking instructions), text (what's spoken).
  - `text` (from a chat model): instructions, description (the part that
    changes).
  - A step with no prompt (a matte, a depth map) has settings and
    references only.
- **Steps:** `Recipe.new(…, steps: [edit, matte])` for an asset made in
  steps, each a recipe of its own; a single recipe is one step.
- **Named texts:** written `owner:name`, or `owner:name/purpose`, with
  `@version` when reading one back. The owner is the app (its `consumer:`),
  and only it adds wordings under its names; any app uses them as they
  are. A wording seen before gets its old version; a new one the next
  number for its name and purpose. A search by `owner:name` finds every
  purpose; `/purpose` narrows it to one.
- **The purpose (0.13.1):** a store made by 0.13.0 gets the column by
  rebuilding `named_texts` once, since its unique constraints change: the
  rows are copied with their ids, so recipes still point at them, and the
  copy is checked (row counts, foreign keys) before the old table goes.
  Only Owl's store held a named text then (`owl:narrator`, 11 records).
- **`prompt_sent`:** for a picture, compared with its fields joined by one
  space, empty ones skipped, and kept only if it differs. For speech and
  text it's kept as given, if given. An old record whose parts are lost
  (`@owl`'s whole prompts) is its settings and `prompt_sent`, no fields.
- **The asset's `description`** is a text in the same table (decided
  2026-10-13). `store(…, description:)` and `AssetRecord#description` stay
  as they are; a recipe's `description` field and the asset's description
  are one row when the words are the same. A blank description clears it.
  The JSON carries `description_hash`, the same in every store, and
  `list_assets(description_hash:)` finds every asset sharing one. A typo is
  fixed for all of them with `update_asset(…, everywhere: true)` (`@curio`;
  Overlore's sharing is about to grow, Thomas): a new text, with every
  asset that pointed at the old one pointed at it. The old text stays,
  since a recipe may record it as what a provider was sent.
- **Rows and HTTP:** `AssetRecord#has_recipe?` (JSON `has_recipe`), the
  cheap flag `@curio` asked for; `GET /assets/:id/recipe` returns the
  recipe, steps and handles included; `GET /assets` filters by
  `file_hash`, `description_hash` and
  `text.<field>=owner:name[/purpose][@version]`.
- **Dialogue and assembled recipes** (a cast, a timeline) come when an app
  stores the first one.

## Moving existing records

DataDungeon can't read each app's own `generation` format, so it doesn't
try (changed 2026-10-13, from moving what it can read). The first open by
0.13 moves every `generation` value, as it is, into a table of old records
and drops the column; `AssetRecord#generation` and `store(…, generation:)`
keep working through 0.13, reading and writing that table. Each app then
converts its own records with `set_recipe`, one app at a time, as it
converts its types; the old record stays until the app says it can go
(`drop_generation: true`). Descriptions move into the texts table the same
way. Each column is dropped only after every value reads back the same
from where it moved; otherwise the open fails, leaving the store as it
was. It's one way, as 0.12's keys were. Thomas, 2026-10-13: be very
careful with deleting, so DataDungeon deletes no text and replaces no
recipe unless told to. Before Overlore opens its store with
0.13, it drops or rewrites its start-up migrations that read `generation`
in SQL (`voices_to_mp3`, `level_voices`).

## Considered first: compressed segments

Recipes kept whole, recent ones in a table, older ones rolled up monthly into
compressed segments in storage (2026-10-11). Gzip got 24-29x on whole
records, about what the tables get, but reading one means unpacking its
segment, nothing can be queried, and it needs roll-ups and a segment index.
Measured on 458 of Overlore's records:

| | Ratio | Read one |
|---|---|---|
| each record alone, gzip | 1.2x | direct |
| each alone, zstd with a shared dictionary | 4.7x | direct |
| one segment, gzip / zstd / zstd with dictionary | 24x / 26x / 33x | unpack the segment |

On transfs (Thomas's versioned store, which chunks files and zstd-compresses
each chunk) the database's pages are compressed when stored anyway.

## Open

- **The asset's `description`: decided, a reference into the texts table**
  (Thomas, 2026-10-13), so the asset's own description and its recipe's
  description field are one text. `@overlore` asked for it (2026-10-13):
  otherwise a room's LOOK text is stored once in texts and again on every
  picture of the room, up to 60 times. A clip's words would be the same
  reference, which is why its `transcript` assets can go.
- **Measurements from `@mj`'s side:** answered 2026-10-13 (above).
- **A step that refers to an earlier step's result** (`@owl`, low
  priority): most Owl pictures are made from a copy of the last one changed
  in the player's browser (a crop, the view bent by its depth map), never
  stored, so it has no hash. A reference to an earlier step would record
  it. Nothing breaks without it.
- **Release:** 0.13, on its own; the embeddings registry
  (`DESIGN-embeddings.md`) in 0.15.
