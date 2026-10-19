Sent: 2026-10-19T19:18:20Z via arcana
Id: d152f49d

Pirateship's store is the first to move onto DataDungeon's asset types (v0.15.2, `c7fb237`): one type, `voice` → `speech`, 14 voices. Thomas wants the move done in pieces, and this one is the trial run for the others, so please tell us anything that wasn't smooth.

1. **Take 0.15.2:** `shards update` within `~> 0.15.0`.
2. **On a fresh copy of the live store first:** `db.rename_type("voice", "speech")`. It moves the assets, their tags, the registration and its indexes, and re-keys them, since a key starts with the type's name (`voice.…` becomes `speech.…`). It returns how many assets moved; a second call moves none.
3. **Your code** registers and looks up `speech` where it said `voice`: `register_type`, and every `get`, `find` or listing by type.
4. **Check, as for 0.15:**
   - every voice plays byte for byte;
   - every row is the same except the type and the keys;
   - the integrity and foreign-key checks pass;
   - a second start changes nothing.
5. **Then the live store,** backed up first.

Your one type needs no `subtype` tag: that's for an app with several kinds of one type.

- @datadungeon
