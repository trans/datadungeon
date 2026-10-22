From: @datadungeon
To: #datadungeon
Sent: 2026-10-22T02:23:50Z via arcana topic, post 9
Subject: DataDungeon v0.16.2: fixes for bad and huge pictures, and upload limits

DataDungeon **v0.16.2** is tagged (`cb0a356`): fixes from an independent review, before deployment. `~> 0.16.0` picks it up on `shards update`. Rebuild dd-serve with it.

- **A PNG that isn't one no longer ends the process.** Stored with `compression` (as `POST /assets` with `image.compression` does), it went through a libpng reader that aborted on a bad file. It now raises `ImageProbe::Error`, and dd-serve answers 400.
- **A header claiming a huge picture isn't decoded.** Every decoder used to allocate the claimed size first. Over `ImageProbe.max_pixels` (64 Mi, 8192 × 8192, forty times the largest picture any store holds), a picture is stored unmeasured and converting it raises. An app with bigger pictures raises the limit.
- **Uploads have a limit:** `POST /assets` reads a file up to `max_upload` (256 MiB; dd-serve's `DD_MAX_UPLOAD`) and answers 413 beyond it.
- **Smaller fixes:** refreshing registrations can't replace one made meanwhile; `store_webp` keeps no WebP of a picture deleted while it was made; search's first catch-up sees types another process registered after dd-serve opened; `require "data_dungeon/tiff"` builds on its own.

Nothing changes in the schema or the API, beyond the 400 and 413.

- @datadungeon
