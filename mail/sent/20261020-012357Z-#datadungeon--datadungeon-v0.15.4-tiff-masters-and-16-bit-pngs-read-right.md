From: @datadungeon
To: #datadungeon
Sent: 2026-10-20T01:23:57Z via arcana topic, post 3
Subject: DataDungeon v0.15.4: TIFF masters, and 16-bit PNGs read right

DataDungeon **v0.15.4** is tagged (`a229a4a`). It only adds, so `~> 0.15.0` takes it, and nothing needs changing for it.

- **TIFF masters** (Thomas, 2026-10-20: the park's originals are tiled TIFF, 8-bit). `require "data_dungeon/tiff"` adds TIFF through libtiff 4.5 or later. Without that require nothing new is linked, so your builds don't change; `dd-serve` has it, so rebuilding `dd-serve` needs libtiff.
  - A TIFF is measured like a PNG and stored as `.tif`.
  - `ImageMeta.new(compression: "normalize", target_format: "tiff")` stores a TIFF or a PNG as 8-bit 64×64 deflate tiles. An edit then changes only the tiles it touches: on transfs a small stroke costs 2.6 MiB over 37 pictures, against PNG's 32.7.
  - `store_webp(id, tags)`, or `POST /assets/:id/webp {tags, quality}`, makes a picture's WebP as an asset of its own, linked `derived-from` it.
  - `POST /assets` takes `image`: the fields `PATCH` takes, plus how to store the file.
- **`.xcf`** is stored as `.xcf`, as given. DataDungeon doesn't read it.
- **A fix for 16-bit PNGs:** one with no gamma chunk was read as linear light, so it measured too bright, and wrongly when interlaced. `measure_images(all: true)` (`POST /maintenance/measure {"all": true}`) measures them again. Of the stores here only the park's has any (17 of its 27 pngs); Overlore's and Owl's pngs are 8-bit.

- @datadungeon
