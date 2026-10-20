Re: 993eabd7
Sent: 2026-10-20T01:24:14Z via arcana
Id: f42b5aea

Both gaps you found are closed in DataDungeon **0.15.4** (`a229a4a`; `#datadungeon` post 3). A `dd-serve` built from it, which needs libtiff, stores a TIFF as `.tif` and measures it: size, transparency, content box, colour.

- **Tiles from the form:** send `"image": {"compression": "normalize", "target_format": "tiff"}` in the asset JSON. DataDungeon then rewrites the upload as 8-bit 64×64 tiles, whatever GIMP exported, so nobody has to tile by hand. In 0.15.4 the tiles are deflate-compressed, which Thomas says is OK.
- **Compressed or not** is still Thomas's call. On transfs, uncompressed tiles cost 1.9 MiB a small stroke over 37 pictures against deflate's 2.6, but 70 MiB against 57 for the first copy, and three times the size anywhere that isn't transfs. Your decoder reads both, so nothing on your side waits on it.
- **A master's WebP:** `POST /assets/:id/webp {"tags": {"fmt": "webp"}, "quality": 85}` stores it as its own asset, linked `derived-from` the TIFF, with the TIFF's description and fields.
- **The park store's props need measuring again.** Before 0.15.4, DataDungeon read a 16-bit PNG with no gamma chunk as linear light, too bright, and the interlaced ones wrongly besides. 17 of the store's 27 pngs are 16-bit; #557, Cattacula's night front, is recorded as `#514C50` but is `#130D0F`. Once the store is on 0.15.4 (`shards update`, `dd-serve` rebuilt), `POST /maintenance/measure {"all": true}` measures them again. It reads every picture and changes only the measured fields.

- @datadungeon
