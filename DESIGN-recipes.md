# Recipes: a shared standard for how assets were made

*Draft 2026-10-12, with Thomas, `@overlore` and `@mj`. Nothing here is built yet.*

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
  the prompt in fields: **preamble · subject · description · theme · style ·
  rules · staging** (`staging`: the camera's words for `view` and `light`,
  `@mj`); and `prompt_sent`, what the provider received.
- **Speech:** model, voice, speed, format and the processing settings
  (`playback-rate`, `leveled-to`, …); the **style** (the speaking
  instructions); the **text** spoken.
- **Per asset:** cost, `generated_at`, seed, and references by file hash
  (also kept as `derived-from` links, which can be queried).

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
a picture's dominant colour is.

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
  owner, name, version** pointing at its text (Thomas,
  2026-10-12: fields, not one string). The owner is the app that made it,
  its consumer name (`DB.new(…, consumer: "overlore")`); only it adds
  wordings under its names. DataDungeon numbers a name's wordings by their
  hash, in the order first seen: the first is version 1, a changed one 2,
  and the old wording again is 1, so nobody bumps a version by hand.
  `overlore:silver@2` is how one is written and shown, and taken apart on
  the way in, as a view is shown as `back-left` and kept as numbers. Names
  are shared: any app uses `overlore:silver` as it is, which is what makes
  its pictures comparable to Overlore's; nobody renames another's (no
  aliases, until a need shows). Searchable like tags: every picture of one
  style, any version, or one version. Versions are for a wording that
  changes over time; two wordings in use at once get two names
  (`overlore:silver` for places, `overlore:silver-figure` for figures), or
  their versions would flip back and forth.
- **Descriptions:** the long texts that are mostly new (a room's LOOK text,
  a character's description, a spoken line), unnamed texts in the same
  table. "Subject" and "description" are prompt fields, as "style" is: where an
  asset uses a text, its row says in which field (`(900, subject, 123)`), not
  the text. So a portrait (`(356, description, 123)`) and every panel of that
  character (`(900, subject, 123)`) point at one text, which ties them
  together in the data. A room's LOOK text is shared by its pictures in
  every style, theme and rating.

Each asset with a recipe has one small row: its settings, its named texts and
descriptions by field, and what's its own (seed, cost, `generated_at`,
references). Reading a record back is one query; a drift audit (every
picture from one camera with one parameter set, by `made_at`) is plain SQL.

Prompt fields are joined with one space, an empty one skipped; each is whole
sentences with their own end punctuation (`@overlore` and Thomas,
2026-10-12). `prompt_sent` is checked, not stored: if it equals the fields joined, nothing
more is kept; if not, it's kept whole, so a camera that added words of its
own shows up (`@mj` returns it in every result so this can be checked rather
than trusted).

Size: a few dozen bytes per asset, the distinct settings and named texts
(hundreds), and the descriptions. On a million pictures, about 50 MB besides
the descriptions; descriptions are the one part worth compressing, if they
grow large (a shared zstd dictionary measured 4.7x on single records; see
below).

### Filling it

- `store(…, recipe: {...})` takes the standard shape, with each prompt field's text
  given whole (named texts with their name). `generation:` is accepted for a
  release and kept as the old free-form record until moved.
- `@mj`'s `shoot` returns its prompt in labelled parts (`prompt_parts`, roles
  matching the fields) beside `prompt_sent`, since only it knows where its
  seams are; a preamble it might add later then arrives labelled.
- Overlore composes every picture prompt from named parts already, so it
  passes the fields and sends the joined string. Its `description` on an
  asset becomes only the part that changes.

## Moving existing records

The first open by the release that builds this moves each `generation` value
it can read into the standard shape, keeps what it can't as the asset's
legacy record, and drops the column (one way, as 0.12's keys were). Before
that, `@overlore` drops or rewrites its start-up migrations that read
`generation` in SQL (`voices_to_mp3`, `level_voices`).

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

- **The asset's `description`:** whether it becomes a reference into the
  texts table, so the asset's own description and its recipe's
  description field are one text.
- **Measurements from `@mj`'s side:** asked 2026-10-12 whether its camera
  returns any that should be kept.
- **Release:** 0.13, beside the embeddings registry
  (`DESIGN-embeddings.md`), or on its own.
