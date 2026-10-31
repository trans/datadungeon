# Formats and roles

*Draft 2026-10-30, with Thomas. Not built. An asset's type is its file
format; what DataDungeon has called a type is a role, which any asset may
have (Thomas, 2026-10-30). Replaces the type list in DESIGN-types, whose
reasons for roles stand.*

## Why

`@cattacula` asked whether Kitty Marionette's poses are a `motion`. A
`motion` turned out to be a BVH, an FBX animation or a glTF one: files
whose format already says what they are. Thomas, 2026-10-30: "the type is
'bvh' or 'fbx' etc. and if there's a few that don't have a good standard
yet, we create our own *format*. that's all there is to it really."

A format is a standard already shared, better than any category we
invent. Some of DataDungeon's 26 types name what a format would say
(`motion`, `font`, `document`, `set`, `figure`). The others name what a
format can't: a PNG can be a place, a cutout or a depth map, and an MP3
a voice, music or an effect. Those are roles.
Thomas: "what we have making a type, is really just a role of a format."

## The format

Every asset has one, and today it's recorded: `assets.content_type`. It's
treated as an afterthought:

- `ext_for` gives 16 extensions; anything else is stored as `.bin`.
- Details are kept per media (`image_meta`, `audio_meta`, `video_meta`),
  not per format, and only pictures are measured (`ImageProbe`). An
  audio's duration or a video's frame rate is whatever the app said.

The proposal: the content type is the asset's type. DataDungeon keeps a
table of the formats it knows, each with its content type, its extension
and its probe. Content types are the standard names: `image/png`,
`audio/mpeg`, `model/gltf-binary`, `font/woff2`, `text/vtt`. A few
formats have no registered type (BVH, FBX, SRT, Yarn) and take the one
in common use (`application/x-subrip`, `text/x-yarn`); `x-` names are
only for others' formats, ours are vendor types (below).

**A format DataDungeon doesn't know** is stored with its file's own
extension (Thomas, 2026-10-30), unmeasured. Today every key's extension
comes from the content type (`object_key`), so an unknown one is `.bin`.

- **The format decides when it's known,** never the file's name: the same
  bytes as `.jpeg` and `.jpg`, or `.yml` and `.yaml`, would be two objects
  for one hash.
- **One part,** lowercased, letters and digits. A compressed tar takes its
  usual short form (`.tar.gz` is `.tgz`; `.tbz2`, `.txz`, `.tzst`), since
  its content type is only the compression's (`application/gzip`); any
  other compound ending keeps its last part. The Worker serves
  `hh/<sha256>.<ext>` with one extension, and keeping snapshots off it
  may rest on that (DESIGN-backups).
- **`.bin` only when there's no name:** `source_path:` gives one, and
  `POST /assets` takes the upload's. Bytes passed to `store` have none; a
  `filename:` for them waits for an app that stores bytes of a format
  DataDungeon doesn't know (Thomas, 2026-10-31).
- **No flag for unknown:** an asset is unmeasured when its format's probe
  hasn't written a record, which stays true until DataDungeon learns the
  format and the probe runs.

**Formats of our own,** where no standard exists, are named as the
standard says (RFC 6838): a vendor type with its syntax as a suffix, such
as `application/vnd.cattacula.marionette+json`. Each has a written spec
and a version. A JSON file says nothing on its own: `application/json` is
a container, so an asset that a program reads has a format of its own.

**A dialect is a format of its own** when it changes what a file means.
Yarn lines with emoji as cues for the body aren't standard Yarn (Thomas,
2026-10-31): such a file still parses as Yarn, since an emoji is only
characters in a line, but a tool that knows only Yarn would send the
emoji to the voice. So it gets its own name, `eyarn` (Thomas,
2026-10-31), and spec, which is DataDungeon's (Thomas, 2026-10-31):
`.eyarn`, `text/vnd.datadungeon.eyarn`.

`media` (image, audio, video, text, data, model, font) follows from the
format, as a coarse grouping.

## The role

Optional, on any asset, "even if it doesn't have a use yet" (Thomas,
2026-10-30). It says what the asset is for, which the bytes can't: a
`drop` is a place things stand in front of, a `plug` a moment shown as it
is, a `pass` a picture for programs.

- **Lookups go by role.** What `register_type` registers today (traits,
  indexes, labels, facets, `embed`) belongs to a role. Keys stay as they
  are (`drop.golden.pg.…`): today's type names become role names.
- **An asset with no role has no key.** It's found by id, hash, tags,
  links and search.
- **The roles for pictures, sound and text stay:** `drop`, `plug`,
  `placard`, `scrim`, `prop`, `texture`, `icon`, `pass`; `speech`,
  `dialogue`, `music`, `ambience`, `effect`, `recording`; `prose`,
  `script`\*, `transcript`, `log`.

  \* `script` names what Yarn says (below), so it may go; it stays for now
  (Thomas, 2026-10-31).

**Pictures,** Thomas: it mostly comes down to whether a picture is a
backdrop or an object with transparency around it. Both are measured
already: `transparent` and the content box. A cutout is transparent with
its content box inside the frame. What isn't in the pixels is the use:
a drop and a plug are both opaque and full, and a scrim is an overlay the
size of the frame. So measured fields describe the picture, and the role
says how it's used.

## Details: measured by the format, set by the role

Today's tables mix the two (the same line DESIGN-export draws):

- **Measured** belongs to the format. A probe reads it from the bytes, so
  it can always be read again, and a better probe re-reads it.
- **Set** belongs to the role, or the app: presentation, compression
  targets, view, light, anchors, world size, a view's name, a sprite
  sheet's grid, keyframes.

What a probe would read, by format:

| Formats | Measured |
|---|---|
| PNG, WebP, JPEG, GIF, TIFF | width, height, transparent, content box, dominant color; frames, duration and loops when animated (measured today) |
| SVG | its view box |
| MP3, Ogg, Opus, WAV | duration, sample rate, channels, bitrate (set by the app today) |
| WebM, MP4 | width, height, duration, frame rate, whether it has sound (set by the app today) |
| glTF, GLB | meshes, bounds, materials; skins and their joints; animations, their names and lengths |
| BVH | the joints, the frame count, the frame time |
| FBX | as glTF, but closed: reading it needs Autodesk's SDK or a converter |
| TTF, OTF, WOFF2 | family, style, weight, glyph count |
| VTT, SRT | cues, duration, language |
| PDF, EPUB | pages, title, language |
| a format of our own | its spec says |

Some roles a probe could almost tell: a glTF with animations and no
meshes is a motion, one with a skin is a figure. That's a hint for an
app, not a role DataDungeon assigns.

**The general shape,** proposed: measured details as one record per asset,
written only by the format's probe and stamped with the probe's version,
with the fields each format's probe documents. Set details stay as named
columns. Listings filter on 18 picture fields (`RANGE_FIELDS`), measured
ones (width, height, the content box) and set ones (view, light, anchor,
world size), so measured fields must stay filterable: rows per field, or
a JSON column with indexed expressions. Which is open.

## What changes for the apps

Little, for what they store today:

- a store's `asset_type` becomes its `role`, unchanged; keys don't move;
- `register_type` becomes registering a role, under a new name with the
  old one kept a while;
- the format is the content type each asset already has.

What's new: assets with no role, formats DataDungeon measures, and formats
of an app's own.

## Stages

Each stage is a release of its own, checked on copies of every live store,
and each needs only the open questions listed under it settled.

**1. Formats and extensions** (small; no schema change, no key moves)
- A table of formats replaces `ext_for` and `DB.media_of`: content type,
  extension, media, probe. Everything known today keeps its extension.
- Formats coming soon get theirs before any probe: glTF/GLB, BVH, TTF,
  OTF, WOFF2, VTT, SRT, EPUB; Yarn (`text/x-yarn`, `.yarn`) and eyarn
  (`text/vnd.datadungeon.eyarn`, `.eyarn`); a vendor `+json` type is
  `.json`.
- An unknown format keeps the extension of its `source_path:` or its
  upload's name, in one part (`.tgz` for compressed tars); `.bin` without
  a name, as for bytes.
- Checked: every store's `object_keys` unchanged.

**2. The role, optional** (the main stage; a schema change, so a minor
release the apps take when they move their pin)
- `assets.asset_type` is `NOT NULL`: the table is rebuilt on open, as the
  wordings' was (every row compared, foreign keys checked after), and the
  column becomes `role`, nullable. First check that no app reads the
  column by name in SQL of its own.
- `store` without a role: no registration, no key; found by id, hash,
  tags, links and search. A role still needs its registration and a
  listed name, as a type does today.
- New names beside the old: `role:` on `store`, `register_role` with
  `register_type` kept, `role` in JSON and `?role=` with `?type=` kept.
  Nothing is forced on the apps.
- Keys, listings, match files, `embed`, `/vocabulary` and the export
  design handle an asset with no role.
- To settle first: whether an asset with no role is embedded for search
  (`embed` is a role's today).

**3. Measured details beyond pictures** (one format at a time)
- 3a, sound and video: probes fill `audio_meta` and `video_meta`'s
  measured fields (duration, sample rate, channels, bitrate; size, frame
  rate, sound), replacing what the app said, as pictures' are.
  `measure_images` becomes `measure` and backfills a store.
- 3b, formats with no table yet (glTF, BVH, fonts, subtitles, PDF): the
  general record, stamped with its probe's version.
- To settle first: rows or a JSON column (3b); probes written in Crystal,
  or a tool like `ffprobe` (3a; MP4 and WebM are the hard ones).

**4. Formats of our own,** when an app wants one (Cattacula's poses
first). Stages 1 and 2 store them already; a probe only if one helps.
- To settle first: where specs live, and the vendor names.

**5. The old names go, and the list is trimmed** (a later minor release,
once every app has moved)
- `asset_type:`, `register_type` and `?type=` removed.
- Roles that only name a format go, after a read-only check that no store
  holds one (Overlore's comics are `document`).
- To settle first: the role list.

## Cattacula's bits and poses

`@cattacula` (3d9ab3d3, 2026-10-31) keeps all but its voices in a
database of its own, from before DataDungeon's types.

- **Mr Monocles' bits** are Yarn assets, not scripts (Thomas, 2026-10-31):
  1 to 4 lines in one voice, a line's timing as a `#` tag, the bit's type
  and style as tags on the asset. With emoji cues they're the Yarn dialect
  above. Each beat's `speech` links to its bit.
- **Kitty Marionette's poses** are a format of Cattacula's own: a versioned
  JSON spec of a pose (its length, and the path each string follows: head,
  tail, four paws, mouth), such as
  `application/vnd.cattacula.marionette+json`. Each revision by the
  Director is a new asset, `derived-from` the one before.
- Either needs a role only if Cattacula looks them up by one.

## Open

- **The role list:** only DataDungeon's names, as types are since 0.16, or
  any word, with a shared list for roles apps share. Which of today's 26
  stay as roles (`motion`, `font`, `document`, `data`, `set`, `figure`,
  `automaton`, `sequence` name what a format says; so does `script`, which
  is Yarn, kept for now).
- **`eyarn`'s spec,** to write in DataDungeon's repo: an
  emoji is a cue at its point in a line; followed by "…" it holds the words
  and the voice until the action ends; a prop's emoji also sets the prop;
  the voice is sent the line without them; the map from emoji to action is
  the app's, as voice tags are.
- **Search:** whether an asset with no role is embedded (stage 2).
- **Measured details:** rows per field or a JSON column.
- **Formats of our own:** where their specs live (DataDungeon's repo, or
  the app's), and the vendor name (`vnd.datadungeon.…` or the app's).
- **FBX:** probe it, convert it to glTF on the way in, or store it
  unmeasured.
- **Probes:** in DataDungeon (as `ImageProbe` is), or outside it (a
  library per format, like `data_dungeon/tiff`).
