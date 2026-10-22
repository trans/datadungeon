# Standard asset types

*Draft 2026-10-13, from Thomas and `@overlore`; reviewed the same day by
`@curio`, `@overlore`, `@owl` and `@mj`. The vocabulary is built (0.14);
the rest waits for an app that needs it. **Each store is one owner's**
(Thomas, 2026-10-16): an app that wants another store's assets copies the
records into its own, so what was here for several apps sharing one store
(uses, owner tags, refusing a delete while another app uses an asset) is
dropped, and the hub is deferred. **There are no standard styles**
(Thomas, 2026-10-17): each app names, words and tags its own, pictures
aren't expected to move between apps, and styles shared between apps fall
to the hub, later. **Standard types stay: without them sharing would be
impossible** (Thomas, 2026-10-19). The list is in 0.15.2
(`DB::STANDARD_TYPES`, `GET /vocabulary`), and the apps move onto it in
pieces (Thomas, 2026-10-19): one type first, Pirateship's voices to
`speech`; then a few more; then the rest, Overlore's. All had moved by
2026-10-20, and since 0.16 `register_type`, `rename_type` and storing take
only the listed names.
`register_type` stays: with one owner per store, the owner registers each
type with the traits its own lookups need, so keys needn't become the
apps' indexes. An app tells its own kinds of a type apart with one shared
tag, `subtype`, its values the app's own words (`room`, `door-view`): a
tag, so it can be in a key, and one name, so curio and a copy can tell
which tag gives the kind (Thomas, 2026-10-19). Shared tags beyond `rating`, several values per tag, the
see-through check and "anything that moves is video" wait, under the
freeze.*

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
   are the same whoever uses it. (Dropped 2026-10-16, with one owner per
   store: an app's own tag says it.)

## The types

Names settled (Thomas, 2026-10-13): `drop` for a backdrop, `scrim` for an
overlay, `prop` for an object (a sprite), `plug` for a framed moment shown
as it is (a comic panel, a hero shot; in stagecraft a plug, technically a
scenic insert; `panel`, `shot` and `tableau` were considered), and
`placard` for words shown between scenes. The names come from stagecraft
rather than film, since apps build rooms and scenes from these assets.
`pass` is a picture made for programs, not people, as compositing names a
depth pass or a matte pass (Thomas, 2026-10-20). It was `map` until then,
which read as a pirate's map or a Zork map; `scan` was considered
(2026-10-13), but a scanned page is a picture people read, and "utility
textures" would be confused with `texture`. Not `scene` for a
drop: setting the scene is the whole arrangement, drop, props and scrims
together, not the drop alone.

### Pictures, still or moving

| Type | What it is | See-through |
|---|---|---|
| **drop** | a place, the set things stand in front of | never |
| **plug** | a framed moment, shown as it is: a comic panel, a hero shot | never |
| **placard** | words shown on their own, between scenes: an intro, a title card, end credits | never |
| **scrim** | a frame's whole size, laid over a drop or plug | mostly |
| **prop** | an object, cropped close to its edges, placed by the app: anything from a cup to a building's front | around it |
| **texture** | a material with no subject or edges, filling an area | either |
| **icon** | a small indicator: a button, a rating; mostly SVG, or Lottie when it moves | either |
| **pass** | for programs, not people: a depth map, a mask, a matte | n/a |
| **automaton** | a character's moves as a graph of frames: which may follow which, walked afresh each play | n/a |
| **figure** | a character's body on bones (Spine, Live2D), its pictures props linked from it; the same type as a 3D figure (below) | n/a |

- **Opacity is part of the type,** so it's checked when stored: a drop, a
  plug or a placard with transparent pixels, in any frame, is refused. It's
  the pixels that are checked, not the format: a PNG with an alpha channel
  that is opaque throughout passes (`@overlore`). DataDungeon already
  decodes PNG and WebP (and TIFF) to find a picture's content box, so the check costs
  almost nothing.
- **A placard's words** are its description, so they're searched like any.
- **A scrim's link** (`placed-on`) names the one drop or plug it fits.
  Without one, it's generic and goes over any: rain, fog, a vignette.
- **A building's front is a prop** when the app places it, however big
  the building: "not a set or a figure" is about 3D models, where a place
  is a `set` and a character's body a `figure` (the wording says so since
  2026-10-21, after `@siliconcircus` asked about the park's venue fronts). A picture of a
  building's inside is a `drop`.
- **A sprite sheet** is a prop whose grid is data on it. DataDungeon has
  kept that since 0.11.1 (`ImageAnimation`: frame size and columns).
- **A prop that holds something** (a picture frame, a sheet of paper, a
  speech bubble) needs the position of its opening or writing area: an
  area (below).
- **A map of a place** (a game's world map) is a picture people read, so
  it's a plug or a drop, not a `pass`.
- **An automaton** (Thomas, 2026-10-19, from `@mj`'s Bard) is the graph
  itself, a JSON file, not a picture: which body frames may follow which,
  walked afresh on each play, so neither a `sequence` (one fixed timeline),
  a sprite sheet (a fixed loop) nor a 3D `motion` (a skeleton's). Each
  frame is a `prop` linked from it, its node and mouth shape in the link's
  data, so copying the graph copies its frames; unusable frames are
  `flagged`; the walker is the app's, named by the graph's format and
  version. There's one automaton per set of frames that connect
  (`@mj`): the cartoon Bard and the realistic one are two, not one for the
  character. Not `puppet`: puppet and marionette are kept for rigs, a
  character moved by controls, which are bound to come.
- **Image fields stay with moving pictures** (`@curio`): view, light,
  anchor, real size and content box are a picture's, still or moving, so a
  program reads them by the fields, not the media.

### Sound

| Type | What it is | Its own data |
|---|---|---|
| **speech** | one voice saying something, words or not (a laugh, a grunt) | its tracks (0.15.3): when each word is spoken (`words`) and the mouth's shapes (`mouth`), and its subtitles (`subtitles`, 0.16.5); the words, in its recipe; the speaker, open (below) |
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

**A take's tracks** (Thomas, 2026-10-19; built in 0.15.3): what a tool
measured of a recording over time, Whisper's word timings and Rhubarb's
mouth cues (`@overlore`), go in with the speech as its own data, each
naming its tool, version and the options that change its result. A
`words` track holds each word as written, punctuation and all, when the
tool aligns a known text, as Overlore's takes all have one, and as heard
when it transcribes (`@overlore`: Whisper mishears names, and then the
track no longer matches the script). Not with the script, since every take is
paced differently, and not as assets of their own, since they're facts
about one take, as a picture's content box is. The choreography an app
makes from them and an automaton is its own, kept in its own database,
not in DataDungeon (Thomas, the same day: poses named in a script would
tie it to one automaton's).

**Later: a track's cues as an asset file** (Thomas, 2026-10-22): "in a
future version we are going to move tracks to assets in [general] and only
keep the name / tool and normal metadata -- the text itself can be a asset
file, that way we can support standard formats (which we would want to do
anyway)." A track's row keeps its name, tool and when it was made; its cues
become a text asset in a standard format (WebVTT or SRT for subtitles),
linked to the clip. They're still facts about one take (above), but that
doesn't stop them being stored as assets: they hang on the clip by a
*dependent* link (Thomas, the same day: "something we might want to think
about more"). Open: what a dependent link means (does it go with its
clip, travel with it when copied?), the format for each track (`words`,
`mouth`), the link's name, and a track made by hand, which names no tool.

### Text

| Type | What it is |
|---|---|
| **prose** | continuous writing in one voice: a description, a decree, a story |
| **script** | lines for voices in turns |
| **transcript** | the words of an audio or video asset as text: corrected by hand, with who speaks, with sounds that aren't words; linked `transcript-of` it. A `words` track is a tool's timing of the words, not their text |
| **log** | a record of what happened, in order (what interactive fiction calls a transcript) |

**A recording's words** (Thomas, 2026-10-20) are kept in one of three
places, by when they were written and what they're for:
- **Before, what it was made from:** its recipe's prompt, the text sent to
  the voice. It may hold directions that aren't spoken (`[whisper]`).
  Prompts aren't assets: they're texts in the recipe tables, inputs to
  making something.
- **After, what is heard:** its `words` track, with each word's time,
  which is a measurement of the recording, as a picture's content box is.
  The track's `tool` says whether it aligned the known text or transcribed
  the sound; an app keeping both names the second (`words-heard`). A
  recorded or uploaded clip, with no recipe, has only this.
- **A `transcript` asset, the words as text.** A `words` track is a tool's
  timing of the words, not their text, so it has no place for a word
  corrected by hand, who speaks, sounds that aren't words ("meows twice,
  then purrs"), words no tool could time, or lines and stage directions.
  Keep a transcript when you need any of those. It links to its recording
  `transcript-of`, which works for video as for audio, allows several (one
  per language), and goes when either asset does.

A clip made from a prompt usually needs no transcript: the prompt is its
text, and its `words` track adds the timing. Overlore's 117 were copies of
their clips' prompts, byte for byte, and were deleted in piece 3 (Thomas,
2026-10-20). An earlier wording, "only when the words are a thing of their
own", read as if a track were the transcript of an ordinary clip; Thomas
(2026-10-20, through `@curio`): a words track isn't a transcript.
Subtitles, timed lines, are a track for now, the shared `subtitles` track
(0.16.5), a line to a cue (Thomas, 2026-10-22), and later an asset file in a standard format, as every
track's cues will be ("Later", under a take's tracks).

`audio_meta.transcript_id`, from 0.2 (2026-03), before recipes and tracks,
pointed a clip at one text asset; Overlore was the only app to use it, and
no live store sets it now (2026-10-20). It is deprecated: link a transcript
`transcript-of` its recording instead. The column stays (Thomas,
2026-10-20: "You never know we might find some other need for the column
and then we can just rename it"). Deleting an asset clears any clip's
`transcript_id` that names it (0.15.5; the foreign key refused the delete
before).

**Scripts** use Yarn Spinner's line syntax (`@overlore`'s proposal; notes
in Overlore's `docs/SCRIPT-FORMATS.md`): `Veteran: This isn't a stage,
bard. Sit down. #kind:retort`, speaker, text and `#` tags, with optional
`#line:` ids to key recordings, and directions for the voice in Yarn's
markup (`[sighs/]`). There's no registered content type: `text/plain`, or a
`text/x-yarn` of our own. A script may pin a pose the body must strike, the
bow at the end, as `[pose=bow/]`: `pose` is the one tag for the body, and
every other tag is the voice's, which the app turns into its voice engine's
own before asking for a take; a tag the app doesn't know is an error
(`@overlore`'s proposal; Thomas: it makes sense, 2026-10-19). DataDungeon
doesn't read the tags.

### Documents and data

| Type | What it is |
|---|---|
| **document** | made to be read: pages laid out, text and pictures (PDF, EPUB), often assembled from other assets |
| **data** | made for programs: structured (JSON, CSV) or binary (a story file, a saved game); its format and version say which program reads it. Also the catch-all |

### 3D

| Type | What it is |
|---|---|
| **set** | a place, to be inside or look into |
| **prop** | a 3D model of a thing (a chair, a sword) that isn't a set or a figure, placed by the app: the same type as a picture's prop |
| **figure** | a character's body, usually rigged; also 2D, on bones (Pictures, above) |
| **motion** | movement for a skeleton, without geometry |

The form (mesh, Gaussian splats, point cloud, voxels) is a property, since
a `.ply` can hold any of them. glTF 2.0 / GLB is the standard for meshes.
A material's pictures reuse the picture types: its colour image is a
texture, its normal and roughness images passes.

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

**Where it's kept** (Thomas, 2026-10-13; built in 0.14): a table in the
store, each tag with its label, kind and a one-line description of what it
means, and its values each with one too, seeded with the agreed tags
(`vocabulary_tags`, `vocabulary_values`; `DB#vocabulary`, `GET
/vocabulary`). Tags and values have titles for people, so apps show the
same names ("Rating", "PG"; Thomas, 2026-10-15). A value can name its
family (none does yet), and a rating has DataDungeon's words for it
(`dd:pg`). The standard art styles 0.14's builds seeded before the tag are
gone (below). For now a tag or a
value is added in a DataDungeon release, by agreement: every store opened
read-write takes the vocabulary its release has, and keeps a value a later
release drops.

- **Over HTTP** (`@curio`): `GET /vocabulary`, each tag's name, title,
  label, description, kind and the values in use, for tooltips and the filter
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
  indexes. (An owner field for them, `overlore:room-id`, was planned so
  apps sharing a store were prepared; dropped 2026-10-16, since a store is
  one owner's.)
- **The description's hash in a key** (`@overlore`, from Thomas): texts
  are content-addressed, so an index can key on an asset's description
  hash beside its tags. A voice clip is found by its words' hash and its
  voice, a room picture by its LOOK text's hash and its art style, and
  Overlore's `content_hash` and `look` tags go.
- **Styles are each app's own** (Thomas, 2026-10-17). Custom values were
  first put off to a paid 2.0, with Owl on the standard art styles, since
  sharing was to make pictures affordable (Thomas, 2026-10-14, through
  `@owl`). With pictures staying in their app and each app wording its own
  styles, there are none to share, so each app names and tags its own. An
  Owl world sets its art style, theme and rating apart, as a recipe's style
  and theme are: a player's "kiddy cartoon" is a kids theme, `g`, and one
  of Owl's styles.
- **`rating`** is in the first vocabulary (`@owl`): `g`, `pg`, `r`, `x`,
  meaning the same in every app, since Owl's library skips `r` and `x`
  from other stores. Each has DataDungeon's words, one wording for every
  form, saying what's suitable rather than listing what's forbidden
  (Thomas, 2026-10-16; the words 2026-10-17), `dd:<rating>` from
  `db.rating_text`:

  | Value | DataDungeon's words |
  |---|---|
  | `g` | Family-friendly and wholesome, suitable for all ages. |
  | `pg` | Suitable for older children: mild peril and action, kept clean. |
  | `r` | For mature audiences: violence, blood and risqué scenes may be shown. |
  | `x` | For adults only. |

### Art styles: dropped before 0.14's tag

*There are no standard styles (Thomas, 2026-10-17): each app names, words
and tags its own, and styles shared between apps fall to the hub (below).
What follows is the record of the `art-style` vocabulary agreed on
2026-10-13, which 0.14's builds seeded before the tag (a store they opened
loses it on its next open), and of what each app called its styles.*


One tag, `art-style`, for how a picture is drawn or rendered (Overlore's
`art_style`; the park store's and Owl's `style`). It has no label: its
values say what they are (`golden-comic`, not `golden`), so a key reads
`watercolor`, not `watercolor-style`. A label is for a tag whose values
alone could be another's, as `red` could be hair, skin or a coat.

| Value | Title | What it looks like | Today |
|---|---|---|---|
| `golden-comic` | Golden Age Comic | Golden Age comics | Overlore's `golden` |
| `silver-comic` | Silver Age Comic | Silver Age comics | Overlore's `silver` |
| `modern-comic` | Modern Comic | modern comics: detailed inks, digital coloring | Overlore's `modern` |
| `dark-manga` | Dark Manga | dark manga | Overlore's `manga` |
| `fantasy` | Fantasy Cover | classic fantasy cover art, slightly painterly | Overlore's `fantasy` |
| `photorealism` | Photorealism | looks real, however it was made, near-real 3D included | Overlore's `realism`, the park's `real` |
| `pixel` | Pixel | pixel art; a filter on `pixel` finds every tier below | |
| `pixel-32` | 32-Bit Pixel | detailed late 16-bit / early 32-bit pixel art, Silicon Circus's usual | the park's `32-bit` |
| `pixel-16` | 16-Bit Pixel | chunky early to mid 16-bit | the park's `16-bit`; Overlore's `pixel` (Thomas, 2026-10-14) |
| `pixel-8` | 8-Bit Pixel | the coarsest | |
| `3d-cartoon` | 3D Cartoon | 3D that looks sculpted and lit, rounded and exaggerated: the Toy Story middle ground | Overlore's `3d` |
| `watercolor` | Storybook Watercolor | storybook watercolour: soft washes, fine ink outlines | Owl's worlds (`@owl`; Thomas, 2026-10-14) |
| `painted-animation` | Painted Animation | hand-painted animation backgrounds: lush colour, soft cel shading | Owl's worlds (`@owl`; Thomas, 2026-10-14) |
| `ascii` | ASCII | text-mode art, ASCII made dynamic and modern; a picture of characters, or the characters themselves (ANSI art, asciinema's asciicast when it moves) | none yet |

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

*Dropped 2026-10-16 (Thomas): a store is one owner's, so an app's own tags
say how it uses an asset. Kept here for the record.*

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

**Deleting what's in use** (`@curio`): an app was to be refused, with
the uses listed (HTTP 409). Dropped 2026-10-16 with uses: a store's owner
decides what it deletes, and other stores hold copies of their own.

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

**The hub** (Thomas's idea, 2026-10-14, through `@owl`; deferred
2026-10-16, until stores connect to each other) is that service: a
DataDungeon service on the bus that knows every store. It searches them as
one, merges duplicates by hash, filters by rating, counts use
across stores, and clears the shared bucket, deleting a file only when no
store uses it. An app asks the hub, then copies what it chooses into its
own store, linked `copied-from` the file's hash. The copy is what makes
sharing crash-proof: the app has its own record, so it keeps working if
the store it came from goes down, and the bytes are still one file in the
bucket. Owl's library code is a small version and would be its first
user. **`@curio` builds it** (Thomas, 2026-10-14): curio already reads
every store, so the hub is a service on top of it. DataDungeon's part is
what each store offers: its search over HTTP, `GET /objects` and shared
storage (0.13). Clearing the bucket must
follow the order above (every store's list first, then the bucket, keeping
anything written since the run began), since stores rely on it. A copy
could later skip sending the bytes again: a call that records a row for a
file already in the bucket and refreshes its date there.

**Shared styles are the hub's** (Thomas, 2026-10-17; not needed yet). With
no standard styles, the hub is the one thing that can coordinate sharing
them: a lookup table of the styles each store uses, its name and words. A
store can adopt another's style, using its name and words as they are,
and from then on their pictures in that style can be shared.

## Moving existing stores

Each app moves its own assets, one app at a time (Thomas, 2026-10-13):
each of its types becomes a standard type and a use, with its tags kept
and renamed to the shared vocabulary where they differ. Overlore has
worked out its own already (its 15 types; its 117 `transcript` assets go,
since a clip's words are its recipe's text). DataDungeon provides the
calls; the one-way part, as 0.12's keys were, is the schema. Curating
will find mistakes (a scrim filed as a drop), so one asset's type can be
changed too (`@curio`), to another on the list.

- **Owl** (`@owl`): scenes become drops (`owl:scene`), props props, depth
  maps passes, the narrator's lines speech. Its frames, stills of one shot
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
`register_type` was to go, types being DataDungeon's and tags defined in
the vocabulary, with apps keeping `register_index` for their own fast
lookups (Thomas, 2026-10-13). It stays (2026-10-19): a store is one
owner's, so its owner registers each standard type with its own key.

**In pieces** (Thomas, 2026-10-19), each app's agent moving its own store,
rehearsed on a copy first: `rename_type` moves a type's assets, tags,
registration and indexes, and joins them to the target's when it has
assets already, so two of an app's types become one standard type. An app
whose kinds share a standard type tags them first with `subtype`, and
registers the standard type with the traits it looks them up by.
Pirateship (piece 1, 2026-10-19) keeps the call in its start-up, so its
deployed store moves on its first start; from 0.15.3 a call with nothing
left to move changes nothing (in 0.15.2 it logged every asset of the type
again and rewrote their search rows on each start).

| Piece | Store | Its types → standard types |
|---|---|---|
| 1 | Pirateship | voice → `speech` |
| 2 | Cattacula | voice → `speech` |
| 2 | the park | stage-standup → `speech`; prop is already `prop` |
| 2 | Owl | owl_scene, owl_frame → `drop`; owl_depth → `map`, `pass` since 0.15.6; owl_voice → `speech`; owl_prop → `prop` |
| 3 | Overlore | room, door_view, background, backdrop → `drop`; panel, heroshot, portrait → `plug`; banter, narration → `speech`; banter_script → `script`; decree → `prose`; comic → `document`, `subtype` `comicbook`; layer → `prop`; its `transcript` assets are deleted (Thomas, 2026-10-20: each is its clip's prompt, byte for byte); `legacy`: one portrait kept as a `plug`, three deleted |

Every store had moved by 2026-10-20: Pirateship (piece 1), Cattacula, the
park and Owl (piece 2; Owl's depth maps `pass` since its `16748f9`), and
Overlore (piece 3, its `f9c472ee`). An app with a store that hasn't moved yet, a deployed copy
say, moves it on a 0.15 build before taking 0.16, which refuses to register
the old names.

## Open, collected

- The first shared vocabulary beyond `rating`: the names
  `lighting` and `condition`, and the descriptions. A tag is added in a
  release for now (0.14).
- The hub (`@curio`'s): what more it needs from each store.
- **Tracks' cues as asset files** (Thomas, 2026-10-22; a future version):
  the track keeps its name, tool and metadata, its cues a text asset in a
  standard format, hanging on its clip by a *dependent* link, which wants
  thinking about. Subtitles are a track (`subtitles`) until then.
- **2D and 3D don't line up** (Thomas, 2026-10-21: "Have to think about
  that"). A `drop` is in effect a 2D `set`, but `prop` is both 2D and 3D,
  and `figure` is 3D, or 2D only when rigged: a flat character with no
  bones is a prop, or an automaton's frames. A 2D character on bones
  (Spine, Live2D: the marionette setups Thomas expects) is a `figure`
  since 2026-10-21 (Thomas chose adding the wording now over a to-do).
- **Characters: to do** (Thomas, 2026-10-21, after `@mj` reopened "tags
  are claims"' no characters on 2026-10-19). A character is an asset: a
  standard record of the character's attributes. Other assets link to it
  because the character is in them (a picture, an automaton) or speaks in
  them (speech). How is open (Thomas: "I am not 100% sure about how we do
  it, but that's the general notion"): a `character` type and its media;
  which attributes are standard, and whether they're tags or the record's
  own data; the link names (`depicts`, `voiced-by` were floated); the
  sheet `@mj` wants for making more of one (reference pictures, its
  `character` wording, which is already a named wording, DESIGN-recipes);
  and copying a character between stores, which would have to follow its
  links. A speech's speaker waits on it: the voice is in the recipe, but
  who speaks is a character.
- `q` over descriptions and a recipe's subject (`@owl` finds other stores'
  pictures by words, and Overlore's drops have none in their tags).
  Semantic search (0.15.7, `GET /search`) reads descriptions and the tags
  a type's registration embeds, not recipes.
- Release (Thomas, 2026-10-15): the vocabulary in 0.14 with the new
  picture prompts, `rating` only (no standard styles, Thomas, 2026-10-17). The types, several values per tag
  and keys as the apps' indexes wait for an app that needs them (Thomas,
  2026-10-16: a freeze on what no app uses yet); uses and owner tags are
  dropped. 0.15 is a small cleanup, without them (Thomas, 2026-10-17).
  The types' list is 0.15.2, the apps move in pieces, and 0.16 refuses
  unlisted names (Thomas, 2026-10-19; released 2026-10-20).
  `audio_meta.transcript_id` stays, deprecated (Thomas, 2026-10-20), not
  dropped as first planned; 0.15.5 lets a transcript it names be deleted.
