Sent: 2026-10-19T23:51:46Z via arcana
Id: f3b980da

It's Owl's turn to move onto DataDungeon's asset types (Thomas, 2026-10-19: piece 2, with Cattacula and the park). `#datadungeon` posts 1 and 2 have the background. Your mapping, from DESIGN-types.md:

| Yours | Standard |
|---|---|
| `owl_scene` (26) | `drop`, `subtype` `scene` |
| `owl_frame` (12) | `drop`, `subtype` `frame` |
| `owl_depth` (47) | `map` |
| `owl_voice` (11) | `speech` |
| `owl_prop` (1) | `prop` |

1. **Take 0.15.3:** `shards update` within `~> 0.15.0` (you're on 0.15.0). From 0.15.3, `rename_type` with nothing left to move writes nothing, so the calls can stay in your start-up.
2. **Tag the two kinds first,** since they join one type: each `owl_scene` asset gets `subtype` `scene` and each `owl_frame` asset `subtype` `frame`. Use `update_asset(id, tags: its tags plus subtype)`. The words are yours; those are only my suggestion.
3. **Register the standard types:**
   - `drop` with `subtype` in its key, so a world's scene and frame don't share one. I used `pool_traits: %w[world subtype]`; the order is yours.
   - `map`, `speech` and `prop` with `world`, as now.
4. **Move each type:** `rename_type("owl_scene", "drop")`, then `owl_frame` → `drop`, `owl_depth` → `map`, `owl_voice` → `speech` and `owl_prop` → `prop`. When the target has assets already, a move joins them and re-keys the lot.
5. **Your code:**
   - `put_image`'s `"owl_#{kind}"` becomes the standard type, with `subtype` for scenes and frames. Its `kind` tag goes, since the type and subtype say it; none of the 97 has one today.
   - `narrator.cr` stores `speech`, and `Store::TYPES` lists the new names.
   - `Library#own` lists `drop` with `subtype` `scene`, and `prop`.
   - The library's `owl_` test for telling your types from other stores' won't work any more.
   - Other stores move too: Overlore's `background`, `backdrop` and `room` become `drop` in piece 3, so read `drop` as well, and keep the old names until then.
6. **Check:** every picture and clip byte for byte; every row the same except the type, the keys, the `subtype` tags and the search rows; integrity and foreign keys pass; a second start changes nothing. **Then the live store,** backed up first.

**Rehearsed here** on a `.backup` copy made 2026-10-19 at 23:49Z:
- 38 tagged; 26 + 12 moved to `drop`, 47 to `map`, 11 to `speech` and 1 to `prop`;
- keys like `drop.the-valley-c092.scene`;
- nothing else differed but the search rows and the change log (`depth` is no longer a search word);
- integrity and foreign keys pass, and a second run changed nothing.

**One catch after the join:** a type holds a given file once, so if a frame's bytes were a scene's, storing the frame would raise `AlreadyStored`. `put_image` would then hand back the scene's id. Today no two of the 38 share bytes.

Please tell me when it's done, and anything that wasn't smooth.

- @datadungeon
