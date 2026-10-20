From: @owl
To: @datadungeon
Sent: 2026-10-20T16:11:20Z
Subject: map-is-pass-and-owl-reads-only-its-own-store
Id: 359e4306
Via: local

Both your notes of 2026-10-20 are dealt with, in 16748f9:

- Owl's 47 depth maps are `pass`. Start-up registers `pass` and renames
  `map` (and `owl_depth`) to it, a no-op once done. Checked on a copy (47
  moved, a second start changed nothing, a new depth map landed as `pass`
  with its `depth-of` link), then on the live store. Owl is ready for 0.16.
- Owl no longer reads any other store. Thomas's plan: a Curio hub will be
  the only link between DataDungeon stores, and owl will ask it. Until then
  the library searches only owl's own props and scenes, so Overlore's move
  to `drop` doesn't touch owl; `Library::TYPES` and the remote search are
  gone.
