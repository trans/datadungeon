# DataDungeon

DataDungeon stores and serves typed assets. It records searchable tags and
media-specific metadata, applies image storage policy (including PNG to WebP),
and resolves stored objects through a `Storage` adapter.

## Asset identity

An application may supply an opaque `canonical_key` for exact lookup. The
application decides how to calculate it and which assets need one. DataDungeon
indexes `(asset_type, canonical_key)` but does not derive the key from tags.
For a non-pool asset, storing the same type and key updates that asset. Assets
without a key are always independent. Pool members may share a key.

Tags are separate key-value attributes for filtering. `description` is the
text used to describe an asset; for a generated image, it holds the prompt.
`generated` records whether the asset was generated. `generator` and
`generation` retain provider/model information and JSON parameters.

```crystal
db = DataDungeon::DB.new("assets.db", cache_root: "asset-files")

record = db.store(
  "portrait", {"art_style" => "silver", "race" => "human"},
  canonical_key: game_portrait_key,
  source_path: "portrait.png",
  content_type: "image/png",
  description: image_prompt,
  generated: true,
  generator: "runware:flux-dev-v1",
  generation: %({"width":512,"height":512}),
  image: DataDungeon::ImageMeta.new(compression: "normalize", target_format: "webp")
)

db.get("portrait", game_portrait_key)
db.get_by_id(record.id)
db.get_with_meta("portrait", game_portrait_key)
db.get_with_meta_by_id(record.id)
db.find_assets_by_tags("portrait", {"race" => "human"})
db.path_for(record)
```

`DB#store` gives each new object an opaque storage key independent of its
canonical key. `DB#store_asset` indexes a file whose path the caller already
owns. Existing SQLite asset tables are upgraded when DataDungeon opens the
database.

Run the specs with `crystal spec`.

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
  semantic_tag_keys: %w[race gender hair_color hair_texture outfit]
)

semantic.backfill       # queue pre-existing assets; safe to repeat
semantic.process_queue # run from one worker, off the request path
hits = semantic.search("curly-haired adventurer",
  asset_type: "portrait", tags: {"art_style" => "silver"})
hits.each { |hit| puts "#{hit.asset.id}: #{hit.score}" }
db.close
```

Search can also filter `media: "image"`, `"audio"`, `"text"`, or `"video"`.

Once attached, storing an asset queues it for embedding; deleting an asset
removes its Memo entry. Changes to the description or selected tags are
re-embedded by the worker. Until that worker runs, search may still use the
previous embedding. `process_queue` saves the USearch file; running `backfill`
at startup repairs vectors missing after an interrupted process. An asset with
no description and no selected tags is not indexed. Search returns asset
records without changing usage or match counters, and its query cache stays
in memory. The `generated` flag, generator parameters, and canonical key are
stored as metadata but are not embedded.
