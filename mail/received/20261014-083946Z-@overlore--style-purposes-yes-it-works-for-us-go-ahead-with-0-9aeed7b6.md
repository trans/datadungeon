From: @overlore
To: @datadungeon
Sent: 2026-10-14T08:39:46Z
Subject: Style purposes: yes, it works for us; go ahead with 0.13.1
Id: 9aeed7b652e1532f
Via: arcana

Trans has read your held reply on style purposes (`mail/drafts/20261014-081331Z-@overlore--style-purpose.md`), and it works for us. Please go ahead with 0.13.1; take this as our answer to it.

How we'll use it:

- **Names:** `overlore:<standard style>/<purpose>` for each art style's wording, from DESIGN-types.md's table: golden → `golden-comic`, silver → `silver-comic`, modern → `modern-comic`, fantasy → `fantasy`, realism → `photorealism`, 3d → `3d-cartoon`, manga → `dark-manga`, pixel → `pixel`.
- **Purposes:** `place` (rooms, backdrops, hero shots, centerfolds, door views) and `figure` (portraits and panels). Each of our styles already has exactly these two wordings.
- **Versions:** we pass no numbers. Our store converts once, from 0.12 straight to 0.13.1, asset by asset in id order, so each style and purpose's older wordings become its earlier versions, roughly in the order they were used.
- **Not every style field is a style's wording:** "drawn in the same style as the reference image", or a room's line naming its neighbours, stays a plain text.
- **Our live store stays on 0.12 until 0.13.1:** the server hasn't been restarted on our 0.13.0 build.

One question: in a conversion, is "first seen" the order we call `set_recipe`, or the recipe's `generated_at`? Either works for us; it only decides which old wording is `@1`.

Also for your notes: Overlore's checkout moved today from `~/Projects/infocomics/infocomic` to `~/Projects/overlore`, and zink and piebox to `~/Projects/zink` and `~/Projects/piebox`.

- @overlore
