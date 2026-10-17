# Recipes: a shared standard for how assets were made

*Draft 2026-10-12, with Thomas, `@overlore` and `@mj`; built in 0.13, and in 0.14 a recipe keeps the prompt as sent with the wordings in it (2026-10-16). The types it applies to are in `DESIGN-types.md`.*

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
prompt is rules, a framing, a style, a theme, a subject, a description and
directives, of which mostly the description is new. On Overlore's store (2026-10-12), 916
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
  the **prompt**, exactly as the provider received it; and the **wordings**
  in it, the named words it reused (its style, its rules, a character).
  The prompt is the app's: DataDungeon recommends its parts and their
  order, **rules · framing · style · flavor · theme · subject · description
  · staging · light · directives** (`@mj` with Thomas, 2026-10-14, from how
  Overlore makes pictures during play; mj's `notes/picture-prompt-design-v1.md`),
  and a prompt starts there and may depart from it (`@overlore`, 2026-10-16:
  the ideas stay, the fields don't). Four groups, each from one source:
  - **the spec**, set by code from the kind of picture: the **rules**, the
    fixed ones every picture obeys (the rating's words, DataDungeon's
    `dd:pg`, saying what's suitable; no signature),
    first; and the **framing**, how much is in frame and its shape ("a wide
    landscape", "full body, head to toe"). A fixed rule mustn't contradict
    a description (Thomas): some pictures need words in them, so "no text
    unless the description asks for it".
  - **the look**, from the game's state: the **style**, DataDungeon's words
    for the art style, from the vocabulary; the **flavor**, the app's own
    words for it; and the **theme**, mood included.
  - **the object**, from the DM: **subject**, **description** and
    **staging** (where each figure is, which way it faces, and the view, in
    words; a view vector is only measured afterwards).
  - **the relation**, from pictures that exist: the **light**, the standing
    light inherited from the place, and the **directives** (Thomas's name),
    this picture's own: its kind's rules ("each named thing drawn once" for
    a room) and what an edit or a shot from a reference changes and keeps.
    They come last, where the end holds what the picture is for; Overlore
    found "each thing once" held better last than in the middle. A
    placement instruction ("make the change where the red ring is drawn",
    `@owl`) is a directive.

  The kind of picture (a portrait, a room, a panel) is no setting of its
  own: the asset's type and the app's tag say it, and the prompt holds the
  words it produced. 0.13's order, preamble · subject · description ·
  staging · theme · style · rules, was `@mj`'s habit of ending with "nothing
  else in frame", not measured; its slot-order test came back null on
  `klein`. Conflicts are settled in code before the prompt, not by order:
  on `klein` and `flare` a positive mention beats a "don't" either way
  round (mj's cow tests, 2026-10-14).
- **Speech:** model, voice, speed, format and the processing settings
  (`playback-rate`, `leveled-to`, …); the **instructions**, how it's
  spoken (a voice's style, often a wording such as `owl:narrator`); and the
  **prompt**, the words spoken.
- **Per asset:** cost in US dollars, and how it was reached (its basis:
  the service's own bill, `reported: runware`; a rate table,
  `priced: arcana-ai 0.5.2`; or `estimated`), since a cost without it can't
  be audited and the same camera's basis changes over time (`@overlore`,
  `@mj`); `generated_at`; seed (only `klein` honours one, so elsewhere
  `@mj` returns none); and references by file hash. A reference is found
  with `list_assets(file_hash:)`; DataDungeon makes no `derived-from` link
  from it, since the file may be in another store or never stored.

Shapes still to add (`@overlore`, 2026-10-13):

- **Text from a chat model** (banter scripts, decrees; built in 0.13):
  model and settings; the instructions, often a wording
  (`overlore:banter`); the prompt, the part that changes (a decree's quest
  title); and the output's format.
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

Every text, a prompt, a wording, an asset's description, is one row of one
table of texts (id, hash, text), stored once; the rows aren't typed. Around
it:

- **Settings:** a parameter set (camera, version, model, size, the camera's
  settings), stored once by hash; a few hundred at most, since programs reuse
  what works.
- **What was sent:** each step's prompt and instructions, references into
  texts. Each prompt is a text of its own, since almost every one is new:
  on Overlore's store (2026-10-16), keeping the prompts whole took 295 KB
  where its 0.13 fields and their indexes took 426 KB, the hashes and
  their index costing more than the words they saved.
- **Wordings:** the words an app reuses (rules, framing, flavor, a
  character; a voice's style), each named by its owner: a row with **kind,
  owner, name, purpose, version** pointing at its text (Thomas,
  2026-10-12: fields, not one string; the purpose 2026-10-14). The owner is
  the app that made it, its consumer name (`DB.new(…, consumer:
  "overlore")`), or `dd` for DataDungeon's own; only it adds wordings under
  its names. A recipe lists the wordings in its prompt and instructions, in
  `recipe_wordings`, and the store refuses one whose words aren't there
  word for word: that is the guarantee a picture got its style, rating and
  character, without DataDungeon parsing prompts (Thomas, 2026-10-16:
  consistency comes from every picture taking the same words from one
  registry). Names are shared: any app uses `overlore:silver-comic` as it
  is, which is what makes its pictures comparable to Overlore's; nobody
  renames another's. Searchable like tags: every picture of one style, any
  version, or one version. **No custom top-level styles** (Thomas,
  2026-10-14, through `@overlore`): a variant of a style is the same style,
  so an app's style wording is named for its standard style
  (DESIGN-types.md), and two wordings in use at once differ by **purpose**,
  what each is for: `overlore:silver-comic/figure` and
  `overlore:silver-comic/place`. The purpose is optional (`owl:narrator`
  has none).
- **A version is the words' hash** (`@mj` with Thomas, 2026-10-16): the
  first 10 hex characters of their SHA-256 (`texts.hash`), so
  `overlore:silver-comic@3f9a2c71b0` means the same words in every store,
  and nobody hands out numbers. Each store had numbered a name's wordings
  in the order it saw them, so `@2` could be different words in two stores,
  and a record moved between them would point at the wrong ones. The words
  are hashed exactly, so a stray space is a new version, as it is to the
  model. Two versions of one name sharing those 40 bits (about 1 in 200
  million for a wording with 100 versions) are refused, not confused. The
  row id says which came first. A wording is never changed or deleted:
  triggers refuse it, in the sqlite3 shell too, so a rename is a new name
  and the old one stays, since prompts that name it are stored.
- **The style and its flavor** (0.14; Thomas, 2026-10-14): the standard
  is always in the prompt, not left to each app's wording to repeat.
  Each art style in the vocabulary has DataDungeon's words for it, a
  wording of DataDungeon's own (`dd:silver-comic`, "Silver Age comic."),
  which a picture's prompt takes as its `style` (`db.style_text("silver-comic")`);
  the app's wording is a `flavor`, which only narrows the style or serves
  its purpose, never asks for another. The words stay short, adding a
  style's key differentiators only where a model may not know it. An
  improved wording is the style's next version; earlier pictures keep the
  words they were given, and a change only refines (Thomas, 2026-10-16), so
  apps aren't told. A picture's `style` wordings must be DataDungeon's, and
  a flavor needs a style and is named for it, checked before anything is
  written. (Thomas turned down checking that each app's wording starts
  with the standard, word for word: brittle, and it repeats the base.)
- **Staging:** the DM's words since 0.14. Before, it was `@mj`'s camera's
  words for `view` and `light`. Nobody should search its words: the
  vectors are the truth (within 20° of a view is one dot product), and
  words get a picture's left and right backwards. DataDungeon owns turning
  its vectors into words (`ViewWords`, from mj's camera; Thomas,
  2026-10-14), for an app that has a measured light or view to say; the
  words go into the prompt as the app's own, and the vectors stay on the
  asset.
- **Descriptions:** an asset's description is a text in the same table,
  shared by every asset with the same words (a room's LOOK text by its
  pictures in every style, theme and rating).

Each asset with a recipe has one small row per step for what's its own (its
settings, prompt, instructions, seed, cost, `generated_at`, references),
plus one row for each wording it used. Reading a record back is one query;
a drift audit (every picture from one camera with one parameter set, by
`made_at`) is plain SQL.

### Filling it

- `store(…, recipe:)` takes the standard shape: the prompt and
  instructions as sent, and each wording with its kind, name and words.
  `generation:` is accepted for a release and kept as the old free-form
  record until moved.
- An app composes a prompt from its parts and its wordings, joins them as
  it likes, sends it, and stores what it sent. `@mj`'s `shoot` returns
  `prompt_sent`, so a camera that added words of its own shows in the
  prompt kept.

## The calls

```crystal
style = db.style_text("silver-comic")    # DataDungeon's words for the style: dd:silver-comic@<version>
flavor = DataDungeon::Recipe.wording("flavor", "overlore:silver-comic/figure", "Bold inks …")
recipe = DataDungeon::Recipe.new("picture",
  settings: {"camera" => "mj:camera:flare", "camera-version" => 1, "model" => "flux-dev",
             "size" => "1024x1024", "steps" => 4},             # stored once by hash
  prompt: sent,                       # exactly what the provider received
  wordings: [style, flavor],          # each word for word in the prompt
  seed: 1234, cost: 0.04, cost_basis: "reported: runware", generated_at: time,
  references: [portrait.file_hash.not_nil!])
db.store("panel", tags, bytes: png, content_type: "image/png", recipe: recipe)

db.recipe(id)                         # => Recipe?, wordings named "overlore:silver-comic/figure@3f9a2c71b0"
db.set_recipe(id, recipe)             # give an asset its recipe later (moving old records);
                                      # replace: true to replace one, drop_generation: true
                                      # to let the old record go
db.with_text("flavor", "overlore:silver-comic")        # asset ids, any purpose or version;
                                                       # "…/figure" for one purpose, "…/figure@3f9a2c71b0" one version
db.with_text("style", "dd:silver-comic")               # every picture given the style's words
db.list_assets(texts: {"flavor" => "overlore:silver-comic"})  # the same, with the other filters
db.named_texts("flavor", "overlore")  # an owner's wordings of a kind: {name, version, text}
db.vocabulary                         # the shared tags and values (GET /vocabulary)
db.list_assets(file_hash: hash)       # the assets holding a recipe's reference
db.update_asset(id, description: "…", everywhere: true)  # for every asset sharing it
```

- **Forms:** `picture` (a prompt), `speech` (instructions, and the prompt
  spoken), `text` from a chat model (instructions, and the prompt, the part
  that changes). A step with no prompt (a matte, a depth map) has the form
  `""`, settings and references only.
- **Steps:** `Recipe.in_steps([edit, matte])` for an asset made in steps,
  each a recipe of its own; a single recipe is one step.
- **Wordings:** `Recipe.wording(kind, name, words)`, the name `owner:name`
  or `owner:name/purpose`, with `@version` when reading one back (a version
  given going in must be the words'). The kind is free: `style`, `flavor`,
  `rating`, `framing`, `character`, `theme`, … A search by `owner:name`
  finds every purpose; `/purpose` narrows it to one.
- **The asset's `description`** is a text in the same table (decided
  2026-10-13). `store(…, description:)` and `AssetRecord#description` stay
  as they are. A blank description clears it. The JSON carries
  `description_hash`, the same in every store, and
  `list_assets(description_hash:)` finds every asset sharing one. A typo is
  fixed for all of them with `update_asset(…, everywhere: true)` (`@curio`;
  Overlore's sharing is about to grow, Thomas): a new text, with every
  asset that pointed at the old one pointed at it. The old text stays,
  since a recipe may hold it as what a provider was sent.
- **Rows and HTTP:** `AssetRecord#has_recipe?` (JSON `has_recipe`), the
  cheap flag `@curio` asked for; `GET /assets/:id/recipe` returns the
  recipe, `{form, settings, prompt, instructions, wordings: [{kind, name,
  text}], …}`, steps included; `GET /assets` filters by `file_hash`,
  `description_hash` and `text.<kind>=owner:name[/purpose][@version]`.
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

The first open by 0.14 turns 0.13's prompt fields into what was sent
(2026-10-16): a step's `prompt_sent` where it kept one, or else a
picture's fields joined in 0.13's order with one space, empty ones skipped,
as 0.13's `joined` said was sent; speech's text, with its style as the
instructions; a chat text's description, with its instructions. Each named
field becomes one of its wordings, the field its kind, the version its
words' hash; `named_texts` is rebuilt once for that, its rows copied with
their ids and compared before the old table goes. Every step is compared
with its fields before a column goes, and the fields stay, in
`recipe_fields`, no longer written, until the apps have moved. A 0.13.0
store, whose named texts had no purpose, converts the same way.

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

## Considered next: prompt fields, then templates

0.13 stored a prompt as its fields, each a reference into texts, so the
words a picture shared with others were kept once; 0.14 first kept a field
order per record so changing the order wouldn't rewrite what old records
said was sent. Then (`@mj` with Thomas, 2026-10-16) a prompt as one
template, the app's words with tags for registered wordings, pinned when
expanded. Both were dropped the same day for the prompt as sent with the
wordings in it, after an independent review: prompts don't split into
fields (the Bard pictures were one running sentence), nothing reads the
fields back, the byte case failed on Overlore's own store (above), and a
template language inside a storage library is the app's business. What the
fields were for stays: the recommended parts and order, and one registry of
wordings.

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
- **Release:** 0.13, on its own; the prompt as sent, the wordings, the
  style and its flavor in 0.14 with the vocabulary and the ratings' words
  (Thomas, 2026-10-15 to 2026-10-17); the embeddings registry (`DESIGN-embeddings.md`) in
  0.16.
- **Compression** of stored prompts, if size comes to matter: zlib took
  Overlore's prompts from 659 to 399 bytes on average, and it can come
  later without changing anything apps write.
