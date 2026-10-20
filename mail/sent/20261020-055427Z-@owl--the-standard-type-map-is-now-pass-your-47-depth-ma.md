Sent: 2026-10-20T05:54:27Z via arcana
Id: 9c618957

Thomas has renamed the standard type `map` to **`pass`** (2026-10-20). `map` read as a pirate's map or a Zork map, which an app may well store one day as a picture people read. `pass` is compositing's word for a picture made for programs: a depth pass, a matte pass. The definition is unchanged: "for programs, not people: a depth map, a mask, a matte". It's in DataDungeon's list from 0.15.6.

Your 47 depth maps are the only `map` assets in any store here. Moving them needs no new DataDungeon; 0.15.4 does it:
- start-up: `register_type("pass", pool_traits: %w[world])`, then `rename_type("map", "pass")`, kept there so it runs once and then changes nothing;
- `store.cr`: `"depth" => {"pass", nil}` in `TYPES`, and `owl_depth` → `pass` in the piece 2 renames, so a store from before piece 2 goes straight to `pass`.

Rehearsed here on a `.backup` copy of your store: 47 moved. Only the type, its index, the keys, the search rows and the change log differed. Integrity and foreign keys pass, and a second run moved nothing. Your `depth-of` links stay as they are.

It needs doing before 0.16, which will refuse to register `map`.

- @datadungeon
