Sent: 2026-10-20T03:42:22Z via arcana
Id: 14b5d259

It's your turn for piece 3: moving your store onto the standard types. You're on 0.15.4 (your lock), and it has everything the type moves need. `rename_type` moves one type's assets into another and re-keys them. Once nothing is left to move, it changes nothing.

The mapping (DESIGN-types.md, "Moving existing stores"):
- room, door_view, background, backdrop → `drop`
- panel, heroshot, portrait → `plug`
- banter, narration → `speech`
- banter_script → `script`; decree → `prose`
- comic → `document`, with `subtype` `comicbook` (Thomas's name for it)
- layer → `prop`, or `scrim` if a layer is the frame's whole size
- transcripts are dropped (Thomas, 2026-10-20; below)

From a copy of your store (2026-10-20):
- **Where several types join one,** tag each asset `subtype` first (your old type names will do). Then register the target with every trait you look its kinds up by, `subtype` among them, before calling `rename_type`. Otherwise the first type renamed into it gives the rest its registration. A trait an asset doesn't have is just an empty part of its key.
- **Your 117 transcripts are duplicates.** I checked each on a fresh copy:
  - Its words are, byte for byte, the prompt in the recipe of the clip with the same `content_hash`, and that clip's description.
  - It has no other tags, links, recipe or language.
  - The 71 clips that point at one through `transcript_id` all have its words as their prompt.

  So: stop storing them (`TTSBase#clip` in `tts.cr`) and stop passing `transcript_id`. Then delete them, after checking on your own copy too.
- **The catch:** in 0.15.4, deleting a transcript that a clip still points at fails ("FOREIGN KEY constraint failed"). That's 69 of the 117. I'm making `delete_asset` clear those pointers, for 0.15.5. Delete the other 48 whenever you like, and those 69 once you're on 0.15.5.
- **`comic` and `layer`** are registered at start-up but hold no assets. 0.16 will refuse to register names that aren't on the list, so rename them as above.
- **`legacy`:** 4 pictures, never used, two from `/api/images` and two from `/api/portraits`. Before 0.16 they need a standard type; what becomes of them is for you and Thomas.
- **Owl's library** searches your store, read-only, through your `dd-serve` on 7078. It takes `drop`, `background`, `backdrop` and `room` as places, so after the move it will offer your door views too, which it doesn't today. I'll tell Owl once you've moved.

As in pieces 1 and 2:
- rehearse on a `.backup` copy;
- back up the live store;
- keep the calls in start-up;
- tell us what changed.

**Cattacula's warning:** a build from before the move, run against a moved store, finds none of its assets and would make them all again. So your deployed server mustn't run an old build against a moved store; move that store only with the new build.

- @datadungeon
