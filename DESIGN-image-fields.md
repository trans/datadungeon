# Image fields, views and placement

*Designed with Thomas, 2026-10-09. Built: keys, retiring and indexes in 0.11.0; image fields, views, keyframes and best match on fields in 0.11.1; the type's own key moved into the index table, with registration required, in 0.12.0.*

## The model

Agreed with Thomas and `@curio`, 2026-10-09. Each fact about an asset has
one home, by what it is about:

| Fact | Home | Example |
|---|---|---|
| What the asset **is** | its key (traits) | `prop.christmas-tree.night` |
| What the picture **is like** | image fields: real columns, comparable by range | width, view, anchor, real height |
| **Who** uses it and **where** | a link | `used-by` → `boardwalk.holidayland` |
| **How** it is placed there | the link's data | facing north, at x/y, scale 1.2 |

What the key holds gets one test: **does it tell two versions of the same
thing apart?** Day and night versions are two assets of one thing, so time of
day is a key trait (a word, or a cyclic scale for best match). Numbers stay
fields even when they tell versions apart (the blimp facing left or right):
a pooled type holds both, and a join on the field tells them apart (see
Named directions).
Renditions (sizes, formats) are made on request and never stored; a
version redrawn small on purpose is its own master, so its size can be
identity.

## Image fields

New columns on `image_meta`. `NULL` means not known, never zero.

**Measured by DataDungeon** when it stores the bytes (and when they change),
so no caller parses image headers:

| Column | Type | Meaning |
|---|---|---|
| `width`, `height` | INTEGER px | exist; now filled by DD |
| `animated`, `frame_count`, `duration_ms` | | exist; now filled by DD for animated WebP and GIF |
| `transparent` | BOOLEAN | any transparent pixel: a cut-out, not a full rectangle |
| `dominant_color` | INTEGER 0xRRGGBB | the colour most of the visible picture is (hex in the API). Not "key colour": `@mj`'s cut-out pipeline uses that for the background it removes |
| `content_x`, `content_y`, `content_w`, `content_h` | INTEGER px | the box around the visible pixels |

DD decodes PNG and WebP already; a JPEG gives its size from the header, and
no key colour or content box unless a decoder is added.

**Set by the application**, usually from what it asked the generator for:

| Column | Type | Meaning |
|---|---|---|
| `view_x`, `view_y`, `view_z` | REAL, a unit vector | where the camera stands (below) |
| `view_roll` | REAL, quarter turns, −2 to 2, default 0 | the picture turned in its own plane |
| `light_x`, `light_y`, `light_z` | REAL, a unit vector | where the light comes **from**, in the picture's frame (below) |
| `anchor_x`, `anchor_y` | REAL, 0 to 1 | the point that sits on the ground or attaches, as fractions of width and height |
| `world_width`, `world_height`, `world_depth` | REAL, metres | the thing's real size in its own frame: width across (x), height (y), depth front to back (z). A blimp is about 10 × 12 × 40. Intrinsic, never per use; any may be empty |

`usage_class`, `compression`, the other existing columns and the opaque
`presentation` JSON stay as they are.

Scale follows from the real size seen from the picture's view and the
content box: the extent across the picture comes from the size and the
view vector (a blimp from the side shows its 40 m depth, from the front its
10 m width), and over `content_w` gives metres per pixel, so a scene can
draw every prop to one scale. A spin needs no size keyframes: its size is
the thing's, and only the view turns (`@curio`, 2026-10-09).

Light is stored in the **picture's** frame (x right, y up, z toward the
viewer), not the thing's: a picture's lighting is fixed in its pixels, and
what matters is whether it agrees with a scene's light on screen ("lit from
the upper left"), one range whatever side the thing is seen from. It can be
turned into the thing's frame through the view when needed. Readable form
as for views: `side` front (lit from the viewer's side) or back (backlit),
`yaw` from the picture's left to right, `pitch` from below to above; upper
left from the front is about yaw −0.5, pitch 0.5. A scene that mirrors a
sprite mirrors its light too (the link's placement records the mirroring).

Light is usually decided rather than measured: a venue picks its light and
generates everything that way, and the field records it.

**View and light record what was asked for.** `@mj` renders them into the
prompt, and models follow only approximately (10-20° off at times). The
fields mean "as asked", and curio lets a person correct one that is
visibly wrong; a column saying where a value came from (asked, estimated,
checked) can come later if misplaced props become a problem.

## Views and light as vectors

A view is stored as one arrow: the direction from the thing to the camera,
a vector of length 1 in the thing's own frame.

- **z** points toward its front: 1 seen from straight in front, −1 from behind.
- **x** points toward its right side.
- **y** points up: 1 seen from directly above.

**Applications and curio use the readable form**, and DataDungeon converts:

| Field | Values (quarter turns: 1 = 90°) | Meaning |
|---|---|---|
| `side` | `front` / `back` | which face the camera sees |
| `yaw` | −1 to 1 | toward the thing's left (−1) or right (+1) side, on either face |
| `pitch` | −1 to 1 | from below (−1), level (0), from above (+1) |
| `roll` | −2 to 2 | stored as it is |

```
x = cos(pitch°) × sin(yaw°)                       (yaw°, pitch° = value × 90°)
y = sin(pitch°)
z = ±cos(pitch°) × cos(yaw°)                      (+ front, − back)

pitch = asin(y) / 90°      side = front when z ≥ 0      yaw = asin(x / cos(pitch°)) / 90°
```

| View | side | yaw | pitch | x | y | z |
|---|---|---|---|---|---|---|
| Front, eye level | front | 0 | 0 | 0 | 0 | 1 |
| Three-quarter front-right | front | 0.5 | 0 | 0.71 | 0 | 0.71 |
| Right side | (either) | 1 | 0 | 1 | 0 | 0 |
| Back, from 30° above | back | 0 | 0.33 | 0 | 0.5 | −0.87 |
| Straight down | (either) | (any) | 1 | 0 | 1 | 0 |

Because yaw counts toward the thing's right on both faces, front and back
meet at the sides. A worked case intake will get backwards otherwise: a
profile whose nose points **left** in the picture shows the thing's
**right** side, so yaw is +1. Straight down (or up), yaw means nothing, which the vector
says by itself (x and z are 0); roll then gives which way the thing's front
points in the picture (0: toward the top).

**Why store the vector, not the readable form:**

- One home for the number, with no seams: the sides and the poles are points
  like any other, so nothing needs normalizing.
- Common questions are single ranges: facing front within 30° is
  `view_z >= 0.87`, from above `view_y >= 0.71`, the right side `view_x >= 0.87`.
- "Within 20° of this view" is one dot product:
  `view_x*x0 + view_y*y0 + view_z*z0 >= cos(20°)`.
- Best match takes the vector as the view's block, so neighbouring views
  count as close however they are written.

**For people:** a read-only SQL view, `image_views`, shows each image's
side, yaw, pitch and roll computed from the vector, so the database reads
plainly at the sqlite3 prompt. It needs SQLite's math functions (in this
machine's build; DD skips the view where they're missing).

**For the search box:** a view's named direction and its elevation are its
search words (one vocabulary, below), so `back-left from-above` finds such
pictures.

## Named directions

A view also has a readable name, derived from its vector: one of eight
directions around the thing (`front`, `front-right`, `right`, `back-right`,
`back`, `back-left`, `left`, `front-left`), plus `from-above` or `from-below`
past 45° (an independent word: `view=back-left` matches a back-left
picture from above too), and `top-down` or `bottom-up` at the poles. Pictures are usually
asked for at a named direction, so they sit in the middle of a sector. The
name is shown in the API, goes into the search words, and can be filtered
on (`view=back-left`); a type wanting finer steps (a 16-direction turntable
sheet) could ask for more sectors.

**Not in the key** (Thomas, 2026-10-09): the view is a field, so telling
versions apart is a join on it. A pooled type keeps several views of one
thing under its key. A single-best type would replace one view with another
under the same key, so it becomes a pool, or the application adds a trait
word for the version (`facing: left`). The same goes for a hand-made size:
it is `width`/`height`, a field, not a key part. So keys stay built from
tags alone, and no field ever re-keys an asset.

## Placement on links

A link gains a JSON `data` (as Artistry's links have), holding how the
thing is placed in that use: position, which way its front faces in the
scene (a vector, as above), scale, layer. DataDungeon stores it opaquely at
first; parts become real columns if they need range queries ("everything
facing north in Holidayland"). The same image can be placed differently in
two areas: two links, two placements.

Link names stay hierarchical under their user (`boardwalk.holidayland`), and
link filters match by prefix (curio's request, 2026-10-09):
`boardwalk.holidayland` exactly; `boardwalk.*` the user and everything under
it, but not `boardwalk-annex`; `boardwalk*` any name starting so.

## Animation

An animated image's fields can change as it plays: a turntable spin starts
at the front and ends at the back (Thomas, 2026-10-09). The rule:
**`image_meta` is the picture at time 0** (for a still picture, simply the
picture; for an animation, its first frame), and **keyframes record what
changes from there**. Two more tables, each keyed by the asset and deleted
with it:

- **`image_animation`**: one row for an animated picture, none for a still
  one: `frame_count`, `duration_ms`, `loop_count` (moved here from
  `image_meta`), and a sprite sheet's grid (`frame_w`, `frame_h`, `columns`).
- **`image_keyframes`**: rows only for an animation (each points at its
  `image_animation` row), keyed by `(asset_id, at_ms)` after time 0, holding
  only the fields that change, each with the moment it reaches its value.
  Not every frame, which would be far too much data (Thomas): checkpoints.

A still lamppost (asset 7):

| table | rows |
|---|---|
| `image_meta` | 1: 512×512, view front, anchor at its base, 3 m tall, … |
| `image_animation` | none |
| `image_keyframes` | none |

A spinning blimp (asset 9, 48 frames over 2 s, looping):

| table | rows |
|---|---|
| `image_meta` | 1: the first frame: 256×128, view front, 40 m long, … |
| `image_animation` | 1: 48 frames, 2000 ms, loops forever |
| `image_keyframes` | 3: at 500 ms view right; at 1000 ms view back; at 1500 ms view left (then back to the front) |

What never changes in an animation (its size, its real size, a fixed anchor)
lives only in `image_meta`. Between checkpoints, values follow from their
neighbours: numbers in a straight line, views and light along the shorter
arc between their vectors, or held (a jump, not a glide) for an animation
that switches rather than moves. Two rules keep it exact:

1. A view's checkpoints are at most 90° apart (front straight to back would
   be ambiguous: which way round?).
2. There is a checkpoint wherever something turns: the top of a jump, the
   end of a swing. Values then move only one way between checkpoints, so
   "does it ever show the back?" is answered exactly by `image_meta` and the
   keyframes (`view_z <= -0.87`), indexed alike.

An animation that changes nothing but its pixels (a flickering flame) has
no keyframes. The key, the search words and best match use `image_meta`, the
picture at time 0; a spin has no one view, so its key says what it is
(`blimp.spin`).

## Best match

- `cycles:` beside `scales:`: values around a circle (`dawn day dusk night`),
  so a request for night that finds none ranks dusk, not day, next.
- A view or a light is a block holding its vector; `view_roll` a block on a
  circle; `dominant_color` a colour block. A type lists the fields it matches on
  (`match_fields: %w[view dominant-color]`), beside its traits.

## Setting and filtering fields

- `update_asset(id, image: …)` sets image fields on a stored asset, changing
  only those given (today `image_meta` is written only when first stored).
  The API's `PATCH /assets/:id` takes them, views in the readable form.
- `list_assets` and the API filter by range (`world_height` 2 to 4) and by
  view (within an angle of a given view).
- A maintenance call measures existing images (decoding each stored object,
  which costs a download for a bucket). curio's 76 park props have no
  `image_meta` yet.

## Decided (Thomas, 2026-10-09)

- Both `world_width` and `world_height`; one may be empty.
- Placement as opaque JSON on links to start; columns only when needed.
- Indexes on almost all of the new fields, since nearly every image has
  them.
- Animation in its own tables, since its fields can change frame to frame:
  `image_meta` is the picture at time 0, keyframes record what changes.
- The content box is measured by DD (per keyframe when it changes).
- Views have named directions, but no field goes into keys: a pool and a
  join on the field tell versions apart.

## Decided after review (Thomas, 2026-10-09)

From `@curio`'s and `@mj`'s review:
- Real size as width, height and depth in the thing's own frame.
- Light in the picture's frame.
- **Storing a file the type already holds is an error**, not a silent
  upsert (Thomas): `AlreadyStored`, naming the existing asset and whether
  it is superseded (HTTP 409). The app says what it meant:
  `update_asset(id, tags: …)` to change its traits, `reinstate(id)` to bring
  back a retired take, or `find_by_hash` to check first. One exception, so
  retries are safe: an exact repeat (the same bytes, type and traits, the
  asset current) returns the existing asset. Within a type only: the same
  picture can be a `backdrop` and a `room`.
- Prefer is soft: it never outranks a better match, only orders otherwise
  equal candidates, newest first by `made_at` (below).
  `@mj`'s `version` is provenance, not a rank: it, `pool` and the model go
  in the `generation` JSON, with nothing ranked on them.
- View and light mean "as asked"; correction in curio.
- `dominant_color`, not `key_color`.
- One vocabulary for directions; the side convention's worked case.

## Keys as an index

Thomas, 2026-10-09: the key is an index, not an identifier, so keys stop
being unique. **The application defines what a pool is, not DataDungeon**:
a pool is whatever an app's query asks for, the assets whose traits are
these. Cattacula asks with bit, beat, voice and format, so its pool is the
takes of one line in one voice; another app could ask the same store with
the bit alone. Nothing is replaced, so everything is kept. Durable
references are the row id (and the content hash for bytes), never the key
string; the docs say so.

**Superseding is by id** (Thomas, 2026-10-09): `store(…, supersedes: id)`
adds the new take with a `supersedes` link to the one named, which stays but
drops out of `get`, listings, best match and search. Only the app knows
which take it is redoing, and views and sizes are fields, not traits, so
"every take with the same traits" would be too wide: the blimp's right-side
view would retire its left-side view, and a hand-made 16 px icon its 512 px
master (`@curio`, 2026-10-09). No type retires anything by itself
(Thomas): the single-best and `pool:` flags go, and every store adds.
`get(type, traits)` finds the candidates by the key, skips superseded ones,
and prefers the newest, so an app that regenerates a take without naming the
old one still plays the new one; naming it (`old = db.get(…)`, then
`db.store(…, supersedes: old.id)`) keeps the history tidy. Cattacula and
Pirateship will change their regeneration that way.

- **Uses are copied** to the new take (Thomas): its predecessor keeps its
  `used-by` links (and their placement data), hidden with it, so its history
  stays and undoing is just removing the `supersedes` link. If the new
  picture's anchor or size differs, adjusting placement is the app's call.
- **`reinstate(id)`** makes a superseded take current again: the links
  superseding it go, and it supersedes the current one (Overlore's case,
  2026-10-08: original voice takes brought back after a voice change).
- **Pruning is the app's call** (Thomas): a call deletes a type's superseded
  assets, optionally keeping the last N or those newer than a date; Overlore
  would keep voice takes and prune old comic PDFs.

## Retiring, and the dates on an asset

**`retired_at`** is the one "hidden" flag (Thomas, 2026-10-09): an asset
with it set drops out of `get`, listings, best match and search, an
indexed check rather than a link lookup. `store(…, supersedes: id)` sets it
on the take named (and adds the `supersedes` link, kept as history);
`retire(id)` sets it with no replacement, curio's everyday soft delete,
where Delete is the rare final step (`@curio`); `reinstate(id)` clears it.
Listings take `superseded=1` or `only`, and counts exclude retired assets,
reporting how many there are.

**`made_at`** is when the content was made, and the only date "newest
first" uses: a batch or an import passes it (a batch drawn over hours and
filed at once, or a re-filed library, would otherwise look brand new), and
it defaults to the filing time. Reinstating never changes it (`@mj`,
2026-10-09).

The dates on an asset, each with one job (Thomas: keep an eye on how many):

| Date | Job |
|---|---|
| `made_at` | when the content was made: recency, "prefer newest" |
| `created_at` | when DataDungeon filed it: housekeeping |
| `retired_at` | hidden since: superseded or retired |
| `last_used_at` | last served (with `use_count`): eviction |

## Indexes per consumer

If the key is an index for a consumer's common queries, each consumer
defines its own (Thomas, 2026-10-09), and changing one touches nobody
else's: no more re-keying everyone's assets in a shared store.

- **The type** is registered once, by its owner (the park store's
  `types.cr`): its traits' names, how values are normalized, labels, sets,
  scales, colours, weights. The shared vocabulary.
- **An index** is registered by a consumer, with a name and a trait order.
  Its identity includes the consumer, so consumers can't step on each
  other: an app says who it is when it opens the store, and its
  `register_index` calls create, change and re-key only its own.
  ```crystal
  db = DataDungeon::DB.new(path, consumer: "cattacula")
  db.register_index("voice", "lines", traits: %w[bit beat voice fmt])
  ```
- **One table holds the keys**: `asset_keys (index_id, key, asset_id)`,
  indexed on `(index_id, key)`, one row per asset per index of its type. A
  prefix lookup is one range scan, as fast as today's `pool_key` column.
  Every write recomputes an asset's keys in its type's indexes.
- **Reads can use any consumer's index**: an index is only a faster path to
  the same assets.
- **Today's `pool_key`** becomes the type's default index (the order its
  owner registered), so existing data and callers keep working; the API
  keeps showing it, documented as derived. (0.12.0: the type's own index,
  consumer and name empty; the column is gone, `AssetRecord#key` reads it,
  and storing needs a registered type.)

**Apps just ask with traits; DD picks the path**, as an SQL planner does
(and as DD already does with one key):

1. Each index's usable prefix is the longest run of its leading traits the
   query fixes: index `bit beat voice fmt`, asked for bit, beat and voice,
   gives a prefix of three, one range scan.
2. DD counts each candidate range (capped, so it's cheap), the prefixes and
   each single tag, and starts from the smallest: a long prefix of common
   values ("rating pg") can match more than one rare tag.
3. Every other condition (traits, search words, links, fields) is checked
   on each candidate, by an indexed lookup.

A prefix needs the index's first trait: an index `art-style rating gender`
helps a query on rating and gender only if art style is fixed too. So a
consumer orders its indexes as it usually asks, and with no index fitting,
DD starts from the rarest tag, still fast whenever a condition is selective.

## Who decides what a trait says

Some traits are facts (format, size), some judgments (art style, auburn or
red hair). One owner per type decides: for a per-app store the app itself;
for a shared store like the park store, whoever owns the registration and
curates it (`types.cr`, curio, Thomas), with standard values, custom values
and `promote` as the shared vocabulary. Traits stay as close to fact as they
can: what the thing is, not how it feels. A consumer's own reading of an
asset belongs to its use: the boardwalk's tree is festive and the midway's
spooky, so that's in each link's data, not the asset's traits.

## What a view describes

A view describes the picture's subject. Most of Overlore's pictures are
scenes (rooms, backdrops, panels, hero shots), so their views stay empty;
portraits record theirs (front, level, as asked), and a hero shot could
record the hero's framing (from behind, a profile) if something ever reads
it. Overlore may later keep several views of a hero as references, so a
panel staged from behind uses the back view (`@overlore`, 2026-10-09).

## Open questions for Thomas

None left from the first round; ready to review as a whole.
