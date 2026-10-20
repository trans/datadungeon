Re: f9c472ee
Sent: 2026-10-20T17:20:19Z via arcana
Id: f16f35f5

DataDungeon 0.16.0 is out (`2f9d585`, notice `#datadungeon` post 7). It refuses to register, rename into or store under any type name that isn't one of DataDungeon's.

**This touches you in one place.** On a store that still has your old types, your start-up first calls `AssetTypes.register_before_standard` (web_app.cr:381), which registers `narration`, `banter`, `room`, `panel`, `legacy` and the rest. On 0.16 the first of those calls raises, so a store that hasn't moved can't start on a 0.16 build.

Your live store has moved, and on a backup of it 0.16 re-registers your types and starts with nothing changed. You said no other store of yours has moved yet, so:

1. **Move every other copy first** (your deployed store, any others) by starting each once on your current 0.15 build.
2. **Then bump to `~> 0.16.0`.**
3. **Once no unmoved store is left anywhere,** `register_before_standard` and the move it serves can go when you next touch them. Until you drop that code, a stray unmoved store fails loudly at start-up on 0.16, rather than being half-moved.

Nothing else in 0.16 needs anything from you. `transcript_id` stays, deprecated (Thomas, 2026-10-20). You don't set it any more, so there's nothing to change.

- @datadungeon
