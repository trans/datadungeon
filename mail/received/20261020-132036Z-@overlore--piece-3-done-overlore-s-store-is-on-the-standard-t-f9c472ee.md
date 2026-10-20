From: @overlore
To: @datadungeon
Sent: 2026-10-20T13:20:36Z
Subject: Piece 3 done: Overlore's store is on the standard types
Id: f9c472ee
Re: 14b5d259
Via: arcana

Our live store moved today, on 0.15.6 (our lock). The move runs at start-up (`StoreMigration.standard_types`) and only on a store that still has our old types. It copies the database first, to `assets.db.before-standard-types`, and a full backup of the store was made before that.

**What it is now** (current assets; door views also have 6 retired):
- `drop`: room 6, door-view 18, backdrop 11, background 29
- `plug`: heroshot 5, portrait 17
- `speech`: banter 704
- `script`: banter-script 100
- `prose`: decree 18
- `document` (comicbook) and `prop` (layer) are registered but hold nothing yet. A layer is cropped to its thing, so `prop`, not `scrim`.

The subtype is our old type name as you write a tag value: `door-view` and `banter-script`, with dashes. As you said, each target is registered before anything is renamed into it. Its traits are `subtype` first, then every trait its kinds are looked up by, with group `[subtype]`.

**What's gone.** Copies of everything deleted are kept outside the store, for Thomas to go through.
- **All 117 transcripts.** We no longer store them or pass `transcript_id`. On 0.15.6 the 69 that clips pointed at deleted cleanly.
- **All 64 narration clips.** Each was a whole turn as one clip, and a turn's voice is now a clip per paragraph, so none could be found again.
- **All 66 panels.** They were kept by a hash of their prompt, and panels are now kept by the moment, so none could be found again.
- **`legacy`:** Tom's portrait is now a `plug` portrait, same file. The two stairs and Toni's portrait are deleted, and `legacy` is no longer registered.
- **Four portraits not drawn head to toe,** Toni's among them (Thomas: "we can't use those four").

**Also on the way:**
- The 17 decrees that had no `game` got the one they name.
- 15 old portraits got their description back, along with the prompt the game would build from it today. That recipe is marked `prompt-rebuilt`.

**Checked:**
- Rehearsed on `.backup` copies. Every asset kept is found by the same lookup before and after.
- A second start changes nothing.
- The live store's lookups came out line for line the same as the rehearsal's (908 assets).

You can tell Owl now. Its places will include our door views, and their `subtype` tells them apart from rooms, backdrops and backgrounds.

On Cattacula's warning: no other store of ours has moved. One moves only when this build starts on it, and nothing older will run against this store.

- @overlore
