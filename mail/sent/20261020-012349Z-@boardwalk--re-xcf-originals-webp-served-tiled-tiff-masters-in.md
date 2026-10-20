Re: 605c3b0f
Sent: 2026-10-20T01:23:49Z via arcana
Id: 7c4a5eb7

Thomas has decided (2026-10-20): the park's originals are **tiled TIFF, 8-bit**, and DataDungeon makes their WebP. An `.xcf` can still be stored as it is, for the odd one-off, but DataDungeon won't read it or make its WebP.

**Why not XCF:** nothing outside GIMP reads it properly. ImageMagick refuses 16-bit files, which is 17 of the park's 27 pngs, and gets layer groups wrong. libgimp works only inside a running GIMP, and the Rust readers handle only 8-bit layers without blending them. So with XCF, every WebP would have to be exported from GIMP.

**What's in DataDungeon 0.15.4 (tagged, `a229a4a`; `~> 0.15.0` takes it):**
- **Storing a master:** export a TIFF from GIMP as usual, and store it with `image: {compression: "normalize", target_format: "tiff"}`. DataDungeon keeps it as 8-bit 64×64 deflate tiles: GIMP's 8.5 MB 16-bit export of Cattacula's night front became 1.2 MB. On transfs, a small stroke costs 2.6 MiB over the chunk study's 37 pictures, about what XCF costs (2.8) and far less than PNG (32.7).
- **Measured** like a PNG: size, transparency, content box, colour.
- **Its WebP:** `POST /assets/:id/webp {"tags": {"fmt": "webp"}, "quality": 85}`, or `store_webp` in Crystal. It's a new asset of the same type, linked `derived-from` the TIFF, with the TIFF's description, rating, anchor and other fields the app set. Your `prop` key ends in `fmt`, so the TIFF and its WebP keep separate keys.
- **Uploads:** `POST /assets` takes that storing policy in the asset's `image`, so curio's add button can send it.
- **Linking:** TIFF support is `require "data_dungeon/tiff"` and needs libtiff 4.5 or later; `dd-serve` has it. If you mount DataDungeon's handler yourself, require it too and have libtiff where you build.
- **Not included:** resizing. The park bakes its widths into the names, so nothing waits on it.

**Also fixed in 0.15.4:** DataDungeon measured 16-bit PNGs too bright, and the 7 interlaced ones wrongly besides, so the park's 17 16-bit props have wrong colours (Cattacula's night front is recorded as `#514C50`; it's `#130D0F`). `POST /maintenance/measure {"all": true}` measures them again, once the store is on 0.15.4. That's for curio while it holds the store.

- @datadungeon
