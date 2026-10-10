# DataDungeon

DataDungeon stores and serves typed assets. It records searchable tags and
media-specific metadata, applies image storage policy (including PNG to WebP),
and resolves stored objects through a `Storage` adapter.

## Asset identity

Each asset type the application registers names the traits that identify it,
most important first. Traits are ordinary tags. DataDungeon derives the
asset's `pool_key` from them: the asset type, then the trait values in that
order, joined by dots.

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
# pool_key: poster.art-deco.blue,red
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
  description: image_prompt,
  generated: true,
  generator: "runware:flux-dev-v1",
  generation: %({"width":512,"height":512}),
  image: DataDungeon::ImageMeta.new(compression: "normalize", target_format: "webp")
)
record.pool_key                                     # "portrait.silver.pg.f.ape.purple-skin.red-hair"

db.find_pool("portrait", traits)                    # every trait equal
db.find_pool("portrait", traits, custom: %w[race])  # every trait equal but race; rank race yourself
db.find_group("portrait", traits)                   # the group traits equal
db.find_group("portrait", traits, 4)                # the first four traits equal
db.find_pool(record.pool_key.not_nil!)              # by the key alone
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

`rename_tag(type, from, to)` renames a tag on all of a type's assets and in
its registration; keys hold values, not names, so they normally stay the same.
`rename_type(from, to)` moves a type's assets and registration to a new name,
re-deriving their keys; if `to` already has assets, they join it under its
registration.

The registration is stored in the database. Registering a type again with
the same definition changes nothing; a different definition raises unless
given `rekey: true`, which re-derives the keys of its assets from their tags.
A store shared by several applications should register its types in one
place. (`pool:` is deprecated and changes nothing.)

## Takes, superseding and retiring

`get(asset_type, traits)` and `get_with_meta(asset_type, traits)` return the
newest current asset with those traits, newest by `made_at`: when the content
was made, which a batch or an import passes (`store(…, made_at: time)`) and
which defaults to when it was filed. `find_pool` returns every current one.

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

A type's own key serves the order its owner registered. An application
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
`unregister_index` drops one. `indexes(type)` lists everyone's. Every
process writing a store with indexes must be DataDungeon 0.11 or later.

An unregistered type may still pass an explicit `pool_key` (formerly
`canonical_key`), and assets without a key are addressed by ID. Both are
**deprecated**: 0.12 will require registering a type before storing it,
and keep each asset's key in the index table (the type's own order as its
default index), so a caller-built key goes. Register every type you store,
look assets up by traits, and refer to one asset by its id. `description` is the text used to describe an asset; for a
generated image, it holds the prompt. `generated` records whether the asset
was generated. `generator` and `generation` retain provider/model information
and JSON parameters.

`DB#store` stores objects by content: each object's storage key is the SHA-256
of its bytes under a directory named for the first two hex characters, with an
extension from its content type (`ab/ab12….webp`). Identical bytes are stored
once and shared by every asset that holds them (of different types), and
deleting or pruning an asset unlinks its object only when no other asset
still uses it. Existing rows keep the keys they were stored under. `DB#store_asset`
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

## Image fields

A picture's facts that are numbers live in `image_meta` columns, comparable
by range, rather than in its key (see `DESIGN-image-fields.md`). `nil` means
not known.

**DataDungeon measures** each picture it stores: `width` and `height`,
`transparent` (any pixel not fully opaque), `dominant_color` (the colour
most of the visible picture is, `#rrggbb` in JSON), the box around the
visible pixels (`content_x/y/w/h`), and for an animation its frames
(`animation`: count, duration, loops). PNG and WebP, still or animated, give
all of these; a GIF its size and frames and a JPEG its size, from their
headers. `measure_images(type, all:)` measures pictures stored before
(each object is read, which for a bucket is a download).

**The application sets** what it asked the generator for: the view (where
the camera stands, a unit vector in the thing's frame, and its roll), the
light (where it comes from, in the picture's frame), the anchor (0 to 1
across and down: the point that sits on the ground), and the thing's real
size in metres (`world_width`, `world_height`, `world_depth`). Views and
light are written readably, as `Direction`: `side` front or back, `yaw`
toward the right (+1) or left, `pitch` from above (+1) or below, in quarter
turns. A profile facing left in the picture shows the thing's right side,
yaw +1. Each view has a name, `back-left` or `front from-above` or
`top-down`, which is also a search word; the `image_views` SQL view shows
views readably at the sqlite3 prompt.

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
(429, 5xx) are retried with backoff. Give DataDungeon a bucket, or a `prefix:`
in one, of its own: `check_consistency` treats every object under it as
DataDungeon's.

With remote storage, lookups don't confirm that each record's object still
exists, since that would cost a round trip per read; `check_consistency` finds
any drift. Read objects with `DB#read`, or stream them with `DB#open`, rather
than opening `path_for`, which is only a file path for local storage.
`DB#find_by_hash` finds the assets holding given bytes, by their SHA-256.

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
```

Search words come from a full-text index (SQLite FTS5) of each asset's type
and tag values, kept current as assets change. `update_asset(id, tags:,
description:, flagged:, rating:)` edits an asset in place without storing
its bytes again.

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
| `GET /assets?type=&q=&tag.<key>=&link.<rel>=&unlinked=&limit=&page=&before=&count=1` | a page of assets with their tags, and `next` |
| `…?retired=only` or `=include` | retired assets, or all, in listings and counts |
| `…?field.<name>=<low>..<high>&view=back-left&view.side=&view.yaw=&view.pitch=&view.within=` | by picture fields (and `light.` alike) |
| `GET /assets/:id`, `/assets/:id/object`, `/assets/:id/links` | an asset with its tags, metadata and links; its bytes; its links |
| `POST /maintenance/check` | the consistency report |
| `PATCH`, `DELETE /assets/:id` | edit (with `image` fields, views readably) or delete (write token) |
| `PUT /assets/:id/keyframes` | an animation's checkpoints (write token) |
| `POST`, `DELETE /assets/:id/links` | link (with `data`) or unlink (write token) |
| `POST /assets/:id/retire`, `/assets/:id/reinstate` | retire or reinstate (write token) |
| `POST /maintenance/prune` | `{type, keep_last, retired_before}`: delete retired assets (write token) |
| `POST /maintenance/measure` | `{type, all}`: measure stored pictures (write token) |
| `POST /types/:type/promote`, `/maintenance/vacuum` | (write token) |

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

Search can also filter `media: "image"`, `"audio"`, `"text"`, or `"video"`.

For a registered type, `pool_key:` ranks only one pool's assets and
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
