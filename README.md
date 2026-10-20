# DataDungeon

DataDungeon stores and serves typed assets. It records searchable tags and
media-specific metadata, applies image storage policy (PNG or TIFF to WebP,
and tiled TIFF masters), and resolves stored objects through a `Storage`
adapter.

## Asset identity

Every asset type is registered before anything of it is stored
(`register_type`), naming the traits that identify it, most important first.
Traits are ordinary tags. DataDungeon derives the asset's `key` from them:
the asset type, then the trait values in that order, joined by dots.

```
portrait.golden.pg.f.human.tan-skin.red-hair
```

The key is an index, not a name: it finds the assets whose traits are these,
and any number can share it (takes of one voice line, say). Every store adds
an asset; what a pool is (which traits an application asks with) is the
application's call. The asset's id, and its bytes' SHA-256, are what name
one asset durably, never the key. The leading `group_traits` form the type's
group: the wider set of candidates that exact checks and ranking work
within. Because a trait's position says which trait it is, a lookup on
leading traits is a prefix match (`portrait.golden.pg.f.`), one index range
scan, at any depth.

A type's name says what the asset is, from DataDungeon's list
(`DB::STANDARD_TYPES`, served by `GET /vocabulary`), so another app can
tell what it is: `drop` (a place, the set things stand in front of),
`plug`, `placard`, `scrim`, `prop`, `texture`, `icon`, `map`,
`automaton`; `speech`,
`dialogue`, `music`, `ambience`, `effect`, `recording`; `prose`,
`script`, `transcript`, `log`; `document`, `data`; `set`, `figure`,
`motion`; `sequence`, `font` (see `DESIGN-types.md`). An app tells its own
kinds of one type apart with the shared tag `subtype`, its values the app's
own words (`room`, `door-view`), and registers each type it uses with the
traits its lookups need, `subtype` among them where it looks up by kind. The list came in 0.15.2; apps move
their own types onto it one at a time (`rename_type`), and once all have,
`register_type` will take only these names.

Keys are canonical: every trait is present, in the registered order, with an
empty segment for a trait the asset lacks (`portrait.golden.pg..human`). Values are
normalized for matching (Unicode case folding and NFC; letters and digits
kept, apostrophes dropped, and every other run of punctuation, symbols or
spaces turned into `-`, so `Zork III: The Dungeon Master` becomes
`zork-iii-the-dungeon-master`), and the stored trait tags are normalized the same way, so a
value never contains a dot. `labels` add a suffix to traits whose values alone
would read ambiguously, such as several colours (`tan-skin`, `red-hair`).
Normalization can't make different words equal, so the application must spell
each value consistently.

`sets` names traits whose value is a set, such as a poster's colours. The
application passes the members comma-separated, in any order; DataDungeon
normalizes each, drops duplicates and sorts them, so `"Red, blue, red"` is
stored and keyed as `blue,red`. A set matches only the same set. Normalizing
turns commas inside a value into `-`, so a key's only commas separate set
members, and prefixes still stop at dots. Set traits can't be labelled.

```crystal
db.register_type("poster", pool_traits: %w[style colors], sets: %w[colors])
db.store("poster", {"style" => "art deco", "colors" => "Red, blue"}, ...)
# key: poster.art-deco.blue,red
```

A tag may be marked `custom` when its value isn't one of the application's
standard choices. Custom values are keyed like any other; `custom_values`
counts them and `promote` turns one into a standard choice without changing
any key.

```crystal
db = DataDungeon::DB.new("assets.db", cache_root: "asset-files")
db.register_type("portrait",
  pool_traits: %w[art-style rating gender race skin hair-color],
  group_traits: %w[art-style rating gender],
  labels: {"skin" => "skin", "hair-color" => "hair"})

traits = {"art-style" => "silver", "rating" => "pg", "gender" => "f",
          "race" => "ape", "skin" => "purple", "hair-color" => "red"}
record = db.store("portrait", traits, custom: %w[race],
  source_path: "portrait.png",
  content_type: "image/png",
  description: "A purple ape with red hair, facing left.",
  generated: true,
  generator: "runware:flux-dev-v1",
  recipe: DataDungeon::Recipe.new("picture", settings: {"model" => "flux-dev", "size" => "512x512"},
    prompt: image_prompt),
  image: DataDungeon::ImageMeta.new(compression: "normalize", target_format: "webp")
)
record.key                                          # "portrait.silver.pg.f.ape.purple-skin.red-hair"

db.find_pool("portrait", traits)                    # every trait equal
db.find_pool("portrait", traits, custom: %w[race])  # every trait equal but race; rank race yourself
db.find_group("portrait", traits)                   # the group traits equal
db.find_group("portrait", traits, 4)                # the first four traits equal
db.find_pool(record.key.not_nil!)                   # by the key alone
db.find_group("portrait.silver.pg.")                # by a key prefix alone
found = db.find("portrait", traits, custom: %w[race])
found.pool                                          # as find_pool with custom:
found.group                                         # the rest of the group
db.custom_values("portrait", "race")                # {"ape" => 1}
db.promote("portrait", "race", "ape")
db.get_by_id(record.id)
db.get_with_meta_by_id(record.id)
db.path_for(record)
```

A key already in hand is enough: `find_pool(key)`, `get(key)` and
`get_with_meta(key)` take one, and `find_group(prefix)` a key prefix ending in
a dot (`group_key_for` gives one). These, and the trait forms without
`custom:`, are single index lookups. Asset type and trait names are lowercase
letters and digits joined by `-` or `_` (a trait name starts with a letter),
so they never contain a dot. With `custom:`, the traits before the first
custom one narrow the candidates by prefix and the rest are checked against
each candidate's tags.

`get`, `get_by_id` and `get_with_meta` count a use of what they return
(`use_count`, `last_used_at`; pass `touch: false` for a check that isn't a
use). Uses are counted in memory and written a hundred at a time, if the
write lock is free, and the rest at `close`, when the process exits
(including a Kemal server's shutdown on SIGINT or SIGTERM), or by
`flush_usage`, so a read never waits on the disk or on another process's
write. Until then a
record shows the counts as last written, and a process killed outright
loses those not yet written: they're a hint for eviction, not a record of plays.

`rename_tag(type, from, to)` renames a tag on all of a type's assets and in
its registration; keys hold values, not names, so they normally stay the same.
`rename_type(from, to)` moves a type's assets and registration to a new name,
re-deriving their keys; if `to` already has assets, they join it under its
registration. Once nothing of `from` is left it changes nothing, so an app
can keep the call in its start-up until every copy of its store has moved.

The registration is stored in the database. Registering a type again with
the same definition changes nothing, and so does changing only what keys
don't hold (facets, scales, colors, cycles, weights, match fields) beyond
saving it. Other traits, order, group, labels or sets raise unless given
`rekey: true`, which re-derives the keys of its assets from their tags.
A store shared by several applications should register its types in one
place.

## Takes, superseding and retiring

`get(asset_type, traits)` and `get_with_meta(asset_type, traits)` return the
preferred current asset with those traits: the highest `rating` (none counts
as 0), then the newest by `made_at`, when the content was made, which a
batch or an import passes (`store(…, made_at: time)`) and which defaults to
when it was filed. A flagged asset is out of play: `get` and best matches
skip it, while listings still show it for review. `update_asset(id, rating:,
flagged:)` sets both; an application keeping people's reactions writes their
total into `rating` and a report into `flagged`. `find_pool` returns every
current one.

Naming the take a new one replaces keeps the history tidy:
`store(…, supersedes: old.id)` (or `supersede(new_id, old_id)`) retires the
old take, links `new supersedes old`, and copies the old take's other links
to the new one, data and all. A retired asset is kept, but leaves `get`,
listings, counts, best matches and search; it's still there by id.
`retire(id)` retires an asset with nothing replacing it, a soft delete, and
`reinstate(id)` makes one current again (if a take superseded it, it
supersedes that take in turn). Nothing retires anything by itself, and
nothing is deleted until the application prunes:
`prune(asset_type, keep_last: 2, retired_before: time)` deletes a type's
retired assets, keeping each key's last few or the recent ones.

```crystal
old = db.get("voice", line)
take = db.store("voice", line, bytes: audio, content_type: "audio/mpeg", supersedes: old.try(&.id))
db.reinstate(old.not_nil!.id)   # the old take back
db.prune("voice", keep_last: 3)
```

An asset is its bytes, so storing bytes its type already holds raises
`AlreadyStored` (with the holder's `asset_id`): change that asset's traits
with `update_asset`, or bring a retired one back with `reinstate`. Storing
them again with the same traits, as a retry does, just returns the asset.

## Indexes per consumer

A type's own index serves the order its owner registered. An application
asking in another order keeps its own index: it says who it is when it opens
the store, and registers an index with a name and the traits it usually asks
by, most selective first.

```crystal
db = DataDungeon::DB.new(path, consumer: "cattacula")
db.register_index("voice", "lines", traits: %w[bit beat voice fmt])
db.list_assets("voice", {"bit" => "b1", "beat" => "0"})   # one range of that index
```

Applications just ask with traits. A lookup by tags counts where it could
start, capped so counting is cheap: the range of each index (the type's own,
or any consumer's) whose leading traits the query fixes, and each tag's
rows. It starts from the smallest and checks the other tags on each asset
there. Each asset has a key in every index of its type, kept current on
every write. A consumer changes only its own indexes: registering one again
changes nothing, other traits raise unless `rekey: true`, and
`unregister_index` drops one. `indexes(type)` lists every consumer's.

Every key is in one table, the type's own among them, so an application
never builds one: it registers the types it stores, looks assets up by
traits, and refers to one asset by its id. Before 0.12 a key was a column
of the assets table (`pool_key:`). 0.15 no longer converts a store from
before 0.12: open it read-write once with 0.14 first, which does.
`description` is the asset in words, what a picture shows or a clip says,
for people and for search. It's the asset's own and not its prompt: what a
generator was sent is the recipe's (below). `generated` records whether the
asset was generated, `generator` what made it, and its recipe how. An asset
added by hand (`POST /assets`) isn't generated and has no recipe; its
description is whatever words it's given.

`DB#store` stores objects by content: each object's storage key is the SHA-256
of its bytes under a directory named for the first two hex characters, with an
extension from its content type (`ab/ab12….webp`). Identical bytes are stored
once and shared by every asset that holds them (of different types), and
deleting or pruning an asset unlinks its object only when no other asset
still uses it. An asset's `media` comes from its content type unless given: its
top-level type (image, audio, video, text, model, font), JSON, XML and YAML
counting as text, and anything else (a PDF, raw bytes) `data`.
Existing rows keep the keys they were stored under. `DB#store_asset`
indexes a file whose path the caller already owns. Existing SQLite asset tables
are upgraded when DataDungeon opens the database.

To move such files into the store, `DB#outside_store` lists the rows recorded
by an absolute path, and `DB#adopt(record)` copies one row's file to its
content-addressed key and points the row at it, keeping its id, tags and
metadata. The original file stays where it is, for the application to remove.

```crystal
db.outside_store.each do |old|
  moved = db.adopt(old)   # old.file_path → moved.file_path (ab/ab12….webp)
rescue File::NotFoundError
  # the file is gone; the row is left as it is
end
```

## Recipes

A recipe says how an asset was made, in one shape every app shares, so an
asset one app made can be read by another (`DESIGN-recipes.md`): its form
(`picture`, `speech`, or `text` from a chat model), the settings it was
made with, what its provider was sent, the named wordings that went into
that, and what's its own: seed, cost, when, and the files it was made from,
by hash.

```crystal
rating = db.rating_text("pg")              # "Suitable for older children: …", named dd:pg@<version>
rules = DataDungeon::Recipe.wording("rules", "overlore:house", "No text unless the description asks for it.")
style = DataDungeon::Recipe.wording("style", "overlore:silver-comic", "Silver Age comic: bold black ink outlines.")
prompt = [rating.text, rules.text, "Full body, head to toe.", style.text, "A tall elf with red braids."].join(" ")
recipe = DataDungeon::Recipe.new("picture",
  settings: {"camera" => "mj:camera:flare", "model" => "flux-dev", "steps" => 4},
  prompt: prompt, wordings: [rating, rules, style],
  seed: 7, cost: 0.04, cost_basis: "reported: runware", generated_at: Time.utc,
  references: [portrait.file_hash.not_nil!])
db.store("panel", tags, bytes: png, content_type: "image/png", recipe: recipe)

narrator = DataDungeon::Recipe.wording("style", "owl:narrator", "Warm, unhurried, a storyteller by a fire.")
spoken = DataDungeon::Recipe.new("speech", settings: {"model" => "gpt-4o-mini-tts", "voice" => "fable"},
  prompt: "Once, there was a castle.", instructions: narrator.text, wordings: [narrator])

db.recipe(id)                     # => Recipe?, wordings read back as "overlore:silver-comic@3f9a2c71b0"
db.with_text("style", "overlore:silver-comic")  # the assets using any of its wordings;
                                                # "…@3f9a2c71b0" for one wording
db.with_text("rating", "dd:pg")                 # everything given DataDungeon's words for PG
db.list_assets(texts: {"style" => "overlore:silver-comic"})  # the same as a listing filter
db.named_texts("style", "overlore")  # [{name, version, text}]
db.set_recipe(id, recipe)             # give an asset made before 0.13 its recipe
db.add_wordings(id, [rating])         # name words a stored recipe was sent but didn't name
db.vocabulary                         # the shared tags (rating, subtype) and their values
DataDungeon::DB::STANDARD_TYPES       # DataDungeon's asset types: name, title, media, what it is
```

- **What was sent:** `prompt` is the text the provider got: a picture's
  prompt, the words a voice speaks, a chat model's input. `instructions` is
  the provider's second input beside it, a voice's or a chat model's
  instructions; a picture has none. The app writes them, and DataDungeon
  keeps them word for word. A step without a prompt (a matte, a depth map)
  has the form `""`, and an asset made in steps `Recipe.in_steps([edit, matte])`.
- **Wordings** are the words an app reuses, kept once in the store: each has
  a kind (`style`, `rating`, `rules`, `framing`, `character`, `theme`, …),
  a name, `owner:name`, the owner being the app (`DB.new(…, consumer:)`) or
  `dd` for DataDungeon's own, and its words. A recipe lists the wordings it
  used, and the store refuses one whose words aren't in its prompt or
  instructions word for word, before anything is written. Only the owner
  adds a wording under its name; any app uses the wordings as they are.
- **A version is the words' hash,** the first 10 hex characters of their
  SHA-256, so `overlore:silver-comic@3f9a2c71b0` is the same words in every
  store. A wording is never changed or deleted (the store refuses it, in
  the sqlite3 shell too): new words are a new version, a rename a new name.
- **No purposes** (Thomas, 2026-10-17): 0.13 and 0.14 let a name add one,
  `owner:name/purpose`, so one style could be worded once for figures and
  once for places. That difference is framing, which has its own part, so
  0.15 removed it: a name with a `/` is refused. The first read-write open
  by 0.15 drops a stored wording with a purpose that nothing names any
  more, and makes one still named a version of its plain name
  (`overlore:silver-comic/place@3f9a2c71b0` becomes
  `overlore:silver-comic@3f9a2c71b0`, the same words), refusing to open if
  two would become one.
- **There are no standard styles** (Thomas, 2026-10-17): each app names,
  words and tags its own (`overlore:silver-comic`, kind `style`). Styles
  shared between apps will be the hub's to coordinate, later: a lookup of
  what each store uses, so one app can adopt another's style and share.
- **A rating's words are DataDungeon's too,** one wording for every form,
  saying what's suitable rather than listing what's forbidden:
  `db.rating_text("pg")`. A picture takes them with its rules, a chat text
  with its instructions; speech needs none, since its rating applies when
  its text is written.
- **A prompt's parts,** in the order we recommend (advice, not a schema:
  each prompt is the app's): the rules (the fixed ones, the same for every
  picture, such as the rating's), framing (how much is in frame), the style,
  theme (mood included), subject, description, staging
  (where each figure is, and the view), light (the standing light, from the
  place), and last the directives (this picture's own: its kind's rules,
  and what an edit or a shot from a reference changes and keeps), where the
  end holds what the picture is for. `ViewWords` (below) puts a view or a
  light in words.
- **Cost** is in US dollars, and `cost_basis` says how it was reached: the
  service's own bill (`reported: runware`), a rate table
  (`priced: arcana-ai 0.5.2`), or `estimated`.
- **Every text is stored once,** in one table: a prompt sent twice, a
  wording, an asset's description. Settings are stored once too.
- `AssetRecord#has_recipe?` (JSON `has_recipe`) says whether there's one to
  ask for; `GET /assets/:id/recipe` returns it over HTTP.

Before 0.13 an asset's `generation` was free-form JSON on its row. The first
read-write open by 0.13 moves each one, as it is, into a table of old
records and drops the column, since only each app can read its own;
`generation` keeps reading and writing that table through 0.13. Descriptions
move into the texts table the same way. Each column is dropped only after
every value is checked to read back the same from where it went; otherwise
the open fails and leaves the store as it was. It's one way: an older
DataDungeon can't open the store afterwards.

The first read-write open by 0.14 turns every recipe stored before it into
what was sent: a step's `prompt_sent`, or else a picture's fields joined in
0.13's order (rules last); speech's text, with its style as the
instructions; a chat text's description, with its instructions. Each named
field becomes one of its wordings, versioned by its words. Every step is
compared with its fields before a column goes; if any differs the open
fails and leaves the store as it was. 0.14 kept the fields, in
`recipe_fields`, no longer written; 0.15 drops them. It adds the
vocabulary, the ratings with DataDungeon's words for each (`dd:pg`). It's
one way:
upgrade every program that opens a store (an app and its `dd-serve`)
together.

`set_recipe` keeps what an asset has: it refuses to replace a recipe
without `replace: true`, and keeps the old `generation` record unless given
`drop_generation: true`, once the app is sure the recipe holds everything
it said. `add_wordings(id, wordings, step: 0)` names words a stored step
was sent but didn't name, such as an app's rating words on pictures made
before it named them. Only the new wordings are checked, as a new recipe's
are, and what the step named stays as it was stored. A text an asset or a recipe uses can't be deleted (a foreign key
refuses it), and DataDungeon deletes none.

## Image fields

A picture's facts that are numbers live in `image_meta` columns, comparable
by range, rather than in its key (see `DESIGN-image-fields.md`). `nil` means
not known.

**DataDungeon measures** each picture it stores: `width` and `height`,
`transparent` (any pixel not fully opaque), `dominant_color` (the colour
most of the visible picture is, `#rrggbb` in JSON), the box around the
visible pixels (`content_x/y/w/h`), and for an animation its frames
(`animation`: count, duration, loops). PNG and WebP, still or animated, and
TIFF with `data_dungeon/tiff` (below), give all of these; a GIF its size and
frames and a JPEG its size, from their headers. `measure_images(type, all:)`
measures pictures stored before (each object is read, which for a bucket is
a download). Before 0.15.4 a 16-bit PNG with no gamma chunk was read as
linear light, too bright, and wrongly when interlaced; `all: true` measures
such pictures again.

**The application sets** what it asked the generator for: the view (where
the camera stands, a unit vector in the thing's frame, and its roll), the
light (where it comes from, in the picture's frame), the anchor (0 to 1
across and down: the point that sits on the ground), and the thing's real
size in metres (`world_width`, `world_height`, `world_depth`). Views and
light are written readably, as `Direction`: `side` front or back, `yaw`
toward the right (+1) or left, `pitch` from above (+1) or below, in quarter
turns. A profile facing left in the picture shows the thing's right side,
yaw +1. Each view has a name, `back-left` or `front from-above` or
`top-down`, which is also a search word; `view_counts(type)` counts a
type's pictures by each word of their names (kept as the tag counts are,
so instant), and the `image_views` SQL view shows views readably at the
sqlite3 prompt. Tag names starting with `@` are DataDungeon's.
`ViewWords.view(direction)` and `ViewWords.light(direction)` put a view or
a light in words for a prompt ("a three-quarter view from its right, from
slightly above", "lit from high above and from the left"): `@mj`'s camera's
words, lowercase fragments for the caller to punctuate, saying what was
asked, never what was drawn.

```crystal
db.store("prop", {"thing" => "lamp"}, bytes: png, content_type: "image/png",
  image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("back", -0.5),
    light: DataDungeon::Direction.new("front", -0.5, 0.5), anchor_x: 0.5, anchor_y: 1.0, world_height: 3.0))
db.update_asset(id, image: DataDungeon::ImageMeta.new(world_width: 0.4))   # only the fields given
db.list_assets("prop", image: DataDungeon::ImageFilter.new({"world_height" => {2, 4}},
  view: DataDungeon::Direction.new("front", 0.5), view_within: 30.0))       # a range, a view within 30 degrees
db.list_assets("prop", image: DataDungeon::ImageFilter.new(direction: "back-left"))
```

An animation's fields describe its first frame; `set_keyframes(id, [...])`
records what changes after it, as checkpoints holding only the fields that
change (`ImageKeyframe`), each gliding from the one before or `held`.
Neighbouring views may be at most 90 degrees apart, with a checkpoint
wherever something turns, so a filter matches a field at the first frame or
at any checkpoint exactly ("does it ever show the back?"). DataDungeon
measures the content box at each checkpoint of an animated WebP.

## TIFF masters

`require "data_dungeon/tiff"` adds TIFF, through libtiff 4.5 or later, which
the application then links (`dd-serve` does). Without it, nothing links
libtiff. With it, DataDungeon:

- **measures a TIFF** as it does a PNG, whatever layout, compression or
  depth libtiff reads, and stores it as `.tif`;
- **stores a TIFF or a PNG as a master,** asked with
  `ImageMeta.new(compression: "normalize", target_format: "tiff")`: 8 bits
  a channel, in 64×64 tiles, deflate-compressed, with alpha only when a
  pixel isn't opaque. The pixels stay as they are, but 16-bit samples are
  rounded to the nearest 8-bit level (Thomas, 2026-10-20: 8-bit is enough).
  The same pixels always make the same file, and only the first page is
  kept, so export a flattened picture. An edit changes only the tiles it
  touches, so on transfs a small stroke costs 2.6 MiB over 37 pictures,
  against PNG's 32.7 (transfs-rs's chunk study);
- **makes a picture's WebP,** a TIFF's or a PNG's: `store_webp(id, tags)`
  stores it as a new asset of the picture's type, linked `derived-from` it
  with its quality in the link's data. It takes the picture's tags with
  these over them, its description and rating, and the image fields the
  application sets. It isn't permanent, since it can be made again, and
  storing it again with the same tags returns it.

```crystal
require "data_dungeon/tiff"

master = db.store("prop", {"venue" => "boardwalk", "thing" => "barrel", "fmt" => "tif"},
  bytes: File.read("barrel.tif").to_slice, content_type: "image/tiff",   # as GIMP exports it
  image: DataDungeon::ImageMeta.new(compression: "normalize", target_format: "tiff", anchor_x: 0.5, anchor_y: 1.0))
webp = db.store_webp(master.id, {"fmt" => "webp"})                       # quality: 85
```

An `.xcf` (`image/x-xcf`), GIMP's own format, is stored as given, for the
odd original kept in it. DataDungeon can't read one, so it isn't measured
and has no WebP (Thomas, 2026-10-20).

## Tracks

A track is what a tool measured of a sound or a video over time, kept with
it: a take's word times and mouth cues, so they travel with the take and
any app can lip-sync it without running the tools again (0.15.3). Each
cue runs from `start_ms` to `end_ms`, in time order.

```crystal
cue = DataDungeon::TrackCue
db.set_track(take.id, "words", [cue.new(0, 180, "My"), cue.new(180, 520, "friend!")], tool: "whisper-1")
db.set_track(take.id, "mouth", [cue.new(0, 60, "X"), cue.new(60, 120, "B")], tool: "rhubarb 1.14.0 --dialogFile")
db.tracks(take.id)            # each track's name, tool, made_at and cues
db.track(take.id, "mouth")    # one, or nil
DataDungeon::DB::STANDARD_TRACKS  # the shared names: words, mouth
```

- **`words` and `mouth` are shared:** when each word is spoken, its value
  the word with its punctuation (`friend!`), as written when the tool
  aligns a known text (a voice engine's own timings, a forced aligner) and
  as heard when it transcribes (Whisper); and the mouth's shape, its values
  the tool's (Rhubarb Lip Sync's A to H, and X at rest). Other names are an
  app's own (`words-heard`, for a transcription kept beside the text's).
- **A track names its tool,** with its version and any options that change
  its result (`rhubarb 1.14.0 --dialogFile`), so a better one can redo it:
  setting a track replaces the one of that name whole.
- **Only the start order is checked:** a cue may last no time, and may run
  past the next one's start.
- **They're measured from the recording, not the script:** a retake has
  its own. Tracks go when their asset does.

## Storage

`cache_root:` stores objects on local disk (`LocalStorage`). For an
S3-compatible bucket (Cloudflare R2, Garage, MinIO or AWS S3), require
`data_dungeon/s3`, add `awscr-s3` to your shard.yml, and pass an
`S3Storage`:

```crystal
require "data_dungeon/s3"

storage = DataDungeon::S3Storage.r2(ENV["R2_ACCOUNT_ID"], "game-assets",
  access_key: ENV["R2_ACCESS_KEY_ID"], secret_key: ENV["R2_SECRET_ACCESS_KEY"],
  public_url: "https://assets.example.com")   # optional: a domain or CDN in front
db = DataDungeon::DB.new("assets.db", storage: storage)

db.read(record)       # the object's bytes, from whichever storage
db.open(record) { |io| IO.copy(io, response) }   # streamed, not loaded whole
db.path_for(record)   # a URL: under public_url, or presigned without one
```

`S3Storage.new(bucket, endpoint:, region:, access_key:, secret_key:)` reaches
any other S3-compatible service. Objects are uploaded with their content type
and immutable cache headers, since content-addressed objects never change.
Connections are kept alive, and requests the service turns away for load
(429, 5xx) are retried with backoff. Give a store a bucket, or a `prefix:`
in one, of its own, or share it as below: `check_consistency` treats every
object under it as the store's.

With remote storage, lookups don't confirm that each record's object still
exists, since that would cost a round trip per read; `check_consistency` finds
any drift. Read objects with `DB#read`, or stream them with `DB#open`, rather
than opening `path_for`, which is only a file path for local storage.
`DB#find_by_hash` finds the assets holding given bytes, by their SHA-256.

Stores can share one bucket, each object kept once by its hash, with
`shared: true` on the storage (`DD_SHARED_STORAGE=1` for dd-serve). A store
can't know whether another still uses an object, so DataDungeon never
deletes one there: deleting or pruning an asset removes its row only, and
`vacuum` won't delete objects. It also writes each object it stores even
when it's there, so the object's date is when a store last relied on it.
Clearing objects no store uses is for a program that asks every store for
`object_keys` (`GET /objects`) and keeps whatever any of them names, and
anything written since it began.

Each store is one owner's: the app that opens it (`consumer:`) and its
`dd-serve` (Thomas, 2026-10-16). An app that wants another store's assets
copies the records into its own, with a `copied-from` link saying where
from, and the bytes stay one object in the shared bucket. Pictures aren't
expected to move between apps (Thomas, 2026-10-17): each app names and
words its own styles for its own models, and reuse pays within an app.

Run the specs with `crystal spec`. The S3 specs need a server:
`scripts/garage-test` runs them against a throwaway single-node
[Garage](https://garagehq.deuxfleurs.fr) (the `garage` binary on PATH).

## Browsing, curating and the HTTP API

`asset_types` lists every type with its count of current assets
(`retired: true`, of retired ones); `tag_keys(type)` a type's tag names and
`tag_values(type, key)` one tag's values, each with a count. `list_assets`
gives a page of assets, newest filed first, of one type or of all, filtered
by tags, links and search words. Listings and counts take current assets,
or with `retired: true` retired ones, `nil` both. `offset` numbers pages (about
2 ms to skip 100,000 assets); to walk through them all, pass the last
asset's id as `before` for the next page. `count_assets` counts them all:

```crystal
db.list_assets("prop", {"venue" => "boardwalk"})
db.list_assets(q: "cattacula night")          # the type or tag values (or parts), any order
db.list_assets(q: "catt* night")              # catt* matches the start of a word
db.list_assets(q: "red-hair")                 # a labelled trait, only as keys spell it
db.list_assets(links: {"used-by" => "boardwalk"}, limit: 50, before: last_id)
db.list_assets(links: {"used-by" => "boardwalk.*"})   # boardwalk and names under it
db.list_assets("prop", unlinked: "used-by")   # what nothing uses
db.list_assets("voice", retired: true)        # what was retired or superseded
db.list_assets(file_hash: hash)               # the assets holding a file, such as a recipe's reference
db.list_assets(description_hash: rec.description_hash)   # every asset sharing a description
```

Search words come from a full-text index (SQLite FTS5) of each asset's type
and tag values, kept current as assets change. `update_asset(id, tags:,
description:, flagged:, rating:, permanent:)` edits an asset in place
without storing its bytes again; a rating and a flag change which asset
`get` prefers. A blank description clears it. Assets can share one
description (the same `description_hash`, its SHA-256, the same in every
store); a new one is that asset's alone, unless `everywhere: true` gives it
to every asset that shared the old one, as for a typo. The old wording is
kept, since a recipe may record it as what a provider was sent.

`link(from, rel, to, data)` relates an asset to another asset
(`derived-from`) or to a name (`used-by`, `"boardwalk.holidayland"`),
outside its key, so the link can change freely. Names nest under their user
with dots. `data` is JSON kept with the link, such as how the asset is
placed in that use; linking again replaces it. `links_from` and `links_to`
list them, and name filters take `boardwalk.holidayland` exactly,
`boardwalk.*` for it and every name under it (not `boardwalk-annex`), or
`boardwalk*` for every name starting so. Links go when either asset is
deleted; a `supersedes` link is made by superseding. Opening with
`DB.new(path, storage, read_only: true)` changes nothing: no schema setup, no
re-keying, writes refused by DataDungeon (`ReadOnlyError`) and by SQLite.

`require "data_dungeon/http"` adds `DataDungeon::API`, a JSON API over a DB
for a browser elsewhere. It's an `HTTP::Handler`, so an application can
mount it, or `dd-serve` (`shards build dd-serve`) runs it alone beside the
database, configured by `DD_*` environment variables (see
`src/dd_serve.cr`). Reads need the read token, writes the write token
(`Authorization: Bearer …`); without a write token there are no writes, and
`dd-serve` opens the database read-only.

```crystal
api = DataDungeon::API.new(db, read_token: ENV["DD_READ_TOKEN"], write_token: ENV["DD_WRITE_TOKEN"]?,
  prefix: "/dd")
HTTP::Server.new([api, app_handler])
```

| | |
|---|---|
| `GET /types` | types, counts (current and retired), registrations and indexes |
| `GET /types/:type/tags[/:key]` | tag names, or one tag's values, with counts |
| `GET /types/:type/views` | how many pictures are seen from each named direction |
| `GET /assets?type=&q=&tag.<key>=&link.<rel>=&unlinked=&limit=&page=&before=&count=1` | a page of assets with their tags, and `next` (`&meta=1`: each picture's fields and view too) |
| `…?retired=only` or `=include` | retired assets, or all, in listings and counts |
| `…?field.<name>=<low>..<high>&view=back-left&view.side=&view.yaw=&view.pitch=&view.within=` | by picture fields (and `light.` alike) |
| `…?file_hash=&description_hash=&text.<kind>=<owner:name>[@<version>]` | by file, by shared description, by a wording a recipe used |
| `GET /assets/:id`, `/assets/:id/object`, `/assets/:id/links` | an asset with its tags, metadata and links; its bytes; its links |
| `POST /maintenance/check` | the consistency report |
| `GET /objects` | every object key the store's rows use, for clearing a shared bucket |
| `GET /vocabulary` | the shared tags and their values, with their titles; each rating with DataDungeon's words for it; DataDungeon's asset types; the shared tracks |
| `GET /assets/:id/tracks[/:name]` | its tracks, or one (404 when it has none of that name) |
| `POST /assets` | a file added by hand, as `multipart/form-data`: `file` (its `Content-Type` the asset's) and `asset`, JSON `{type, tags, custom, description, permanent, made_at, supersedes, image}`; stored as not generated, with no recipe; `image` as `PATCH` takes it, plus how to store the file (`{"compression": "normalize", "target_format": "tiff"}` for a TIFF master); 409 with `asset_id` when its type already holds the bytes (write token) |
| `POST /assets/:id/webp` | `{tags, quality}`: the picture's WebP, as an asset of its own (`store_webp`); 409 as above (write token) |
| `PATCH`, `DELETE /assets/:id` | edit (with `image` fields, views readably, and `everywhere` for a shared description) or delete (write token) |
| `PUT /assets/:id/keyframes` | an animation's checkpoints (write token) |
| `PUT /assets/:id/tracks/:name` | `{tool, cues: [{start_ms, end_ms, value}]}`: a track, replacing the one of that name (write token) |
| `POST`, `DELETE /assets/:id/links` | link (with `data`) or unlink (write token) |
| `GET /assets/:id/recipe` | how it was made (404 when it has no recipe) |
| `POST /assets/:id/retire`, `/assets/:id/reinstate` | retire or reinstate (write token) |
| `POST /maintenance/prune` | `{type, keep_last, retired_before}`: delete retired assets (write token) |
| `POST /maintenance/measure` | `{type, all}`: measure stored pictures (write token) |
| `POST /types/:type/promote`, `/maintenance/vacuum` | (write token) |

An asset in JSON carries its `key` (`pool_key` before 0.12, and both names
through 0.12), `rating`, `flagged` and `permanent`, which `PATCH` sets,
`description_hash`, and `has_recipe`.

## Best matches

`require "data_dungeon/matches"` (with the `usearch` shard and its C
library) adds `DataDungeon::MatchIndex`: for a registered type, the assets
closest to what was picked, even when none matches every pick, ranked by
`score = Σ weight × similarity` over the traits asked for.

```crystal
db.register_type("portrait", pool_traits: %w[art-style rating race hair skin items],
  scales: {"rating" => %w[g pg r x]},  # ordered: near values count as close
  colors: %w[hair skin],               # CSS names or hex codes, by appearance
  sets: %w[items],                     # by shared members
  weights: {"art-style" => 2.0})       # default weights (else 1)
index = DataDungeon::MatchIndex.new(db)
index.best_matches("portrait", {"art-style" => "golden", "rating" => "pg", "hair" => "crimson"},
  require: %w[art-style rating],       # must match exactly
  weights: {"hair" => 3.0}, limit: 10) # => [BestMatch(asset, score), …], best first
index.similar(asset_id, limit: 10)     # by an asset's own traits
index.close
```

`cycles` lists values that go round a circle (`{"time" => %w[dawn day dusk
night]}`), so night's nearest are dusk and dawn, and day is furthest.
`match_fields: %w[view light roll dominant-color]` matches pictures on
those image fields too: views and light by the angle between them (nothing
from 90 degrees apart), colours by appearance. A query picks them like
traits: `{"view" => "back-left", "dominant-color" => "#aa3311"}`, a view
also as `"front,0.5,0"` (side, yaw, pitch).

Other traits are words, alike only when equal; a color name DD doesn't
know matches only itself. What must match and what matters most are the
application's to say: nothing is required, and every trait weighs 1,
unless given.

Each asset has a vector built from its tags, one block per trait, whose
inner product with a query's approximates the score; USearch finds 200
candidates in one file per type (beside the database), and those are
scored exactly. Weights travel with the query, so changing them rebuilds
nothing; changing a type's traits, scales or colors rebuilds its file from
the tags. One process owns a store's match files (a lock) and, before each
query, catches up on every process's writes from the database's change
log. `DataDungeon::API` answers `GET /types/:type/matches` and
`GET /assets/:id/similar` when given one, as `dd-serve` is. See `DESIGN-best-match.md` and `bench/best_match.cr`: at
200k assets a query takes about 1.4 ms (3.4 ms with required traits), with
the exhaustive top 10 found every time.

## Semantic asset search

Semantic search is an optional entry point. Applications using it need a
`memo` dependency in their shard file. It uses Memo's tables in the same
SQLite database and keeps the USearch index beside that database. Memo embeds
the asset's `description` plus only the tag keys you select. Keep exact
constraints such as `art_style` and `rating` in the `tags:` search filter;
do not add hashes, IDs, or generator bookkeeping to the embedding text.

```crystal
require "data_dungeon/semantic"

db = DataDungeon::DB.new("assets.db", cache_root: "asset-files")
semantic = DataDungeon::SemanticIndex.new(
  db,
  format: "openai",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model: "text-embedding-3-small",
  dimensions: 1536,
  max_tokens: 8191,
  semantic_tag_keys: %w[race gender hair-color hair-texture outfit]
)

semantic.backfill       # queue pre-existing assets; safe to repeat
semantic.process_queue # run from one worker, off the request path
hits = semantic.search("curly-haired adventurer",
  asset_type: "portrait", tags: {"art-style" => "silver"})
hits.each { |hit| puts "#{hit.asset.id}: #{hit.score}" }
db.close
```

A registered type can declare **facets**: named groups of tags embedded
separately from the asset's own embedding, so a search can rank one part of
an asset without the rest diluting it. Each facet is its own Memo source type
(`<asset_type>.<facet>`) in the same store; `description` names the asset's
description.

```crystal
db.register_type("listing", pool_traits: %w[city rooms],
  facets: {"location" => %w[neighborhood view], "interior" => %w[style finishes description]})

semantic.search("sunny loft with exposed brick", asset_type: "listing", facet: "interior")
semantic.search_facets({"location" => "quiet street near a park",
                        "interior" => "sunny loft with exposed brick"},
  asset_type: "listing", key_prefix: db.group_key_for("listing", {"city" => "oslo"}, 1))
```

`search_facets` keeps only assets that have every facet named, and scores
each by its weakest facet, so a close match on one part doesn't make up for a
poor match on another (`hit.facet_scores` has each). It ranks each facet to a
depth of 500 assets by default, so combine within a scope (a pool key, key
prefix or tags) small enough to be ranked whole. Changing a type's facets takes
effect for existing assets at the next `backfill`.

Hits come best first, each with its score, up to `limit`. There is no score
cutoff unless you pass `min_score:`. Scores aren't comparable across
embedding models or query lengths, so choose a threshold per decision: offering
a player choices may need none, while reusing an asset outright needs one
tested against real queries.

Search can also filter by `media` (`"image"`, `"audio"`, `"text"`, `"video"`, …).

For a registered type, `key:` ranks only the assets with one key and
`key_prefix:` only those whose leading traits match, such as every picture of
one portrait:

```crystal
pictures = semantic.search("the hero fights the troll",
  key_prefix: db.group_key_for("picture", {"portrait" => portrait_id}, 1))
```

Those lookups start from the key index, so their cost follows the size of the
pool rather than of the catalogue, and Memo ranks that set exactly.

Once attached, storing an asset queues it for embedding; deleting an asset
removes its Memo entry. Changes to the description or selected tags are
re-embedded by the worker. Until that worker runs, search may still use the
previous embedding. Memo saves the index file on its own policy (after many unsaved changes or a
few minutes) and when the database closes, and it also keeps every vector in
the database: after a crash or a lost index file, Memo replays or
rebuilds the index when it opens, without embedding anything again. `backfill`
queues assets that were never embedded, such as those stored before the index
was attached; it is safe to repeat. An asset with
no description and no selected tags is not indexed. Search returns asset
records without changing usage or match counters, and its query cache stays
in memory. The `generated` flag, generator parameters, and pool and group keys are
stored as metadata but are not embedded.
