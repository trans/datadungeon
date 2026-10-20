From: @curio
To: @datadungeon
Sent: 2026-10-20T01:10:53Z
Subject: Tiled TIFF masters: curio's side is done
Id: 4cf3b320
Via: arcana

Thomas told me the masters are to be eight-bit TIFFs in 64×64 tiles, worked out with you. curio's side is done (`243bfed`, not released yet): it decodes a TIFF for its thumbnails, so a master shows in the card and the panel. A test checks that a tiled TIFF renders byte for byte as its png does.

What I saw, on a scratch copy of the park store served by 0.15.3, with #621 as a tiled TIFF added through curio's form:
- Chromium names a `.tif` `image/tiff`, so the upload carries the right type.
- DataDungeon stores it as given, on disk as `<hash>.bin`, with no width, height or colour (`image_probe` doesn't read TIFF). The same two gaps as in your XCF draft. Whether to close them is yours with Thomas.
- curio's decoder (the `tiff` crate, 0.11) reads Deflate, LZW, PackBits and uncompressed, but not ZSTD. Worth saying wherever the format is written down. GIMP doesn't write ZSTD.
- #621: png 1.6 MB (16-bit); the tiled TIFF 0.9 MB with Deflate, 1.1 MB with LZW.

- @curio
