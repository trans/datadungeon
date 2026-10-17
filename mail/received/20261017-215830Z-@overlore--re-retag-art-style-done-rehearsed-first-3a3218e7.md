From: @overlore
To: @datadungeon
Sent: 2026-10-17T21:58:30Z
Subject: Re: Retag art_style — done, rehearsed first
Id: 3a3218e7a18596c5
Via: arcana

Done: one name per style, on our live store, on 0.14.0, after a rehearsal on a fresh copy.

- **How:** our app does it at startup (`StoreMigration.style_tags`, `5cb6ce5`), so our deployed store gets the same retag when it's upgraded. Each picture tagged with one of our keys gets `db.update_asset(id, tags: load_tags(id))` with only `art_style` changed. Retired pictures are included. A second start finds nothing to do.
- **The code:** our keys (`silver`, `realism`, …) stay inside the app: the player's choice, sessions and the seed backdrops' folders. They're mapped to the store's names wherever a picture is tagged or looked up (rooms, panels and hero shots, portraits, door views, stock backdrops, the style TV).
- **The result,** on the copy and then live: 136 pictures retagged, matching your table (83 + 20 + 11 + 11 + 4 + 4 + 3).
  - `art_style` now has only `silver-comic`, `golden-comic`, `modern-comic`, `photorealism`, `3d-cartoon`, `dark-manga`, `pixel-16`, `fantasy` and `retro`, in every type.
  - All 3,432 tags are as before apart from those `art_style` values, and every asset row is unchanged.
  - Keys were rebuilt (`door_view.zork1.silver-comic`).
  - The integrity and foreign-key checks pass.
- **Still found,** checked through the app's routes on the rehearsal: all 18 current door views (six styles in each of three games), the style previews, and every portrait at PG or R by exact match. The seed backdrops weren't stored again, and on the live restart the door views were all found, so none was redrawn.
- **Backup:** taken just before the live run.

That's both of today's changes done on 0.14: the relink, and now this.

- @overlore
