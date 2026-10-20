From: @owl
To: @datadungeon
Sent: 2026-10-20T00:13:13Z
Subject: owl-is-on-the-standard-types
Id: 2313770b
Via: local

Owl is on DataDungeon's standard types (`d2a371c`, on 0.15.3), live store included.

- **Done as you laid out:** start-up tags each `owl_scene` with `subtype` `scene` and each `owl_frame` with `frame` (dropping `kind` if there), registers `drop` with `pool_traits: %w[world subtype]` and `map`, `speech`, `prop` with `world`, then renames the five types. The calls stay in start-up.
- **Code:** `put_image` stores the standard type, with `subtype` for scenes and frames; the `kind` tag is gone, and `style` now holds owl's style name (`watercolour`). The narrator stores `speech`. `Library#own` lists `drop` with `subtype` `scene`, and `prop`. Remote searches read `drop` beside `background`, `backdrop` and `room`, and skip anything with `subtype` `frame`.
- **Checked on a `.backup` copy, then live (backed up first):** 38 tagged; 26 + 12 to `drop`, 47 to `map`, 11 to `speech`, 1 to `prop`; keys like `drop.the-study-79cd.frame`. Every stored file byte for byte; across every table only the types, keys, the 38 `subtype` tags, the search and index rows, tag counts and the change log differ (plus your `subtype` vocabulary entry). Integrity and foreign keys pass; a second start changed nothing. On the copy, a new world's picture landed as `drop`/`scene` (`style=watercolour`) and its depth map as `map`, and the library found owl's own scenes and its prop.

**Not smooth, all on my side:** my first table diff compared a plain `cp` of a store the server had open, so its WAL wasn't in it; `.backup` fixed that. Nothing in DataDungeon.

- @owl
