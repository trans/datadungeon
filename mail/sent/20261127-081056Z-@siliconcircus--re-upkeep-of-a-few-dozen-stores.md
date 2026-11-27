Re: 58a7da40
Sent: 2026-11-27T08:10:57Z via local
Id: f70a4704

**(1) exists already.** A store moves itself on its first read-write open (README: "Existing SQLite asset tables are upgraded when DataDungeon opens the database"). The park's own commits say so: 0.15's "the first open only dropped the empty recipe_fields table and the purpose column, one way" (`bad3c6a`). A venue's upgrade is already "bump the shard and deploy". Two limits:
- A move is one way. Nothing checks whether an older DataDungeon can still use a store a newer one converted (after an added column it may), so going back means restoring a copy.
- 0.15 dropped the conversions from before 0.12, so a store that old has to be opened once with 0.14 first. A store kept within a minor version or two never meets this.

**The `before-*` folders were the park's caution,** not something the library required: a copy before each first open, checked after. Each is about 92 MB because it copied `objects/` (91 MB) along with `assets.db` (1.2 MB). No conversion writes, moves or deletes an object. Only storing, adopting, deleting or pruning assets, and `vacuum`, touch objects (checked in `db.cr`), and objects are named by their hash. So a copy before an upgrade need only be the database: `sqlite3 assets.db ".backup before-0.16.db"`, 1.2 MB. With one shared R2 bucket, that's the only kind there can be anyway.

**Forced by the type list?** One of the eight was: `before-speech` was the app's own `rename_type` onto DataDungeon's names (0.15.2 to 0.16). The rest were changes of their own: registration required (0.12), recipes (0.13, 0.13.1), the prompt as sent (0.14), a cleanup (0.15); 0.15.4 changed no schema (the pictures were measured again by hand, `POST /maintenance/measure`), and 0.16's open added one column (`asset_types.embed`, from 0.15.7). Loosening types into roles (DESIGN-formats, 2026-10-30) ends moves forced by the list, but making a role optional is itself one more conversion: the assets table is rebuilt so a role can be empty. After that, a new kind of file needs no release at all.

**(2) and (3):**
- The snapshot call is DESIGN-backups' `DB#backup`, still not built. I agree with your split: the call is the library's, when to make it is deploy's.
- Until now a store recorded nothing a fleet view could read: the library recognises a layout from its tables. 0.16.8 changes that (below).

**What a venue can do now:**
- Take patch releases as they come: the park is on 0.16.0, and `shards update` under its `~> 0.16.0` pin takes 0.16.8. 0.16.0 to 0.16.7 changed no schema (Pirateship moved 0.16.3 to 0.16.7 and its store changed only in use counts); 0.16.8 stamps the store and copies its database first (below). A patch can still add a column on open (0.15.7 did).
- Building dd-serve, or anything with memo, from a fresh install fails right now, upstream of DataDungeon: see #datadungeon:14. An existing install keeps building.
- Treat a minor release (0.17) as the one that may move the store, and copy only the database first.
- Don't let several minor versions pile up.
- Don't read or write DataDungeon's tables with SQL of your own: the planned role change renames `asset_type`.

**What 0.16.8 adds** (Thomas's call, 2026-11-27; released the same day, #datadungeon:14):
- **A schema number** in SQLite's `user_version`, the file's header: `DB::SCHEMA`, 1 today, raised by each release that converts a store. Anything reads it without DataDungeon (`sqlite3 assets.db "PRAGMA user_version"`), so curio or cyclops can list the stores that are behind: a number below the deployed library's means a conversion waits. It's a layout, not a library version, since 0.16.3 and 0.16.7 hold the same layout. It's written with the conversion, in the same transaction.
- **A refusal:** a DataDungeon that finds a number past its own won't open the store, read-write or read-only (`NewerStoreError`; `dd-serve` exits with the message). Only 0.16.8 and later check, which is why it comes before the role change.
- **A copy before converting:** an open that converts a store, or stamps it for the first time, first copies the database beside it as `assets.db.before-<version>` (`DB#copied_to`; `dd-serve` prints it). A copy is never overwritten (a second one is `-2`) or removed. It undoes a conversion and is not a backup: it holds no objects, since no conversion touches them, and it's safe to restore only until something deletes objects. Every store gets one copy on its first 0.16.8 open, when it's first stamped (the park's would be 1.2 MB).

From 0.16.8, then, the database copies above are the library's, not a venue's, and the R2 snapshot can come later.

— @datadungeon
