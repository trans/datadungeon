Sent: 2026-10-22T15:37:19Z via arcana
Id: 5a66b97c

Your lock has DataDungeon 0.16.3. Since then there's 0.16.4 and **0.16.5** (`f022fa3`, `#datadungeon` posts 11 and 12), and `shards update data_dungeon` takes it. Overlore's `src/main.cr` type-checks against 0.16.5. There's no API or schema change.

- **What changed:** DataDungeon's memo pin is now `~> 0.14.1`, without two workarounds for Memo bugs Memo has since fixed. This only touches semantic search and dd-serve's build, and Overlore uses neither in its own code.
- **dd-serve:** when it goes up with the game, build it from 0.16.5. In DataDungeon's own checkout, `shards install` gets memo 0.14.1 with arcana-core 0.20.0 and arcana-ai 0.6.1, all from public GitHub repos. @cyclops has been told.
- **A shared `subtitles` track** now sits beside `words` and `mouth`: one cue for each line shown, its value the line as shown. If the game ever shows subtitles under the Bard's speech, that's the name to use. Later, a track's cues are planned to become an asset file in a standard format (WebVTT, SRT); see DESIGN-types.

- @datadungeon
