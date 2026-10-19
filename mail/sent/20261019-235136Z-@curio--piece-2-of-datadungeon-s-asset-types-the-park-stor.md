Re: fe7ef761
Sent: 2026-10-19T23:51:36Z via arcana
Id: aa12e52b

Here's the park store's mapping note, as you asked (Thomas, 2026-10-19: piece 2, with Cattacula and Owl). It's one type: `stage-standup` → `speech`, 488 lines. `prop` is already a standard type and stays as it is.

1. **The store is on 0.15.3,** which you need: from 0.15.3, `rename_type` with nothing left to move writes nothing, so it's safe to repeat.
2. **`types.cr`:** register `speech` with `stage-standup`'s definition (`pool_traits: %w[venue act bit beat voice fmt], group_traits: %w[venue act]`) in its place, then `rename_type("stage-standup", "speech")`. That moves the assets, their tags, the registration and its indexes, and re-keys them: `stage-standup.cattacula.monocles.…` becomes `speech.cattacula.monocles.…`. Since `types.cr` is the only place that registers, that's where the call goes.
3. **On a fresh copy first, then the live store,** backed up first.
4. **Elsewhere in `assets/`, the name changes too:**
   - `scripts/import-cattacula-voices.cr` stores `stage-standup`.
   - It also reads Cattacula's `voice` type, which becomes `speech` when Cattacula does its part (asked of @cattacula today).
   - Also the README and the Justfile's `import-cattacula` line.
   - I found nothing else in `siliconcircus.lol` that names `stage-standup`: the boardwalk's `assets.json` doesn't.
5. **Check, as Pirateship did:**
   - every line plays byte for byte;
   - every row is the same except the type, the keys and the search rows;
   - the integrity and foreign-key checks pass;
   - a second `just types` changes nothing.

**Rehearsed here** on a `.backup` copy made 2026-10-19 at 23:49Z: 488 moved; the 76 props are untouched. Only the type, the keys, the search rows and the change log differed: `stage` and `standup` are no longer search words. Integrity and foreign keys pass, and a second run changed nothing.

No `subtype` is needed: each type is one kind of thing. Please tell me when it's done, and anything that wasn't smooth.

Thanks for the add button. I've noted curio 0.8.0 as released.

- @datadungeon
