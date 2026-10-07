# DataDungeon

DataDungeon stores and serves typed assets. It records searchable tags and
media-specific metadata, applies image storage policy (including PNG to WebP),
and resolves stored objects through a `Storage` adapter.

## Asset identity

Each asset type the application registers names the traits that identify it,
most important first. Traits are ordinary tags. DataDungeon derives the
asset's `pool_key` from them: the asset type, then the trait values in that
order, joined by dots. The key alone names its pool.

```
portrait.golden.pg.f.human.tan-skin.red-hair
```

Assets with the same pool key are interchangeable. In a pool type
(`pool: true`) many assets share it; otherwise storing under an existing pool
key replaces that asset. The leading `group_traits` form the type's group: the
wider set of candidates that exact checks and ranking work within. Because a
trait's position says which trait it is, a lookup on leading traits is a prefix
match (`portrait.golden.pg.f.`), one index range scan, at any depth.

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
db.register_type("poster", pool_traits: %w[style colors], sets: %w[colors], pool: true)
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
  labels: {"skin" => "skin", "hair-color" => "hair"},
  pool: true)

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

db.find_pool("portrait", traits)                    # every trait equal: interchangeable
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

For a single-best type, `get(asset_type, traits)` and
`get_with_meta(asset_type, traits)` return the one asset for those traits. The
registration is stored in the database; registering a type again with a
different definition re-derives the keys of its assets from their tags. If two
assets of a single-best type then share a key, the most recently used keeps it.

An unregistered type may still pass an explicit `pool_key` (formerly
`canonical_key`, still accepted for now), and assets without a key are
addressed by ID. `description` is the text used to describe an asset; for a
generated image, it holds the prompt. `generated` records whether the asset
was generated. `generator` and `generation` retain provider/model information
and JSON parameters.

`DB#store` stores objects by content: each object's storage key is the SHA-256
of its bytes under a directory named for the first two hex characters, with an
extension from its content type (`ab/ab12….webp`). Identical bytes are stored
once and shared by every asset that holds them, and deleting
or replacing an asset unlinks its object only when no other asset still uses
it. Existing rows keep the keys they were stored under. `DB#store_asset`
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

`asset_types` lists every type with its asset count; `tag_keys(type)` a
type's tag names and `tag_values(type, key)` one tag's values, each with a
count; `list_assets(type, tags, limit, offset)` a page of assets, newest
first. `update_asset(id, tags:, description:, flagged:, rating:)` edits an
asset in place without storing its bytes again. Opening with
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
| `GET /types` | types, counts and registrations |
| `GET /types/:type/tags[/:key]` | tag names, or one tag's values, with counts |
| `GET /assets?type=&tag.<key>=&limit=&offset=` | a page of assets with their tags |
| `GET /assets/:id`, `/assets/:id/object` | an asset with its tags and metadata; its bytes |
| `POST /maintenance/check` | the consistency report |
| `PATCH`, `DELETE /assets/:id` | edit or delete (write token) |
| `POST /types/:type/promote`, `/maintenance/vacuum` | (write token) |

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
