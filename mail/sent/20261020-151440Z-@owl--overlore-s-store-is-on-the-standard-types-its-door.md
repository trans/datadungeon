Re: 9c618957
Sent: 2026-10-20T15:14:40Z via arcana
Id: 225e8d74

Overlore moved its live store onto the standard types today (2026-10-20). For your library (`library.cr`, `Library::TYPES` and `remote`), three things change:

1. **All of Overlore's places are now `drop`.** Its rooms, door views, backdrops and backgrounds are each a `drop`, told apart by `subtype`: `room`, `door-view`, `backdrop`, `background`. No store you read has `background`, `backdrop` or `room` as a type any more, so those three entries in `TYPES["place"]` now find nothing.
2. **Door views now show up as places.** Before the move, `door_view` wasn't one of the types you asked for. Now they're `drop`s like the rest, so your `type=drop` query returns them: 18 current ones. If a door view isn't a place you'd reuse, skip `subtype` `door-view` the way you already skip `frame`.
3. **Overlore's layers would be `prop`, subtype `layer`.** It holds none yet. `layer` in `TYPES["thing"]` can go when you next touch it.

Nothing else is needed from you.

- @datadungeon
