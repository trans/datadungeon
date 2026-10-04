# DataDungeon v0.3 — Owning the Write Path

> Historical v0.3 design. See [README.md](README.md) for the current API and
> storage-key behavior. Applications now supply optional canonical keys.

> **Status: implemented (v0.3.0).** `Storage`/`LocalStorage`, the WebP bytes path,
> and `DB#store`/`#get`/`#path_for` are in `src/`, covered by `spec/store_spec.cr`
> and an end-to-end PNG→WebP smoke test (1.2 MB PNG → 70 KB WebP). infocomic
> migration remains a separate later PR.
>
> **Eager metadata (post-0.3.0).** `DB#get_with_meta(asset_type, tags)` returns
> `{AssetRecord, AssetMeta?}` in a single wide LEFT-JOIN query, dispatching to the
> sidecar for the asset's media. The four meta structs now inherit an abstract
> `AssetMeta` base that exposes `presentation` (nil for audio/text), so callers get
> placement pins without narrowing and `.as?(ImageMeta)` for media specifics. This
> also added the previously-missing `load_video_meta`.

## Problem

Today DataDungeon is a bag of primitives — `Cache` (path math), `WebP` (encode),
`DB.store_asset` (metadata insert), `Prompts` — and every consumer writes the
same orchestration glue:

    hash inputs → derive path → check File.exists? → generate → convert → link → store_asset

infocomic implements this twice (backgrounds/tiles via a filesystem cache, portraits
via the DB) and Silicon Circus is about to implement it a third time. The evidence:

- **Two parallel cache systems** in infocomic — bg/tiles dedup by `File.exists?`,
  the DB row for them is *write-only* (`find_asset` is never called for bg/tiles).
- **`prompt_hash` computed twice** — once to build the path, once to build the key.
- **`compression: "webp"`** is decorative — not a valid policy value, triggers nothing;
  the real conversion happens in the caller's `post_process`.
- **`file_hash` never set** — no content integrity, no dedup.

The asset-store *algorithm* lives in the consumer. It should live in the store.

## Goal

One entry point that owns the whole lifecycle:

```crystal
rec = db.store(asset_type, canonical_tags, source_path: png, content_type: "image/png",
               image: ImageMeta.new(compression: "normalize", target_format: "webp", ...))
# → hashes bytes, applies policy (PNG→WebP), writes to a path IT owns,
#   upserts row+tags+meta, returns the record

rec = db.get(asset_type, canonical_tags)  # the single lookup; retires File.exists? dedup
```

Collapse infocomic's `generate`+`Cache`+`WebP`+`save_backdrop`+`store_asset` into
**store / get**. Give Silicon Circus a one-call path.

## Non-goals (v0.3)

- Object-store backends (R2/S3) — but the abstraction is introduced now so adding
  them later is additive, not a rewrite.
- Cross-key byte dedup (same bytes under two different identities → one physical file).
  Requires refcounting; deferred. `file_hash` is still computed and stored so we can
  add it later without a migration.
- Auto dimension/duration probing for non-PNG media. Caller supplies dims via meta
  for now (matches current infocomic behavior).

---

## Core concepts

### 1. Storage backend (new)

DataDungeon gains a thin storage interface. `file_path` stays an opaque **key**;
the backend resolves it. This reconciles "owns the write path" with "backend-agnostic."

```crystal
module DataDungeon
  abstract class Storage
    abstract def write(key : String, bytes : Bytes) : Nil
    abstract def read(key : String) : Bytes
    abstract def exists?(key : String) : Bool
    abstract def delete(key : String) : Nil
    abstract def resolve(key : String) : String   # local absolute path (or URL for object stores)
  end

  class LocalStorage < Storage
    def initialize(@root : String); end
    # key "venue/ab/abcd….webp" → <root>/venue/ab/abcd….webp
  end
end
```

`DB` holds a `Storage`. Constructed as `DB.new(db_path, storage: LocalStorage.new(root))`,
or `DB.new(db_path, cache_root: root)` convenience that builds a LocalStorage.

### 2. Content hashing (finally real)

`store` reads the (post-processing) bytes and computes `file_hash = SHA256(bytes)`,
persisted on the row. Used for:
- **integrity** — detect a corrupted/replaced file,
- **write-skip** — if the target key already holds bytes with the same hash, skip the write,
- **future cross-key dedup** — reserved.

### 3. Path derivation (the store owns it)

The stored key is **derived from identity**, not supplied by the caller:

| Mode | Key template |
|------|--------------|
| single-best (`pool=0`) | `<asset_type>/<key2>/<canonical_key>.<ext>` |
| pool (`pool=1`)        | `<asset_type>/<key2>/<canonical_key>/<file_hash>.<ext>` |

where `<key2>` = first 2 hex chars of `canonical_key` (fan-out to avoid huge dirs)
and `<ext>` comes from the *final* content type after policy.

Rationale for **canonical-key-addressed** (not content-addressed) single-best paths:
- **Natural overwrite, no orphans.** Re-storing the same identity writes the same
  path — the new file replaces the old in place. No orphan-cleanup problem.
- **Deterministic find→file.** The path is a pure function of identity.
- Pool members are content-addressed *within* the identity dir, so identical
  candidate bytes dedup automatically and distinct ones never collide.

`file_hash` is still stored for integrity/dedup; it just isn't the path.

### 4. Policy execution (compression actually happens)

`store` honors `ImageMeta.compression` / `target_format` / `quality_floor`:

| compression | behavior |
|-------------|----------|
| `original`  | passthrough; keep input bytes and content_type |
| `normalize` | convert to `target_format` at high quality (WebP q≈90) |
| `compress`  | convert to `target_format` at `quality_floor` |

Branch on input: if input is **already** the target format, passthrough (so Runware's
native WebP isn't re-encoded; OpenAI's PNG gets converted). This is exactly infocomic's
current provider-specific behavior, moved into the store. `WebP` gains a bytes-in/bytes-out
path (decode via temp file where libpng needs a real fd).

The wrong/decorative `compression: "webp"` value goes away — callers use `normalize`.

---

## API

```crystal
class DB
  # High-level: owns hashing, policy, file write, indexing. Returns the stored record.
  def store(
    asset_type : String,
    canonical_tags : Hash(String, String),
    *,
    source_path : String? = nil,          # exactly one of source_path / bytes
    bytes : Bytes? = nil,
    content_type : String,                # input content type
    media : String? = nil,                # inferred from content_type if nil
    extra_tags : Hash(String, String) = {} of String => String,
    pool : Bool = false,
    permanent : Bool = false,
    generator : String? = nil,
    generation : String? = nil,
    image : ImageMeta? = nil,
    audio : AudioMeta? = nil,
    video : VideoMeta? = nil,
    text  : TextMeta?  = nil,
  ) : AssetRecord

  # High-level lookup: resolves the file, self-heals (missing file → miss),
  # touches last_used_at/use_count. Retires caller-side File.exists? dedup.
  def get(asset_type : String, canonical_tags : Hash(String, String)) : AssetRecord?

  # Resolve a record's key to a usable local path (or URL) via the storage backend.
  def path_for(rec : AssetRecord) : String

  # ── existing primitives remain, unchanged, as the layer `store` builds on ──
  def store_asset(...) : Int64        # metadata-only; caller owns the file
  def find_asset(...) : AssetRecord?  # pure lookup, no touch, no file check
  # ... find_assets_by_tags, load_tags, load_*_meta, touch_asset, delete_asset, eviction
end
```

`store` is orchestration over `store_asset`; `get` is `find_asset` + resolve + verify +
touch. Nothing existing breaks — `store`/`get`/`Storage` are additive.

### store() algorithm

1. Load bytes (from `source_path` or `bytes`).
2. Apply media policy → final bytes, final content_type, final ext. Compute `file_hash`.
3. Derive key from identity (+ hash for pool).
4. For single-best: if a row with this `canonical_key` exists and its stored `file_hash`
   equals the new one and the file is present → **no-op**, touch, return existing.
   Otherwise write bytes via storage (overwriting the identity path).
5. Upsert row (`store_asset` semantics: single-best replaces), tags, media meta,
   with `file_path = key`, `file_hash`, final `content_type`.
6. Return the `AssetRecord`.

### delete semantics

`delete_asset(id)` currently drops the DB row only. Add `delete(rec)` (or a flag) that
also removes the backing file via storage. Single-best overwrite no longer orphans files
(same path), so this matters mainly for explicit eviction.

---

## Backward compatibility & migration

- **Additive.** `store_asset` / `find_asset` / `Cache` / `WebP` stay. Existing infocomic
  code compiles unchanged.
- **infocomic migration (later, separate PR):**
  - `ImageGenBase#generate`: replace the `cache_location_for`/`File.exists?`/`post_process`
    block with `db.get(...)` then, on miss, provider-generate + `db.store(...)`.
  - bg/tiles: the filesystem existence cache becomes `db.get` — kills the two-cache split.
  - `save_backdrop` hierarchical "random backdrop" browse becomes a tag query
    (`find_assets_by_tags` + random pick) instead of a second on-disk layout.
  - portraits: already DB-driven; just swap `store_asset`→`store`, `find_asset`→`get`.
- **Silicon Circus:** uses `store`/`get` from day one — no glue.

---

## Load-bearing decisions to confirm

1. **Path scheme** — canonical-key-addressed single-best paths (recommended, above),
   vs. pure content-addressed (`<hash>.<ext>`, true cross-key dedup but needs refcounting
   for safe delete). Recommendation: canonical-key-addressed now, content-dedup later.
2. **Introduce the `Storage` abstraction now** (LocalStorage only) vs. hardcode local FS
   and abstract later. Recommendation: introduce now — retrofitting later touches every
   call site; the cost today is ~40 lines.
3. **Keep `Cache` and the hierarchical portrait/backdrop layout** during transition
   vs. replace immediately. Recommendation: keep, deprecate gradually; this PR only *adds*
   store/get.
```
