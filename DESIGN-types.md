# Standard asset types

*Draft 2026-10-13, from Thomas and `@overlore`. Nothing here is built yet.*

## Why

Every type in a store today is one app's own word: Overlore's `room` and
`banter_script`, Owl's `owl_scene`, the park store's `front`, Cattacula's
`voice`. Several apps share a store, and the recipe design (`DESIGN-recipes.md`)
exists so an asset made by one app can be used by another. But another app
can't tell what a `room` is, or that Owl's `owl_scene` is the same kind of
thing.

An asset's identity should say what it is, in words every app understands.
How one app uses it is that app's business.

## Three things, kept apart

1. **The type:** what the asset is, from a short list DataDungeon defines
   (`drop`, `scrim`, `speech`, …). A type is a role and the media is the
   form, so a type can span media: a drop can be a still picture or a
   looping video.
2. **Tags:** claims about what the asset shows or is (below). The tag
   `hair-color` = `red`, read and keyed as `red-hair`, says that something
   in the picture has red hair, and nothing more.
3. **Uses:** how an app uses the asset, written `overlore:room`. A use is
   the app's own marker, so it finds its own quickly. It is never part of a
   key (Thomas, 2026-10-13): a room is just a drop, and the facts about it
   are the same whoever uses it.

## The types

Names settled so far (Thomas, 2026-10-13): `drop` for a backdrop, `scrim`
for an overlay, `prop` for an object (a sprite). The names come from stagecraft rather than film, since apps
build rooms and scenes from these assets. Still open: what to call a panel
(`tableau` suggests something more special than an ordinary shot, such as
Overlore's hero shots), and `map`. Not `scene` for a
drop: setting the scene is the whole arrangement, drop, props and scrims
together, not the drop alone.

### Pictures, still or moving

| Type | What it is | See-through |
|---|---|---|
| **drop** | a place, the set things stand in front of | never |
| **panel** *(name open)* | a framed moment, shown as it is | never |
| **scrim** | a frame's whole size, laid over a drop or panel | mostly |
| **prop** | an object, cropped close to its edges, placed by the app | around it |
| **texture** | a material with no subject or edges, filling an area | either |
| **icon** | a small indicator: a button, a rating; mostly SVG, or Lottie when it moves | either |
| **map** *(name open)* | for programs, not people: a depth map, a mask, a matte | n/a |

- **Opacity is part of the type,** so it's checked when stored: a drop or
  a panel with transparent pixels, in any frame, is refused. DataDungeon
  already decodes PNG and WebP to find a picture's content box, so the
  check costs almost nothing.
- **A scrim's link** (`placed-on`) names the one drop or panel it fits.
  Without one, it's generic and goes over any: rain, fog, a vignette.
- **A sprite sheet** is a prop whose grid is data on it. DataDungeon has
  kept that since 0.11.1 (`ImageAnimation`: frame size and columns).
- **A prop that holds something** (a picture frame, a sheet of paper, a
  speech bubble) needs the position of its opening or writing area, as
  data on the prop. **Open:** a table of named areas.
- **Why `map` is open:** a game's map of a place is a picture people read,
  and it would sit oddly under a type named for depth maps and masks.
  Candidates: `map` anyway; `pass`, from compositing, where depth, matte and
  normal images are all passes.

### Sound

| Type | What it is | Its own data |
|---|---|---|
| **speech** | one voice saying something, words or not (a laugh, a grunt) | the speaker; the words, by reference into texts |
| **dialogue** | voices in turns, a conversation | the speakers; the script it performs; each turn's start and end |
| **music** | composed: a bed under a scene, or a cue (a fanfare, a sting) | |
| **ambience** | a place's continuous sound (wind, a crowd, a hum) | |
| **effect** | one event's sound, trimmed close to it; interface sounds too | |
| **recording** | anything captured or mixed, with no clear boundaries | what's measured; a transcript, if one is made |

A dialogue is voices alone, in turns, with known speakers. With music,
effects or crosstalk mixed in, or speakers unknown, it's a recording. A
forest recording trimmed and looped to sit under a scene is a new asset, an
ambience made from it. Cuts link back to their source: a dialogue cut at
its turns gives speech clips.

### Text

| Type | What it is |
|---|---|
| **prose** | continuous writing in one voice: a description, a decree, a story |
| **script** | lines for voices in turns |
| **transcript** | the words of an audio or video asset, written down after it, with speakers and times when known (WebVTT) |
| **log** | a record of what happened, in order (what interactive fiction calls a transcript) |

A clip spoken from a text needs no transcript: its words are its recipe's
text. Prompts aren't assets: they're named texts in the recipe tables.

**Scripts** use Yarn Spinner's line syntax (`@overlore`'s proposal; notes
in Overlore's `docs/SCRIPT-FORMATS.md`): `Veteran: This isn't a stage,
bard. Sit down. #kind:retort`, speaker, text and `#` tags, with optional
`#line:` ids to key recordings, and directions for the voice in Yarn's
markup (`[sighs/]`). There's no registered content type: `text/plain`, or a
`text/x-yarn` of our own.

### Documents and data

| Type | What it is |
|---|---|
| **document** | made to be read: pages laid out, text and pictures (PDF, EPUB), often assembled from other assets |
| **data** | made for programs: structured (JSON, CSV) or binary (a story file, a saved game); its format and version say which program reads it. Also the catch-all |

### 3D

| Type | What it is |
|---|---|
| **set** | a place, to be inside or look into |
| **prop** | an object seen from outside, placed by the app: the same type as a picture's prop |
| **figure** | a character's body, usually rigged |
| **motion** | movement for a skeleton, without geometry |

The form (mesh, Gaussian splats, point cloud, voxels) is a property, since
a `.ply` can hold any of them. glTF 2.0 / GLB is the standard for meshes.
A material's pictures reuse the picture types: its colour image is a
texture, its normal and roughness images maps.

### Across media

- **sequence:** parts arranged in time, sound or video (shots cut
  together, a banter scene's clips put together into one file). Its recipe
  is its timeline; OpenTimelineIO is the open standard for that.
- **recording**, as above, covers captured video too.
- **font:** one type.

Video otherwise does a picture's jobs, moving, so the picture types cover
it: a looping fire is a drop, rain a scrim, a flickering torch a prop.

### Properties and measurements

- **Set by the maker, as intent:** tileable (none, horizontal, vertical,
  both), loopable (none, seamless), template (text with slots; the
  standard names one syntax, Mustache's `{{name}}`), language, and a 3D
  model's form.
- **Measured when stored:** pictures as now. For sound: length, channels
  and sample rate, from the file's headers. Loudness means decoding the
  audio, which is later work. For text: length and words. For 3D and
  video: counts, bounds, frame rate, whether there's sound or
  transparency, later.
- **The media from the content,** with the content type as the first guess.
  An app's stated media that the content contradicts is refused, not
  corrected. **Anything that moves is `video`** (Thomas, 2026-10-13), an
  animated WebP, GIF or APNG included, so a still drop and a moving one are
  told apart by `media` whatever the file format. The content type
  (`image/webp`) still says how to show it.

## Tags are claims

Thomas, 2026-10-13: a tag says what the asset shows. `hair-color` =
`red` means that something in the picture has red hair. Who or what it is isn't
modelled: no characters to define, maintain and link, and no deciding what
counts as one (a refrigerator called Fred included). The app that made the
asset decides its tags, since it knows what it made, but in shared words.

A tag is a name and a value, kept as a row of the tags table
(`asset_tags`: asset, name, value), which holds every tag of every asset.
Tag filters, `@curio`'s included, read that table; keys are indexes over
it, for fast lookup. In a key, and wherever people read it, a tag is
written as one term with its label: `hair-color` = `red` is `red-hair`
(`a8b300-hair`, for a colour given in hex). Labels exist since 0.5, set in
a type's registration.

Three things follow.

1. **A tag can hold several values.** A panel with a red-haired and a
   black-haired figure says both. Today a name holds one value per asset.
   A type can declare a tag a set (`sets:`), but a set is stored as one
   row with its values joined (`black,red`), so a filter for `red` misses
   it (filters compare whole values), and a key matches only the same set.
   Under this reading, every tag can hold several values, each its own
   row, so a filter for red finds the picture with red and black.
2. **The shared standard is the vocabulary.** `hair-color` means the same
   on a portrait, a panel or a prop, whichever app wrote it. What's shared
   is each tag's name, its label (`hair`, so the term reads `red-hair`), and
   how its values are written (`red`, not "Red" or "ginger"). The rest of
   what a type's registration says about a tag today belongs to the tag
   too: a set, a scale, a colour, a cycle. It grows by agreement, as the
   recipe shapes do.
3. **Keys are the apps', not the type's** (Thomas, 2026-10-13). There's no
   one key per type. An app registers indexes (0.11) for the searches it
   makes often, over the shared tags; an index is only a faster path to
   facts every app can see, and anything else is a tag filter. **Open:**
   0.12's type's own index does more than lookups today, so its other jobs
   need homes: `get(type, tags)` (a tag search, which the planner already
   does), `prune`'s keep-last per key (per an app's index), and best
   match's traits (per an index, or chosen per search).

**Where it's kept** (Thomas, 2026-10-13, to discuss further): a table in
the store, each tag with a short description of what it means, seeded with
the agreed tags. **Open:** the first vocabulary (Overlore's `art-style`,
Owl's `style` and the park store's `look` look like one tag), and how a
tag is added.

**Types are agreed, not added by apps** (Thomas, 2026-10-13): the list is
DataDungeon's and changes in a release, by agreement.

## Uses

A use is written `consumer:name`: `overlore:room`, `overlore:door-view`,
`owl:scene`. Several apps can each mark the same asset, and one app can
mark one asset with two uses.

- **Never in a key.** Overlore finds its rooms by the drop's tags, with its
  use as a filter. The search planner already starts from a tag when it's
  the narrowest way in.
- **A table of their own** (asset, consumer, name), kept apart from tags so
  a use can't collide with a tag of the same name, and counted as tags are
  so the planner can start from it (Thomas, 2026-10-13).
- **They replace the `used-by` links** the park store gives its props
  (0.9), which say who uses an asset but not how.

## Areas

A prop that holds something has an opening or a writing area; a drop has a
floor, where things can stand. An asset can have several. **Decided
(Thomas, 2026-10-13), built when an app first needs it:** a table of named
areas (asset, name, rectangle, and for a video an optional frame range):
`opening`, `writing`, `floor`.

## Pruning and eviction in a shared store

Two operations exist today, and no app calls either (checked 2026-10-13).
`prune` deletes retired assets (takes replaced through `supersedes:`, or
retired by hand), keeping each key's last few if asked; it retires
nothing. Eviction, for lack of use, is `eviction_candidates`: the least
recently used assets not marked permanent, for the app to delete. A third,
keeping the best few of a pool of interchangeable pictures, doesn't exist.

A pool is one app's view, and so is a lack of use: pictures Overlore can
spare may include the one Owl depends on. So no app deletes for everyone
(Thomas, 2026-10-13). An app drops its own use; DataDungeon deletes an
asset only when no app uses it and it's retired, or unused and evictable,
as a stored file is deleted only when no asset refers to it.

## Moving existing stores

Each app moves its own assets, one app at a time (Thomas, 2026-10-13):
each of its types becomes a standard type and a use, with its tags kept
and renamed to the shared vocabulary where they differ. Overlore has
worked out its own already (its 15 types; its 116 `transcript` assets go,
since a clip's words are its recipe's text). DataDungeon provides the
calls; the one-way part, as 0.12's keys were, is the schema.
`register_type` goes: types are DataDungeon's, and tags are defined in the
vocabulary. Apps keep `register_index` for their own fast lookups (Thomas,
2026-10-13).

## Open, collected

- Names: the panel, `map`.
- New homes for what the type's own index does today: `get` and best
  match's traits. Prune follows uses (above).
- The first shared vocabulary, its descriptions, and how a tag is added.
- Release: with the recipes, as 0.13.
