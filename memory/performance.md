# Performance

*Updated 2026-10-09*

What each structure costs as a store grows, measured on this project's dev
machine (single-threaded), so a design can be judged at scale (see
principles.md). Each benchmark in `bench/` records its own numbers and how
to rerun it.

## Lookups by traits, at 1M assets

| Lookup | Cost | Notes |
|---|---|---|
| Exact pool key | 0.005 ms | one index seek |
| Leading traits (key prefix) | 0.02-1 ms | one range scan |
| Tag table, one rare tag among those asked | 0.01 ms | DD starts from the rarest tag |
| Tag table, only common tags | 8 ms at 100k, linear | `bench/sqlite_identity.py` |
| Pattern on trait-sorted keys, first trait open | 80 ms, linear | `bench/pattern_keys.py`; also yes/no only |

A composite index needs the values in one row, which the one-row-per-tag
table can't give; the ordered key is that index. A wide table of trait
slots (`t1..t16`) would give one per common order: deferred by Thomas
2026-10-08, the plan if filters on common values get slow.

## Best match: controlled vectors in USearch

`bench/controlled_vectors.cr`: each trait a block of dimensions, weighted;
inner product = weighted count of matching traits. At 1M (102 dims, f32,
797 MB): nearest 10 in 0.22 ms (recall 100%), with style and rating
required 0.38 ms; 200k: 0.16 ms. Grows about logarithmically. Building 1M
took 213 s single-threaded. Built in 0.10.0 as `MatchIndex` (`bench/best_match.cr`, through DD, 200k
portraits, 8 traits incl. a scale, colors, a set): best 10 in 1.36 ms,
3.4 ms with two traits required, recall@10 100% against exhaustive
scoring, catching up 0.9 ms a write, reopening 0.67 s, building 130 s.
Hashing every word gave only 81.5% recall (its noise outweighed small
score gaps); each trait's first 16 values get an exact dimension.

## Search box (`list_assets(q:)`), at 1M

`bench/search_planner.cr` (through DD) and `bench/search.py` (FTS5 alone).
FTS5 reads a word's whole posting list even for one page (about 22 ns a
match), so the planner picks the cheapest of: the index, the rarest word
from the index with the others checked, or a walk through the newest assets
(about 0.44 us an asset). A page of 50: common words 0.10-0.16 ms, rare
0.08 ms, rare with common 0.18 ms, a broad prefix 0.13 ms; two moderately
common words together 4.8-6.3 ms, the slowest case (about N^(2/3)).
Counting all matches is linear (9 ms for a word in a quarter of 1M).
**Open:** `@curio` asks for `count=1` only when a search or filter changes,
and would take an estimated total for "page N of M" (2026-10-08). The word
counts in `asset_search_terms` could estimate a search's total instantly.
FTS5 `detail=none` was about 3x slower; `fts5vocab` counts cost as much as
the search, hence DD's own `asset_search_terms`.

## Paging, at 1M

Offset (numbered pages, 100 a page): page 100 in 0.1-0.25 ms, page 1,000 in
1.6-1.9 ms, linear in the skip. Cursor (`before`): 0.05 ms anywhere.

## Lookups by tags through the planner, at 1M (0.11)

`bench/keys_and_indexes.cr` (Cattacula-like voices, a tenth retired). A
page of 50: by a consumer's index or the type's key 0.04-0.06 ms; one
common trait 0.5 ms and two common together 0.2-2.6 ms, walking the
newest; a rare tag 3.8 ms; a rare tag with others about 20 ms (10,000 rows
checked any way: an index on those traits is the fix). Before the kept
counts and the walk, the same pages took 55-320 ms (a whole range read and
sorted). Counting is linear (16-174 ms). `asset_types` 0.9 ms, `tag_keys`
2.5 ms, `tag_values` 0.01 ms from `asset_tag_counts` (4 s and 1 s when
joined to the assets). The counts' triggers add about 23 us a store (102 to
125 us at 200k); registering an index over 1M assets takes 4.7 s.

## The type's own key as an index (0.12)

`bench/keys_and_indexes.cr` again at 1M, 2026-10-11: everything as 0.11
within noise, except `get` 0.016 ms (0.003 with the column); about 8 us
for a hit on a real store, most of it reading the whole row. The plan is
one key-index search and a rowid fetch; resolving the own index's id in
Crystal and joining instead of `IN` would save about 2 us (not done:
constant, not growing with the store).

## Measuring pictures (0.11.1)

`ImageProbe.measure` (decode and one pass over the pixels) takes 0.8 ms for
a 256x256 WebP, 11.5 ms at 1024x1024, 38 ms at 2048x2048, on every store
of a picture. A copy of Overlore's store (232 pictures, local objects) was
measured in 1.7 s.

## Never splice values into SQL

crystal-db caches a prepared statement per distinct SQL text for each
connection's life, so `IN (#{ids.join})` leaked one per call: 2.7 GB after
1M stores (found 2026-10-09, in `index_search`, there since search was
added). Placeholders fixed it (36 MB). Interpolate only fixed fragments.

## A get's usage touch (`@pirateship`, 2026-10-13)

`get`, `get_by_id` and `get_with_meta` default to `touch: true`, which runs
`touch_asset`: an autocommit `UPDATE` of `last_used_at` and `use_count`
outside any batch. Measured by `@pirateship` on its `voices.db` copy (0.12,
WAL, SQLite's default `synchronous=FULL`): each touch waits on an fsync,
about 5 ms, so 14 existence checks took 73 ms (1 ms with `touch: false`) and
counted 14 plays that never happened. With another process holding the
write lock, the touch waits out `busy_timeout` (5 s) and then raises from
inside `get`: a read turned into a 5 s wait and an HTTP 500. A spawned
fiber doesn't help: SQLite's busy wait blocks the thread, so the next
requests waited instead.

Nobody reads what touches write (checked 2026-10-13): no app reads
`use_count` or `last_used_at` or calls `eviction_candidates` (the only
reader of `last_used_at`). Owl and Pirateship pass `touch: false`
everywhere; Overlore and Cattacula use the default. `dd-serve` doesn't
touch. **Open:** see handoff.md (batched touches).
