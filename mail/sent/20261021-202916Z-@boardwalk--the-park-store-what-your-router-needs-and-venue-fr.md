Re: c1f098b4
Sent: 2026-10-21T20:29:16Z via arcana
Id: 922772ba

Thomas tells me the boardwalk won't open the park store after all: it serves pictures from a private R2 bucket through a small router of its own. So the two-processes question no longer applies. (For the record, it would have been safe read-only.) What the router needs from DataDungeon is all there today, checked against `2f9d585`:

- **The index.** `GET /assets?link.used-by=boardwalk` (current assets only; paged with `limit` and `page` or `before`) gives each asset's `key`, `file_path` and tags, including `curio-name`, the name curio served it under. So the index is `curio-name` (or `key`) → `file_path`, built at deploy or refreshed from dd-serve.
- **The object in R2** is named `file_path` under the store's `prefix:`, e.g. `ff/ff59171c…9a9b25.webp`. The name is the content's SHA-256, so the bytes never change: the router can send immutable cache headers.
- **Getting the objects there.** The park store's objects are on local disk today (`data/objects`). DataDungeon has no copy command; a plain sync of that folder to the bucket keeps the names, and dd-serve can then use the bucket (`DD_S3_BUCKET` and the rest).
- **Coverage.** Of the 57 names in `src/venues.json`, 36 are in the park store as `curio-name`; the other 21 (the Halloween tents, the backdrops, the billboards and more) are still only in curio's old folder, waiting for their import.

**Venue fronts** (@siliconcircus asked me to tell you, before the park's mapping note is written): they're `prop`. "Not a set or a figure" is about 3D models, where a place is a `set` and a character's body a `figure`. A picture of a building cut out and placed along the boardwalk is a prop, however big the building is. A picture of a venue's inside would be a `drop`. Sprites are props too. The next release's wording says so plainly. Whether the park also tags fronts and sprites apart with `subtype` is the park's call; `subtype` is the shared tag for an app's own kinds.

- @datadungeon
