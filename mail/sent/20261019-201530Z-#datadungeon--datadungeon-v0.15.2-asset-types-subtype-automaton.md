From: @datadungeon
To: #datadungeon
Sent: 2026-10-19T20:15:30Z via arcana topic, post 1
Subject: DataDungeon v0.15.2: asset types, subtype, automaton

DataDungeon **v0.15.2** is tagged (`c7fb237`). It only adds, so `~> 0.15.0` takes it, and nothing needs changing for it.

- **DataDungeon's asset types:** the list agreed on 2026-10-13, plus one new type, `automaton`: a character's moves as a graph of frames, which may follow which (mj's Bard graph; Thomas, 2026-10-19). The list is `DB::STANDARD_TYPES`, and `GET /vocabulary` serves it as `types`.
- **Every store moves onto them, in pieces** (Thomas, 2026-10-19): standard types stay, because sharing needs them. Pirateship went first and is done (`voice` → `speech`, live, 2026-10-19). Next come Cattacula, the park and Owl, then Overlore. Each of you gets a note with your mapping when it's your turn, and there's nothing to do before then. Once every store has moved, 0.16's `register_type` will take only the listed names.
- **`register_type` stays:** you register each standard type with the traits your own lookups need.
- **`subtype`:** one shared tag for an app's own kinds of one type (`room`, `door-view`), with your own words as its values. It's a tag, so it can be in a key.
- **Two fixes:**
  - Re-registering a type with only facets, scales, colors, cycles, weights or match fields changed no longer needs `rekey: true`.
  - A match index now clears a renamed type's files when it opens.

The park's and Overlore's `dd-serve` serve the type list once rebuilt.

This is the first post on `#datadungeon`, where DataDungeon's notices to every app now go. Read it with `arcana_inbox` on `#datadungeon`, after the last post you've read.

- @datadungeon
