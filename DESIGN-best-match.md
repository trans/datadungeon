# Best match: controlled vectors

*Designed with Thomas 2026-10-08; built in 0.10.0 as `DataDungeon::MatchIndex`
(`data_dungeon/matches`).*

## What it's for

When an app knows what someone picked (art style golden, rating pg, red
hair, tan skin…) and wants the assets that come **closest**, even when none
matches every pick. `find_pool` finds exact matches and `find_group` the
assets sharing the leading traits; neither ranks near misses. Text
embeddings can't either: a single detail barely moves them (measured
2026-10-04).

```crystal
db.best_matches("portrait", {"art-style" => "golden", "rating" => "pg", "hair" => "red", "skin" => "tan"},
  require: %w[art-style rating],   # must match exactly: the app's call
  weights: {"hair" => 3.0},        # this query's emphasis: the app's call
  limit: 10)                       # => [{record, score}, …], best first
```

What must match and what matters most are the application's decisions
(Thomas, 2026-10-08: art style and rating are usually vital, but that's up
to the app). DD imposes neither: `require:` is empty unless given, and
every trait weighs the same unless the query or the registration says
otherwise.

## The score

`score = Σ weight(trait) × similarity(trait)`, over the traits asked for:

- **Words** (race, gender, things): 1 when equal, 0 otherwise.
- **Ordered traits** (`scales:`, e.g. rating g < pg < r < x): 1 when equal,
  falling evenly to 0 at the far end of the scale.
- **Colors** (`colors:`): by how alike they look, from their coordinates in
  a perceptual color space (auburn is close to red). DD carries the CSS
  named colors (148, e.g. `darksalmon`, which Infocomic already uses). A
  color name it doesn't know (`rainbow`) matches only itself.
- **Sets** (a registration's `sets:`, e.g. items held, `lantern,sword`): by
  how many members two sets share, relative to their size (as Jaccard
  similarity does), so `lantern,sword` is close to `lantern,sword,rope`.
- A trait not asked for counts for nothing; one the asset lacks scores 0.
- Traits in `require:` must match exactly, filtering the candidates.

The returned score is exact: DD computes it from each candidate's tags.

## How it stays fast

Scoring every asset would be linear. Instead each asset gets a **controlled
vector**, built by DD from its tags (no model, no API calls), whose inner
product with a query's vector is the score:

- Each trait is a block of dimensions, stored unweighted. The query carries
  the weights, so changing them, even per query, never rebuilds anything.
- A word gets one of its trait's 16 dimensions to itself, for the trait's
  first 16 values (assigned as they appear, kept with the file): exactly
  perpendicular to every other. Later values get a pseudo-random unit
  vector derived from the name, nearly perpendicular. No value lists, and a
  new custom value changes nothing. (Hashing every word was tried first:
  its noise, about ±0.25 a mismatched trait, outweighed small score gaps
  and recall fell to 81.5%; exact slots brought it to 100%.)
- An ordered value lies on a quarter circle, so neighbours line up closely
  and the ends not at all.
- A color is a point among a few anchor colors, so alike colors line up; a
  custom color name gets a word vector in the same block instead, matching
  only itself.
- A set is the sum of its members' word vectors, scaled to unit length, so
  its inner product with another set grows with the members they share.

**One USearch file per asset type** beside the database (`portrait.usearch`),
one vector per asset, each the type's blocks side by side. A group (golden +
pg) isn't a file of its own: `require:` filters the search. Types can't
share a file because each has its own vector length.

**Inner product**, not cosine or Euclidean distance: it adds up the
per-trait matches, so a trait not asked for adds nothing and one an asset
lacks scores 0. Cosine divides by each vector's length, so an asset missing
traits would score higher; Euclidean counts traits not asked for as
distance, so an asset lacking them would come closer. They agree only when
every asset has every trait, and optional traits are common.

USearch finds the nearest 100-200 vectors; DD scores those exactly and
returns the best. Measured (single-threaded, 2026-10-08):

| Vectors | Assets | Query (top 10) | Recall | Memory |
|---|---|---|---|---|
| one dimension per value, weights stored | 1M | 0.22 ms; 0.38 ms filtered | 100% | 797 MB (f32) |
| words hashed, 16 dims a trait, weights stored | 200k | 0.56 ms | 99.5% | 119 MB (f16) |
| words hashed, 16 dims, weights on the query, 100 nearest | 200k | 0.77 ms | 99.1% | 119 MB (f16) |
| same, 200 nearest | 200k | 1.3 ms | 99.8% | 119 MB (f16) |
| **built: MatchIndex through DD**, 16-dim slots, 8 traits incl. a scale, colors, a set | 200k | 1.36 ms; 3.4 ms with 2 required | 100% | f16 |

Search time grows about logarithmically with the store, so 1M should stay
near 1-2 ms. Adding one asset costs under a millisecond. Building a type's
file from scratch takes about 2 minutes per 200k single-threaded (parallel
adds would cut it), needed only when the vectors' meaning changes: traits
added or removed, a scale or the color table changed. Weights never need it.

## Prior art

Each part is established; the combination is a common pattern in retrieval
and recommender systems, though it has no single name.

- **Values hashed into fixed dimensions:** the "hashing trick", or feature
  hashing (Weinberger et al., 2009), used for open-ended categorical values
  for the same reason as here: new values need no new dimensions.
- **Random, nearly perpendicular vectors for symbols:** random indexing and
  the Johnson-Lindenstrauss lemma. The closest named field is
  hyperdimensional computing, or vector symbolic architectures (Kanerva;
  Plate's holographic reduced representations, 1990s), which encode records
  of role = value pairs as high-dimensional vectors and compare them by dot
  product. They usually bind role and value into one shared vector; giving
  each trait its own block is simpler and lets weights apply per trait.
- **Sets as summed member vectors:** "bundling" in the same field; the dot
  product then approximates set overlap, the vector form of Jaccard or
  MinHash similarity (Broder, 1997).
- **The score:** a weighted sum of per-attribute similarities over mixed
  attribute kinds is Gower's similarity (1971).
- **Ordered values:** usually thermometer encoding (g = 1000, pg = 1100, …),
  where overlap counts closeness; the quarter circle does the same while
  keeping every vector the same length, which inner product needs.
- **Colors:** distance in a perceptual color space (CIELAB, "ΔE") is the
  standard measure of how alike colors look.
- **Approximate candidates, then exact re-scoring:** the usual way nearest-
  neighbour search is used in production, and weighted dot products over
  categorical features are everyday practice in recommender systems
  (factorization machines, two-tower retrieval).

Cited from memory; check the references before quoting them.

## Registration

```crystal
db.register_type("portrait", pool_traits: %w[art-style rating gender race skin hair outfit],
  scales: {"rating" => %w[g pg r x]},   # ordered, low to high
  colors: %w[skin hair outfit],         # compared by appearance
  weights: {"art-style" => 4.0, "rating" => 4.0})  # optional defaults; queries can override
```

`scales` and `colors` change the vectors (rebuilding the type's file) but
no keys; `weights` change neither.

## Keeping it current

DD adds, replaces and removes vectors as assets are stored, edited, renamed
or deleted, in the same places it now refreshes the search words. A missing
or stale file is rebuilt from the tags on open.

## As built

- `best_matches(type, picks, require:, weights:, limit:)` and
  `similar(id, …)`; the HTTP API's `GET /types/:type/matches` and
  `GET /assets/:id/similar` when given a MatchIndex; `dd-serve` always has
  one (building it needs the `usearch` shard, which builds its C library on
  install), and a type's file is built on its first match query.
- One process owns a store's match files (a lock in the directory). Every
  process's writes go into the database's change log (`asset_changes`, the
  latest 100,000 kept); the owner replays it before each query, and a
  checkpoint beside each file (signature, last change, word slots) means a
  restart replays only what changed. Further behind than the log, missing,
  corrupt, or of another signature: rebuilt from the tags.
- Each asset's trait values are also kept in memory, as codes, for exact
  scoring and `require:` filtering without reading the database. When the
  filter leaves USearch too few candidates (a small required group), DD's
  tag filter finds the whole group and all of it is scored.
- **Open:** building is single-threaded, about 130 s per 200k (11 min per
  1M), needed on first use and when traits, scales or colors change;
  parallel adds would cut it. Catching up costs about 0.9 ms a write.
