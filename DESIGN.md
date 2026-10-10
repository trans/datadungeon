# DataDungeon Design

> Historical design notes. See [README.md](README.md) and `src/data_dungeon/`
> for the current API. Canonical keys are now optional and supplied by the
> application; new object paths no longer derive from them.

## Purpose

DataDungeon is a **file store** — it caches and deduplicates generated assets
(images, audio, text). If it did nothing but this, that would already be a win.

It replaces the current mix of filesystem-only caching, sidecar JSONs, and
the portrait-specific SQLite index with a single unified system.

## What Is an Asset

An asset is a file: `.png`, `.webp`, `.mp3`, `.json`, etc. Each asset has:

- A **type** — application-defined string (e.g. "portrait", "background")
- A **media category** — what DataDungeon natively understands (image, audio, text)
- A **file path** — where it lives on disk (relative to cache root)
- A **canonical key** — deterministic hash for exact lookup
- A **file hash** — SHA256 of the file contents (integrity, dedup)
- **Tags** — key-value metadata that describe the asset
- A **media profile** — storage and rendering properties

DataDungeon is **type-agnostic** — it doesn't know what a "portrait" means
in your game. The `asset_type` is just a string the application defines.
But DataDungeon *does* understand **media** — it knows what an image is,
how to compress it, and what metadata a renderer needs.

## Media Awareness

DataDungeon doesn't care about game logic, but it has opinions about files.

### Media Categories

| Category | DataDungeon knows... |
|----------|---------------------|
| image | format (png/webp/jpg), dimensions, color depth, compression, animation |
| audio | format (mp3/wav/ogg), duration, bitrate, sample rate, transcript ref |
| video | format (webm/mp4), dimensions, duration, frame rate, audio track |
| text | content, language |

### Usage Classes

Images have a usage class — what they're *for*, not how big they are.
Drives compression policy and storage decisions.

| Code | Usage | Notes |
|------|-------|-------|
| `bg` | backgrounds, splash screens | largest storage budget |
| `tile` | comic tiles, scene panels | moderate compression ok |
| `prop` | portraits, props, scene elements | moderate compression ok |
| `icon` | tokens, UI elements, small art | keep crisp, small files |

Actual dimensions come from `width`/`height` on `image_meta`.

### Compression Policy

Each asset can specify how aggressively DataDungeon may optimize it:

| Policy | Meaning |
|--------|---------|
| `original` | keep as-is, no conversion or compression |
| `normalize` | convert to preferred format (e.g. PNG → WebP) at high quality |
| `compress` | convert + lossy compress (quality floor specified) |

These live in the media-specific sidecar tables (`image_meta`, `audio_meta`),
not the core `assets` table.

Example `image_meta` rows:
- Photorealistic background: `compression=compress, target_format=webp, quality_floor=80`
- Pixel-art icon: `compression=original` (no touchy)
- Portrait: `compression=normalize, target_format=webp, quality_floor=90`

Example `audio_meta` rows:
- TTS narration: `compression=normalize, target_format=mp3, bitrate=128`
- Sound effect: `compression=original` (keep WAV fidelity)

### Presentation Metadata

A JSON blob on the media meta tables (`image_meta`, `video_meta`).
DataDungeon stores it opaquely; the game engine interprets it.

Not mixed with search tags — presentation data is read-heavy, write-once,
variable per asset, and never queried by.

```json
{"x": 120, "y": 80, "zoom": 1.2, "anchor": "center", "layer": 0}
```

Common keys (application-defined, not enforced by DataDungeon):

| Key | Meaning | Example |
|-----|---------|---------|
| x | horizontal offset (px or %) | `120`, `"50%"` |
| y | vertical offset | `80` |
| zoom | scale factor | `1.2` |
| crop | crop region [x,y,w,h] | `[0,0,512,512]` |
| anchor | anchor point | `"center"`, `"top-left"` |
| layer | z-order hint | `0` (back), `10` (front) |
| rotation | degrees | `90` |
| opacity | 0.0–1.0 | `0.8` |

## What Is NOT an Asset

- Session state (which turn, which room, which player)
- Game content configuration (races, measurements, stat tables)
- Player characters, coins, market items

These stay in the application's session database.

## Scale

- Development: SQLite
- Production: PostgreSQL
- Expected: 100K+ assets, potentially millions
- Schema uses standard SQL only — no database-specific features

## Schema

### `assets` — core identity of every cached file

Lean and universal. No media-specific columns here.

```sql
CREATE TABLE IF NOT EXISTS assets (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  asset_type    TEXT NOT NULL,       -- application-defined ("portrait", "background", etc.)
  media         TEXT NOT NULL,       -- "image", "audio", "video", "text"
  content_type  TEXT NOT NULL,       -- MIME type: "image/png", "audio/mp3"
  file_path     TEXT NOT NULL UNIQUE,
  canonical_key TEXT NOT NULL,
  file_hash     TEXT,
  created_at    TEXT NOT NULL,
  last_used_at  TEXT,                -- updated on every access (cache hit, serve, etc.)
  use_count     INTEGER DEFAULT 0,   -- total accesses
  permanent     INTEGER DEFAULT 0,   -- 1 = never evict
  pool          INTEGER DEFAULT 0,   -- 1 = pooled asset (multiple per canonical key)
  generator     TEXT,                 -- "runware:flux-dev-v1", "openai:gpt-image-1" (indexed for bulk queries)
  generation    TEXT,                -- JSON blob: generation params {cfg_scale: 14, steps: 20, ...}
  rating        INTEGER,             -- 1-5 stars, NULL = unrated
  flagged       INTEGER DEFAULT 0    -- 1 = user flagged for quality issues
);

CREATE INDEX IF NOT EXISTS idx_assets_lookup
  ON assets(asset_type, canonical_key);
CREATE INDEX IF NOT EXISTS idx_assets_type
  ON assets(asset_type);
CREATE INDEX IF NOT EXISTS idx_assets_generator
  ON assets(generator);
```

### `asset_tags` — key-value metadata per asset

```sql
CREATE TABLE IF NOT EXISTS asset_tags (
  asset_id  INTEGER NOT NULL,
  tag_key   TEXT NOT NULL,
  tag_value TEXT NOT NULL,
  PRIMARY KEY (asset_id, tag_key),
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tags_kv
  ON asset_tags(tag_key, tag_value);
```

### `image_meta` — image-specific properties

Linked 1:1 from assets where `media = 'image'`.

```sql
CREATE TABLE IF NOT EXISTS image_meta (
  asset_id      INTEGER PRIMARY KEY,
  width         INTEGER,             -- pixels
  height        INTEGER,             -- pixels
  usage_class   TEXT,                 -- 'bg', 'tile', 'prop', 'icon'
  animated      INTEGER DEFAULT 0,   -- 0 = static, 1 = animated (WebP/APNG)
  frame_count   INTEGER,             -- number of frames (animated only)
  duration_ms   INTEGER,             -- total animation length (animated only)
  compression   TEXT DEFAULT 'original', -- "original", "normalize", "compress"
  quality_floor INTEGER,             -- 0-100, NULL = lossless
  max_colors    INTEGER,             -- palette limit, NULL = full color
  -- TODO: named palette/theme support? e.g. "sepia", "neon", "muted"
  --       could drive color grading, consistency across assets in a scene,
  --       or let players pick a visual theme. Maybe a palettes table.
  target_format TEXT,                -- preferred format: "webp", "png", NULL = keep
  presentation  TEXT,                -- JSON blob: positioning hints for renderer
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);
```

### `audio_meta` — audio-specific properties

Linked 1:1 from assets where `media = 'audio'`.

```sql
CREATE TABLE IF NOT EXISTS audio_meta (
  asset_id      INTEGER PRIMARY KEY,
  duration_ms   INTEGER,             -- length in milliseconds
  sample_rate   INTEGER,             -- e.g. 44100, 24000
  bitrate       INTEGER,             -- kbps
  channels      INTEGER DEFAULT 1,   -- 1 = mono, 2 = stereo
  transcript_id INTEGER,             -- FK to a text asset (the spoken words)
  compression   TEXT DEFAULT 'original',
  target_format TEXT,                -- "mp3", "ogg", NULL = keep
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE,
  FOREIGN KEY (transcript_id) REFERENCES assets(id)
);
```

### `video_meta` — video-specific properties

Linked 1:1 from assets where `media = 'video'`.

```sql
CREATE TABLE IF NOT EXISTS video_meta (
  asset_id      INTEGER PRIMARY KEY,
  width         INTEGER,
  height        INTEGER,
  duration_ms   INTEGER,
  frame_rate    REAL,                -- fps
  size_class    TEXT,                -- "full", "half", "spot"
  has_audio     INTEGER DEFAULT 0,   -- 0 = silent, 1 = has audio track
  compression   TEXT DEFAULT 'original',
  quality_floor INTEGER,
  target_format TEXT,                -- "webm", "mp4", NULL = keep
  presentation  TEXT,                -- JSON blob: positioning hints for renderer
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);
```

Note: short animations (animated portraits, spell effects, looping props)
may be better served as animated WebP — stored as `media = 'image'` with
an `animated = 1` flag in `image_meta`. WebP animation is smaller than
GIF, supports alpha, and needs no video player. Reserve `media = 'video'`
for longer-form content (cutscenes, trailers).

### `text_meta` — text-specific properties

Linked 1:1 from assets where `media = 'text'`. The content itself lives
here — no separate file needed for a one-liner, though a sidecar file
can also exist on disk for portability.

```sql
CREATE TABLE IF NOT EXISTS text_meta (
  asset_id  INTEGER PRIMARY KEY,
  content   TEXT NOT NULL,           -- the actual text
  language  TEXT,                    -- "en", "es", etc.
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);
```

### Asset relationships

Audio assets can reference their transcript via `audio_meta.transcript_id`.
This points to a text asset rather than duplicating the string. The text
asset stands on its own (searchable, deduplicable) and the audio asset
links to it.

Example: a TTS decree —
- Text asset: `media='text'`, `text_meta.content = "All goblins shall wear top hats"`
- Audio asset: `media='audio'`, `audio_meta.transcript_id → text asset id`

## Source of Truth

The **storage backend is the source of truth**. The database is an
**index** that can be rebuilt at any time.

On local disk, every asset can have a `.json` sidecar with its tags and
metadata, enabling DB rebuild from a bare filesystem backup.

On object stores (R2, S3, DO Spaces), sidecar metadata can be stored as
object metadata or companion `.json` objects alongside the asset.

This enables:
- Rebuilding the DB from storage alone
- Migrating between database backends (SQLite → PostgreSQL)
- Migrating between storage backends (local → R2)
- Sharing asset packs between installations
- Development: blow away the DB, restart, it re-indexes

In production, database backups are handled by the platform (Supabase).
Storage durability is handled by the object store provider.

## Storage Backend

`file_path` is a **storage key**, not necessarily a local filesystem path.
It works as:
- Local disk path today (relative to cache root)
- Object store key tomorrow (R2, DO Spaces, S3)

DataDungeon doesn't serve files directly — it returns the key and the
application resolves it to a URL or local path based on the configured
backend. This keeps DataDungeon backend-agnostic.

```
# Local:  /var/cache/datadungeon/portraits/silver/pg/human/m/a1b2c3.webp
# R2:     portraits/silver/pg/human/m/a1b2c3.webp  (same key, different resolver)
```

## Pools vs Single-Best

*Superseded in 0.11: keys are an index, every store adds, and `get`
prefers the newest current take (see DESIGN-image-fields.md, "Keys as an
index"). Kept for the history.*

**Single-best** (`pool = 0`): one asset per canonical key. Storing a new
asset with the same canonical key replaces the old one. Lookup by exact
canonical key returns the one result.

**Pool** (`pool = 1`): multiple assets share the same canonical key.
Each insert adds to the collection. Lookup returns a random pick (or all
members for the application to choose from). Every pool member is still
individually addressable by its `id` and `file_path`.

Example: 100 decree texts for "Zork III" — all share the same canonical
tags `{quest: "Zork III"}`, each has a unique `file_path` and `id`.

```sql
-- Random pick from a pool
SELECT * FROM assets
WHERE asset_type = ? AND canonical_key = ?
ORDER BY RANDOM()
LIMIT 1

-- All members of a pool
SELECT * FROM assets
WHERE asset_type = ? AND canonical_key = ?
```

## Eviction

Assets track `last_used_at` and `use_count`. On every cache hit or serve,
`last_used_at` is updated and `use_count` incremented.

Assets with `permanent = 1` are never evicted — seed backdrops, curated
assets, anything hand-picked.

Eviction candidates: `permanent = 0`, ordered by `last_used_at` ascending
(least recently used first). Eviction can be triggered by storage budget,
asset count, or manual cleanup. The application decides policy; DataDungeon
provides the data to make the decision.

```sql
-- Find eviction candidates: oldest unused, non-permanent
SELECT id, file_path, last_used_at, use_count
FROM assets
WHERE permanent = 0
ORDER BY last_used_at ASC NULLS FIRST
LIMIT ?
```

## Canonical Key

Each asset type defines which tags form its identity. These **canonical tags**
are sorted alphabetically, serialized as `key=value\n...`, and SHA256 hashed:

```
art_style=silver
gender=m
race=human
rating=pg
description_hash=a1b2c3d4
```

→ SHA256 → `canonical_key`

This gives O(1) exact lookups via the `idx_assets_lookup` index.

## Tags

Tags are the semantic parameters you'd actually search/filter by.
They replace the old opaque `params_hash` (which was just a SHA256 of a JSON
blob containing model config — useless for queries).

### Canonical Tags (form the canonical_key)

| Asset Type | Canonical Tags |
|-----------|----------------|
| portrait | art_style, description_hash, gender, race, rating |
| background | art_style, prompt_hash, rating |
| tile | art_style, prompt_hash, rating |
| backdrop | art_style, rating, subdir |
| audio | content_hash, voice |
| banter | content_hash, voice |

### Extra Tags (searchable, not part of canonical_key)

| Asset Type | Extra Tags |
|-----------|------------|
| portrait | height_bucket, shoulders_bucket, chest_bucket, waist_bucket, hips_bucket, neck_bucket, arm_length_bucket, leg_inseam_bucket, phy_tier, skin, hair_length, hair_texture, hair_color, facial_hair, outfit, outfit_color, embellishment |
| background | room |

## Queries

### Exact lookup (hot path, 90%+ of queries)

```sql
SELECT * FROM assets
WHERE asset_type = ? AND canonical_key = ?
```

Single indexed column scan. O(1) at any scale.

### Tag-filtered search (fuzzy matching, browsing)

Single JOIN with GROUP BY/HAVING — scales to millions:

```sql
SELECT a.id, a.file_path FROM assets a
JOIN asset_tags t ON t.asset_id = a.id
WHERE a.asset_type = 'portrait'
  AND ((t.tag_key = 'art_style' AND t.tag_value = ?)
    OR (t.tag_key = 'rating'    AND t.tag_value = ?)
    OR (t.tag_key = 'race'      AND t.tag_value = ?)
    OR (t.tag_key = 'gender'    AND t.tag_value = ?))
GROUP BY a.id
HAVING COUNT(*) = 4
```

Returns candidates. Fuzzy scoring happens in application code, not SQL.

### Batch tag loading (for fuzzy scoring)

```sql
SELECT asset_id, tag_key, tag_value
FROM asset_tags
WHERE asset_id IN (?, ?, ...)
```

Load all tags for candidates, score in Crystal/application code.

## Session-Level Caching

DataDungeon tracks assets. The application caches associations:

- **Room backgrounds**: first visit queries DataDungeon, URL cached in
  session DB (session_id + room → URL). Return visits never re-query.
- **Turn images**: session_id + turn → background_url + tile_url in session DB.
- **Portrait**: session_id → portrait_path in session DB.

## API

```crystal
module DataDungeon
  class DB
    # Store a new asset with optional media metadata
    def store_asset(
      asset_type : String,
      content_type : String,
      file_path : String,
      canonical_tags : Hash(String, String),
      extra_tags : Hash(String, String) = {} of String => String,
      file_hash : String? = nil,
      image : ImageMeta? = nil,
      audio : AudioMeta? = nil,
      video : VideoMeta? = nil,
      text : TextMeta? = nil
    ) : Int64

    # Exact lookup by canonical key
    def find_asset(
      asset_type : String,
      canonical_tags : Hash(String, String)
    ) : AssetRecord?

    # Find assets matching a subset of tags
    def find_assets_by_tags(
      asset_type : String,
      filter_tags : Hash(String, String)
    ) : Array(AssetRecord)

    # Load all tags for an asset
    def load_tags(asset_id : Int64) : Hash(String, String)

    # Load tags for multiple assets (batch)
    def load_tags_batch(
      asset_ids : Array(Int64)
    ) : Hash(Int64, Hash(String, String))

    # Media metadata — lazy loaded, not included in find_asset
    # NOTE: how often do we actually need metadata on retrieval?
    #       if rarely, lazy is right. if most callers need it,
    #       consider eager-loading or a find_asset_with_meta variant.
    def load_image_meta(asset_id : Int64) : ImageMeta?
    def load_audio_meta(asset_id : Int64) : AudioMeta?
    def load_video_meta(asset_id : Int64) : VideoMeta?
    def load_text_meta(asset_id : Int64) : TextMeta?

    # Delete asset record (caller handles file/object deletion)
    def delete_asset(id : Int64) : Nil

    # Check if asset exists
    def asset_exists?(
      asset_type : String,
      canonical_tags : Hash(String, String)
    ) : Bool
  end

  struct AssetRecord
    getter id : Int64
    getter asset_type : String
    getter media : String
    getter content_type : String
    getter file_path : String
    getter canonical_key : String
    getter file_hash : String?
    getter created_at : String
    getter last_used_at : String?
    getter use_count : Int32
    getter permanent : Bool
    getter pool : Bool
    getter generator : String?
    getter generation : String?    # JSON string
    getter rating : Int32?
    getter flagged : Bool
  end

  struct ImageMeta
    getter width : Int32?
    getter height : Int32?
    getter usage_class : String?
    getter animated : Bool
    getter frame_count : Int32?
    getter duration_ms : Int32?
    getter compression : String
    getter quality_floor : Int32?
    getter max_colors : Int32?
    getter target_format : String?
  end

  struct AudioMeta
    getter duration_ms : Int32?
    getter sample_rate : Int32?
    getter bitrate : Int32?
    getter channels : Int32
    getter transcript_id : Int64?
    getter compression : String
    getter target_format : String?
  end

  struct VideoMeta
    getter width : Int32?
    getter height : Int32?
    getter duration_ms : Int32?
    getter frame_rate : Float64?
    getter usage_class : String?
    getter has_audio : Bool
    getter compression : String
    getter quality_floor : Int32?
    getter target_format : String?
  end

  struct TextMeta
    getter content : String
    getter language : String?
  end
end
```

## Implementation Notes

### Generator changes — populate new asset fields on store

**`runware_image_gen.cr`** and **`image_gen.cr`** (OpenAI):
- `generator`: `"runware:flux-dev-v1"` or `"openai:gpt-image-1"`
- `generation`: JSON blob with backend-specific params (`{cfg_scale, steps, strength}` or `{quality, size}`)
- `usage_class`: passed in by caller (see below)
- `width`/`height`: from `SIZES[kind]`

### Callers — set usage_class per context

| Call site | usage_class | Notes |
|-----------|------------|-------|
| `web_app/turn.cr` — background generation | `bg` | 1024x768 |
| `web_app/turn.cr` — tile generation | `tile` | 768x1024 |
| `routes/portraits.cr` — portrait generation | `prop` | 768x1024 |
| (future) icon/token generation | `icon` | TBD dimensions |

### Route changes — use new asset API

| Route file | Current | New |
|-----------|---------|-----|
| `routes/portraits.cr` | `db.save_portrait(...)` | `db.store_asset(...)` with canonical + extra tags, image meta |
| `routes/portraits.cr` | `db.find_exact_portrait(...)` | `db.find_asset(...)` by canonical key |
| `routes/portraits.cr` | `db.find_closest_portrait(...)` | `db.find_assets_by_tags(...)` + Crystal fuzzy scoring |
| `routes/images.cr` | filesystem-only cache | `db.store_asset(...)` on generation, `db.find_asset(...)` on lookup |
| `routes/audio.cr` | filesystem-only cache | `db.store_asset(...)` with audio_meta + transcript link |
| `routes/data.cr` | `asset_db` for races | races move back to session DB |

### Schema migration

- Drop `portrait_index` table (replaced by `assets` + `asset_tags`)
- Drop `races`, `race_measurements`, `race_options` from asset DB (move back to session DB)
- Create `assets`, `asset_tags`, `image_meta`, `audio_meta`, `video_meta`, `text_meta`

### DataDungeon shard changes

| File | Change |
|------|--------|
| `db.cr` | Rewrite: generic asset schema, store/find/tags/meta API |
| `portrait_index.cr` | Remove mixin, keep `PortraitAttrs`/`PortraitMatch` structs |
| `race_registry.cr` | Remove from shard (back to infocomic) |
| `cache.cr` | Optional DB recording on cache store |

### Infocomic changes

| File | Change |
|------|--------|
| `sqlite_session_db.cr` | Re-add race tables |
| `session_db.cr` | Re-add race abstract methods |
| `image_gen_base.cr` | Pass usage_class + meta to store_asset |
| `runware_image_gen.cr` | Build generator string + generation JSON |
| `image_gen.cr` | Build generator string + generation JSON |
| `routes/portraits.cr` | New asset API, fuzzy scoring in Crystal |
| `routes/images.cr` | Record bg/tile assets in DB |
| `routes/audio.cr` | Record audio assets + transcript links |
| `routes/data.cr` | Races back on session DB |
| `web_app.cr` | Update asset_db init |

### Verify

1. `crystal build src/main.cr` — compiles
2. `just dev` — starts, creates assets.db with new schema
3. Character creation: race dropdowns populate (back on sessions.db)
4. Portrait generation: stored via new asset API with image_meta
5. Portrait preview: fuzzy matching works via Crystal scoring
6. Background/tile generation: tracked in assets.db with usage_class
7. Audio generation: tracked with transcript links
8. `generator` field populated on all new assets
