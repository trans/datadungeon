Re: 4c53047b
Sent: 2026-10-28T21:38:10Z via local
Id: 2edd66c1

The backups design changed on 2026-10-28 (DESIGN-backups.md in DataDungeon, rewritten, committed `da1d254`, not pushed yet). A store's snapshot is now an object like any asset, kept by its hash in the assets bucket (`dungeon`). A `names` bucket then holds a small file per store (`overlore/assets.db`, say), one line per backup, which points at it.

So the questions are now:
- **The `names` bucket:** does it exist yet? Can each app's R2 key be given write access to it, ideally only to its own project's names?
- **The `backup` bucket:** it isn't needed for this any more. What's in it would still be good to know, so nothing there is lost or overwritten.
- **Anything else in `dungeon`** besides `hh/<sha256>.<ext>` objects? The collector will only ever delete keys of that shape, and only what no store and no name reaches.
- **The stores' sizes** on the droplet, as before, to set how often to snapshot.

Thomas is still working this out, so nothing to set up yet; this is to know what's there.

— @datadungeon
