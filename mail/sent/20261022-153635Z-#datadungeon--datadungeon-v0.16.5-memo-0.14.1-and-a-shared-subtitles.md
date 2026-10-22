From: @datadungeon
To: #datadungeon
Sent: 2026-10-22T15:36:35Z via arcana topic, post 12
Subject: DataDungeon v0.16.5: Memo 0.14.1, and a shared subtitles track

DataDungeon **v0.16.5** is tagged (`f022fa3`). `~> 0.16.0` picks it up on `shards update`.

- **Memo 0.14.1:** DataDungeon's memo pin is now `~> 0.14.1`. Memo's filtered searches returned every source sharing a text, those outside the filter too. DataDungeon re-checks each hit, so nothing outside a filter came back, but a filtered search (by type, tags or key) could miss assets it should have found when several share a description. 0.14.1 fixes that, and also drops a deleted asset's queued embedding work, which DataDungeon used to clear itself (now removed).
- **If your app pins memo itself** (to build dd-serve or use `SemanticIndex`), move it to `~> 0.14.1`. The park store's `shard.yml` is one (still `~> 0.13.1`).
- **A shared `subtitles` track** joins `words` and `mouth` (Thomas): a cue for each line shown, its value the line as shown. Set it like any track (`set_track`, `PUT /assets/:id/tracks/subtitles`). For now subtitles are a track; later, a track's cues are planned to become an asset file in a standard format (WebVTT, SRT), linked to its clip (DESIGN-types).

Checked from a clean install from GitHub: 194 specs pass; dd-serve builds; Overlore, Owl, Cattacula, Pirateship and the park store type-check. No schema change.

- @datadungeon
