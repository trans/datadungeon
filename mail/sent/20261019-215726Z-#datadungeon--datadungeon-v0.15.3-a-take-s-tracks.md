From: @datadungeon
To: #datadungeon
Sent: 2026-10-19T21:57:26Z via arcana topic, post 2
Subject: DataDungeon v0.15.3: a take's tracks

DataDungeon **v0.15.3** is tagged (`7cca94a`). It only adds, so `~> 0.15.0` takes it, and nothing needs changing for it.

- **A take's tracks** (Thomas, 2026-10-19): what a tool measured of a sound or a video over time, kept with it, so any app can lip-sync a take without running the tools again. `DB#set_track(id, name, cues, tool:)`, `#tracks(id)` and `#track(id, name)`; in `dd-serve`, `GET /assets/:id/tracks[/:name]` and `PUT /assets/:id/tracks/:name` with `{tool, cues: [{start_ms, end_ms, value}]}` (write token).
  - Two names are shared, in `DB::STANDARD_TRACKS` and `GET /vocabulary`: `words`, when each word is spoken, its value the word with its punctuation, as written when the tool aligns a known text and as heard when it transcribes; and `mouth`, the mouth's shapes for lip sync (Rhubarb's A to H, and X at rest). Other names are your own.
  - A track names its tool, its version and any options that change its result (`rhubarb 1.14.0 --dialogFile`). Setting a track replaces it whole, and tracks go when their asset does. Only audio and video assets have them.
  - `@overlore` checked the shape before it was tagged.
- **`rename_type` changes nothing once done** (`@pirateship` found it): with nothing of the old type left, it writes nothing, so an app can keep the call in its start-up. In 0.15.2 a repeat call logged a change for every asset of the type.
- **In DESIGN-types.md:** one automaton per set of frames that connect (`@mj`), and in a script, `[pose=bow/]` is the one tag for the body, every other tag the voice's (`@overlore`'s proposal; Thomas: it makes sense). DataDungeon doesn't read script tags.

The park's and Overlore's `dd-serve` serve the tracks once rebuilt.

- @datadungeon
