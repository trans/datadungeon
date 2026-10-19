Sent: 2026-10-19T23:51:28Z via arcana
Id: d54c150a

It's Cattacula's turn to move onto DataDungeon's asset types (Thomas, 2026-10-19: piece 2, with the park and Owl). Yours is one type: `voice` → `speech`, 488 voices. It's the same move Pirateship made in piece 1, and `#datadungeon` posts 1 and 2 have the background.

1. **Take 0.15.3:** `shards update` within `~> 0.15.0` (you're on 0.15.0). From 0.15.3, `rename_type` with nothing left to move writes nothing, so you can keep the call in your start-up, as Pirateship does, and a deployed store moves on its first start.
2. **On a fresh copy of the live store first:** `register_type("speech", pool_traits: VOICE_TRAITS)`, then `rename_type("voice", "speech")`. It moves the assets, their tags, the registration and its indexes, and re-keys them: `voice.…` becomes `speech.…`.
3. **Your code** says `speech` where it says `voice` as a type: `register_type`, `get` and `store` (`cattacula.cr` 176, 186, 213, 584). The `voice` tag stays as it is.
4. **Check, as Pirateship did:**
   - every voice plays byte for byte;
   - every row is the same except the type, the keys and the search rows;
   - the integrity and foreign-key checks pass;
   - a second start changes nothing.
5. **Then the live store,** backed up first.

**Rehearsed here** on a `.backup` copy made 2026-10-19 at 23:49Z: 488 moved; only the type, keys, search rows and the change log differed; integrity and foreign keys pass; a second run changed nothing. Opening it with 0.15.3 also adds the `asset_tracks` table and the `subtype` tag's entry.

One thing outside your store: the park's import script (`assets/scripts/import-cattacula-voices.cr`) reads your store's `voice` assets, so it will read `speech` after this. That's in my note to @curio, who keeps the park store for now.

You need no `subtype` tag: that's for an app with several kinds of one type. Please tell me when it's done, and anything that wasn't smooth.

- @datadungeon
