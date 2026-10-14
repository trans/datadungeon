# Standard asset types

*Draft 2026-10-13, from Thomas and `@overlore`; reviewed the same day by
`@curio`, `@overlore`, `@owl` and `@mj`. Nothing here is built yet.*

## Why

Every type in a store today is one app's own word: Overlore's `room` and
`banter_script`, Owl's `owl_scene`, the park store's `front`, Cattacula's
`voice`. Each app gets a store of its own, and a common store apps copy
from; they copy from each other too (Thomas, 2026-10-13). The recipe design
(`DESIGN-recipes.md`) exists so an asset made by one app can be used by
another. But another app can't tell what a `room` is, or that Owl's
`owl_scene` is the same kind of thing.

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

Names settled (Thomas, 2026-10-13): `drop` for a backdrop, `scrim` for an
overlay, `prop` for an object (a sprite), `plug` for a framed moment shown
as it is (a comic panel, a hero shot; in stagecraft a plug, technically a
scenic insert; `panel`, `shot` and `tableau` were considered), and
`placard` for words shown between scenes. The names come from stagecraft
rather than film, since apps build rooms and scenes from these assets.
`map` stays until a better word comes (Thomas,
2026-10-13; `scan` was considered, but a scanned page is a picture people
read). Not `scene` for a
drop: setting the scene is the whole arrangement, drop, props and scrims
together, not the drop alone.

### Pictures, still or moving

| Type | What it is | See-through |
|---|---|---|
| **drop** | a place, the set things stand in front of | never |
| **plug** | a framed moment, shown as it is: a comic panel, a hero shot | never |
| **placard** | words shown on their own, between scenes: an intro, a title card, end credits | never |
| **scrim** | a frame's whole size, laid over a drop or plug | mostly |
| **prop** | an object, cropped close to its edges, placed by the app | around it |
| **texture** | a material with no subject or edges, filling an area | either |
| **icon** | a small indicator: a button, a rating; mostly SVG, or Lottie when it moves | either |
| **map** | for programs, not people: a depth map, a mask, a matte | n/a |

- **Opacity is part of the type,** so it's checked when stored: a drop, a
  plug or a placard with transparent pixels, in any frame, is refused. It's
  the pixels that are checked, not the format: a PNG with an alpha channel
  that is opaque throughout passes (`@overlore`). DataDungeon already
  decodes PNG and WebP to find a picture's content box, so the check costs
  almost nothing.
- **A placard's words** are its description, so they're searched like any.
- **A scrim's link** (`placed-on`) names the one drop or plug it fits.
  Without one, it's generic and goes over any: rain, fog, a vignette.
- **A sprite sheet** is a prop whose grid is data on it. DataDungeon has
  kept that since 0.11.1 (`ImageAnimation`: frame size and columns).
- **A prop that holds something** (a picture frame, a sheet of paper, a
  speech bubble) needs the position of its opening or writing area: an
  area (below).
- **A map of a place** (a game's world map) is a picture people read, so
  it's a plug or a drop, not a `map`.
- **Image fields stay with moving pictures** (`@curio`): view, light,
  anchor, real size and content box are a picture's, still or moving, so a
  program reads them by the fields, not the media.

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
  model's form. Tileable is a field, as a view is (`@mj`): a program
  choosing a background needs it before it draws, and can't find out by
  looking. It's decided by the projection, not the tags: a boardwalk strip
  built to scroll tiles, a view toward a vanishing point never does.
- **Measured when stored:** pictures as now, their size being the file's
  own: the size a provider snapped to, which often isn't the size asked
  for (`@mj`: Nano Banana has no 1024x768), and the asked-for size is the
  recipe's. Every file's size in bytes. For sound: length, channels
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

1. **A tag can hold several values.** A plug with a red-haired and a
   black-haired figure says both. Today a name holds one value per asset.
   A type can declare a tag a set (`sets:`), but a set is stored as one
   row with its values joined (`black,red`), so a filter for `red` misses
   it (filters compare whole values), and a key matches only the same set.
   Under this reading, every tag can hold several values, each its own
   row, so a filter for red finds the picture with red and black.
2. **The shared standard is the vocabulary.** `hair-color` means the same
   on a portrait, a plug or a prop, whichever app wrote it. What's shared
   is each tag's name, its label (`hair`, so the term reads `red-hair`), and
   how its values are written (`red`, not "Red" or "ginger"). The rest of
   what a type's registration says about a tag today belongs to the tag
   too: a set, a scale, a colour, a cycle. It grows by agreement, as the
   recipe shapes do.
3. **Keys are the apps', not the type's** (Thomas, 2026-10-13). There's no
   one key per type. An app registers indexes (0.11) for the searches it
   makes often, over the shared tags; an index is only a faster path to
   facts every app can see, and anything else is a tag filter. `get` and
   best match keep working without a key per type: `get(type, tags)`
   becomes a tag search, which the planner runs from the narrowest start,
   an app's index when one covers the tags; best match compares the tags
   named in an app's index or in the query, each by its kind from the
   vocabulary (a set, a scale, a colour, a cycle).

**Where it's kept** (Thomas, 2026-10-13, to discuss further): a table in
the store, each tag with its label, kind and a one-line description of what
it means, and its values each with one too, seeded with the agreed tags.
**Open:** how a tag is added.

- **Over HTTP** (`@curio`): `GET /vocabulary`, each tag's name, label,
  description, kind and the values in use, for tooltips and the filter
  column; and for each type its usual tags, most telling first, so curio
  can caption a picture `night · red-hair · photorealism`. That order is
  for display; it isn't a key.
- **Several values in JSON** (proposed): a tag's values are always an
  array, `PATCH` adds or removes one value, and two filters on one tag
  mean both.
- **An app's own tags** (Thomas, 2026-10-13): besides the shared
  vocabulary, an app keeps tags of its own, facts about its world rather
  than the picture: Overlore's room id in the game (`kitchen`), a hero
  shot's `moment` and the `portrait` it was drawn from, a comic's
  `session`. They're searchable like any tag and can be in the app's
  indexes. Each is kept as two fields, owner and name, and written
  `overlore:room-id`, as a named text is (Thomas: yes, two fields, so apps
  that share are prepared); a shared tag has no owner.
- **The description's hash in a key** (`@overlore`, from Thomas): texts
  are content-addressed, so an index can key on an asset's description
  hash beside its tags. A voice clip is found by its words' hash and its
  voice, a room picture by its LOOK text's hash and its art style, and
  Overlore's `content_hash` and `look` tags go.
- **Custom values: later** (Thomas, 2026-10-14, through `@owl`), perhaps
  in a paid 2.0. Art style decides what can be shared, and sharing is what
  makes the pictures affordable, so Owl uses the standard values. An Owl
  world sets its art style, theme and rating apart, as the recipe's style
  and theme fields are: a player's "kiddy cartoon" is a kids theme, `g`,
  and `golden-comic`, `3d-cartoon` or `pixel`.
- **`rating`** is in the first vocabulary (`@owl`): `g`, `pg`, `r`, `x`,
  meaning the same in every app, since Owl's library skips `r` and `x`
  from other stores.

### First vocabulary: `art-style` (in progress, Thomas, 2026-10-13)

One tag, `art-style`, for how a picture is drawn or rendered (Overlore's
`art_style`; the park store's and Owl's `style`). It has no label: its
values say what they are (`golden-comic`, not `golden`), so a key reads
`watercolor`, not `watercolor-style`. A label is for a tag whose values
alone could be another's, as `red` could be hair, skin or a coat.

| Value | What it looks like | Today |
|---|---|---|
| `golden-comic` | Golden Age comics | Overlore's `golden` |
| `silver-comic` | Silver Age comics | Overlore's `silver` |
| `modern-comic` | modern comics | Overlore's `modern` |
| `dark-manga` | dark manga | Overlore's `manga` |
| `fantasy` | fantasy art as on book covers, slightly painterly | Overlore's `fantasy` |
| `photorealism` | looks real, however it was made, near-real 3D included | Overlore's `realism`, the park's `real` |
| `pixel` | pixel art; a filter on `pixel` finds every tier below | Overlore's `pixel` |
| `pixel-32` | detailed late 16-bit pixel art, Silicon Circus's usual | the park's `32-bit` |
| `pixel-16` | chunky early 16-bit | the park's `16-bit` |
| `pixel-8` | the coarsest | |
| `3d-cartoon` | 3D that looks sculpted and lit, rounded and exaggerated: the Toy Story middle ground | Overlore's `3d` |
| `watercolor` | storybook watercolour: soft washes, fine ink outlines | Owl's worlds (`@owl`; Thomas, 2026-10-14) |
| `painted-animation` | hand-painted animation backgrounds: lush colour, soft cel shading | Owl's worlds (`@owl`; Thomas, 2026-10-14) |
| `ascii` | text-mode art, ASCII made dynamic and modern; a picture of characters, or the characters themselves (ANSI art, asciinema's asciicast when it moves) | none yet |

- **Pixel tiers** (`@mj`; Thomas, 2026-10-13): Silicon Circus keeps
  `pixel-32`, `pixel-16` and `pixel-8` at once, since coarseness there is a
  stage of the story (the world pixelates as it comes apart), so each tier
  is a value. `pixel` alone is pixel art of no stated tier, and a filter on
  `pixel` finds every `pixel-*`.
- **`ascii`:** Overlore's `retro` leaves the art styles (`@overlore`): it
  becomes classic play, with almost no art, and its retro pictures fall out
  of use. `ascii` stays for ASCII art when someone makes it.
- Eras and neighbours get values only when someone makes them: `low-poly`
  (the clunky early 3D, which some games choose today), `3d-anime` (3D
  made to look hand-drawn: cel shading, outlines). The near-real end of
  pixel art and 3D is `photorealism`. `3d-cartoon` covers `@mj`'s icon
  sets.
- The park's `look` tag (day, night, clean, dark, dingy) isn't art style.
  It's two separate tags (Thomas, 2026-10-13): the lighting (day, dawn,
  dusk, night, and `dark`, a moonless night, very dark outside) and the
  subject's condition (clean, dingy). **Open:** the tags' names
  (`lighting` and `condition` proposed; `lighting` is a quality of light,
  apart from the picture's `light` field, which is its direction).
  `night` says when, not how dark (`@mj`): Silicon Circus's nights are
  floodlit, projectors on. Overlore's `look` (a hash of the room's text)
  goes, as above.

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
- **Who may change them** (Thomas, 2026-10-13): an app adds and drops its
  own; `@curio` may add or drop any app's, as the curator. Over HTTP
  (`@curio`): filters `?use=overlore:room`, `?use=overlore:*` and
  `?unused=1`, an asset's uses in its JSON, counts per use, and adding and
  removing one with the consumer named in the request.
- **A use carries no data** (Thomas, 2026-10-13). It's a yes-or-no
  marker. Where a prop is placed is a link to what it's placed on
  (`placed-on`, to the drop or to a name such as a venue's), with the
  position in the link's data, as a scrim's link names its drop. A prop
  placed twice gets two links, not two uses. (The park's 76 `used-by`
  links all say `boardwalk` and carry no data, so nothing is lost.)

## Areas and the ground

A prop that holds something has an opening or a writing area; a drop has
ground, where things can stand. An asset can have several. **Decided
(Thomas, 2026-10-13), built when an app first needs it:** a table of named
areas (asset, name, its shape, and for a video an optional frame range):
`opening`, `writing`, `floor`. Positions are fractions of the picture, 0
to 1 across and down, as the anchor's are, so an area can be drawn over a
thumbnail of any size (`@curio`). The first need may be Overlore's
one-hall onboarding: each style door's `opening`, where its view shows.

**The ground** (Thomas wants it recorded wherever it can be, so things
stand in a scene at the right size) has two halves:

- **A prop's** is stored already (0.11): its anchor, the point that sits on
  the ground (between the feet), and its real size in metres. `@owl` will
  fill in the anchor.
- **A drop's** is a few points on its ground, each with how big a metre is
  there, as a fraction of the picture's height. That gives the
  perspective: on flat ground the size falls steadily up the picture and
  reaches nothing at the horizon, so two points place the horizon, and
  more points follow slopes and uneven ground. A program puts a prop's
  anchor on a spot and draws it at its height in metres times the size of
  a metre there, read between the nearest points; the smaller size is the
  farther, which also says what to draw behind what. A raised stage or a
  step is ground of its own, a second set of points, since sizes can't be
  read across its edge. A side-on strip (the boardwalk) has its points
  along one line. `@owl` can work them out from the depth maps it makes
  for every drop, and would read them on other stores' drops.

## Pruning, eviction and shared files

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
as a stored file is deleted only when no asset refers to it. With a store
per app, this matters most for the common store.

**Deleting what's in use** (`@curio`): an app is refused, with the uses
listed (HTTP 409). `@curio`, as the curator, may delete it anyway, but a
person decides: it shows "used by overlore:room" and asks first.

**Shared files** (Thomas, 2026-10-13): stores share one bucket, each file
kept once by its hash, so a copy costs no storage. A store can't see
whether another still uses a file, so DataDungeon never deletes one from
shared storage, and another service (perhaps `@curio`) clears the files no
store uses. Built in 0.13: `shared: true` on the storage keeps deletes,
prunes and `vacuum` to rows, and writes every file a store stores even
when it's there, so a file's date is when a store last relied on it; each
store lists its files with `object_keys` (`GET /objects`). The clearing
asks every store for its list, then lists the bucket, and deletes only
what no list names and nothing wrote since it began, and clears nothing
while any store can't be reached.

**The hub** (Thomas's idea, 2026-10-14, through `@owl`) is that service: a
DataDungeon service on the bus that knows every store. It searches them as
one, merges duplicates by hash, filters by rating and art style, counts use
across stores, and clears the shared bucket, deleting a file only when no
store uses it. An app asks the hub, then copies what it chooses into its
own store, linked `copied-from` the file's hash. The copy is what makes
sharing crash-proof: the app has its own record, so it keeps working if
the store it came from goes down, and the bytes are still one file in the
bucket. Owl's library code is a small version and would be its first
user. **`@curio` builds it** (Thomas, 2026-10-14): curio already reads
every store, so the hub is a service on top of it. DataDungeon's part is
what each store offers: its search and use counts over HTTP, its uses
(0.14), `GET /objects` and shared storage (0.13). Clearing the bucket must
follow the order above (every store's list first, then the bucket, keeping
anything written since the run began), since stores rely on it. A copy
could later skip sending the bytes again: a call that records a row for a
file already in the bucket and refreshes its date there.

## Moving existing stores

Each app moves its own assets, one app at a time (Thomas, 2026-10-13):
each of its types becomes a standard type and a use, with its tags kept
and renamed to the shared vocabulary where they differ. Overlore has
worked out its own already (its 15 types; its 116 `transcript` assets go,
since a clip's words are its recipe's text). DataDungeon provides the
calls; the one-way part, as 0.12's keys were, is the schema. Curating
will find mistakes (a scrim filed as a drop), so one asset's type can be
changed too (`@curio`), to another on the list.

- **Owl** (`@owl`): scenes become drops (`owl:scene`), props props, depth
  maps maps, the narrator's lines speech. Its frames, stills of one shot
  played cross-faded as the player scrolls, would be drops (`owl:frame`)
  linked `derived-from` their scene with their place in the clip as the
  link's data. They stay stills (`@owl`, 2026-10-14): a clip is three to
  five of them, blended live with the depth map so the player can scrub it
  either way, and the last is the next place's picture. A clip a video
  model makes later would be one video. Its `kind` tag goes (the type says it), and so does
  `world` (Owl's own tables know it). Its descriptions are its whole
  prompts, so moving puts each prompt in its recipe's `prompt_sent` and
  leaves the description saying what the picture shows.
- **Pools** stay, as tag filters with a random pick (`@overlore`: 100
  banter scripts a language, about 100 decrees a game, stock drops by
  style and rating): `find_pool` and `count_pool_assets` over tags.
- **Across stores, a link names the file's hash** (`@owl`): `copied-from`
  a hash, which is the same everywhere, rather than a store's name and an
  id, which aren't.
`register_type` goes: types are DataDungeon's, and tags are defined in the
vocabulary. Apps keep `register_index` for their own fast lookups (Thomas,
2026-10-13).

## Open, collected

- The first shared vocabulary beyond `art-style` and `rating`: the names
  `lighting` and `condition`, the descriptions, and how a tag is added.
- The hub (`@curio`'s): what more it needs from each store.
- `q` over descriptions and a recipe's subject (`@owl` finds other stores'
  pictures by words, and Overlore's drops have none in their tags),
  before 0.15's semantic search.
- Release: 0.14, after the recipes in 0.13.
