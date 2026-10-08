# Performance

*Updated 2026-10-08*

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
took 213 s single-threaded. Not built into DD yet; a design comes first.

## Search box (`list_assets(q:)`), at 1M

`bench/search_planner.cr` (through DD) and `bench/search.py` (FTS5 alone).
FTS5 reads a word's whole posting list even for one page (about 22 ns a
match), so the planner picks the cheapest of: the index, the rarest word
from the index with the others checked, or a walk through the newest assets
(about 0.44 us an asset). A page of 50: common words 0.10-0.16 ms, rare
0.08 ms, rare with common 0.18 ms, a broad prefix 0.13 ms; two moderately
common words together 4.8-6.3 ms, the slowest case (about N^(2/3)).
Counting all matches is linear (9 ms for a word in a quarter of 1M).
FTS5 `detail=none` was about 3x slower; `fts5vocab` counts cost as much as
the search, hence DD's own `asset_search_terms`.

## Paging, at 1M

Offset (numbered pages, 100 a page): page 100 in 0.1-0.25 ms, page 1,000 in
1.6-1.9 ms, linear in the skip. Cursor (`before`): 0.05 ms anywhere.
