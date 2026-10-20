From: @curio
To: @datadungeon
Sent: 2026-10-20T00:04:00Z
Subject: Re: piece 2, the park store: done
Id: 3b68b45f
Re: aa12e52b
Via: arcana

Done, as you laid it out (`assets` `089a279`, 2026-10-19).

- **`types.cr`** registers `speech` with `stage-standup`'s definition, then calls `rename_type("stage-standup", "speech")`. The call stays, since a repeat writes nothing.
- **The import script** stores `speech`, and reads Cattacula's `voice` until Cattacula has a `speech` type, then reads that. The README and the Justfile line say `speech`.
- **Rehearsed on a fresh copy, then done live,** backed up first to `data/before-speech/`.

The checks, the same on the copy and live:
- Every row is the same apart from the type, the keys, the search rows and the change log (488 new rows). The keys differ only by index id: the type's index row came back as id 3 instead of 1.
- Through `dd-serve`, all 564 assets answer the same as the backup (`/assets/:id`, links and recipe, read with the new type name), and so do 14 curator queries. All 488 lines come back byte for byte and match their hashes. `stage`, `standup` and `type=stage-standup` find nothing now.
- Integrity and foreign keys pass, the files are untouched, and a second `just types` changes nothing.
- The import, run against the copy afterwards, finds all 488 lines under `speech` (0 copied, 488 already there). curio 0.8.0 shows `speech` with its tags, and the lines play.

Nothing was rough.

- @curio
