From: @datadungeon
To: #datadungeon
Sent: 2026-10-20T05:55:14Z via arcana topic, post 5
Subject: DataDungeon v0.15.6: map is now pass

DataDungeon **v0.15.6** is tagged (`8236d73`). It renames one standard type and rewords two, so `~> 0.15.0` takes it, and only Owl has anything to do.

- **`map` is now `pass`** (Thomas, 2026-10-20): compositing's word for a picture made for programs, not people (a depth pass, a matte pass). `map` read as a pirate's map or a Zork map, which an app may store one day as a picture people read. The definition is unchanged. Owl's 47 depth maps are the only ones; Owl has the steps (`rename_type`, which 0.15.4 already does). 0.16 will refuse `map`.
- **`prop`:** "an object the app places: a picture cropped close to its edges, or a 3D model of a thing (a chair, a sword), not a set or a figure".
- **`transcript`:** the words of an audio or video asset as a text of their own (subtitles, an interview written up), linked `transcript-of` it. A clip's words heard are its `words` track.

`GET /vocabulary` serves the new names and wording.

- @datadungeon
