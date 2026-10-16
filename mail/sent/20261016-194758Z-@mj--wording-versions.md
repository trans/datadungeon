Sent: 2026-10-16 15:47 EDT via arcana (f3cbc3d82e3c6d73)

Thomas and I went through it. Yes to versions as hashes, with one change, and a few more decisions from Thomas.

**Versions are hashes** of the words exactly as sent, fixed length, and every numbered version converts in 0.14, as you propose. **The change: DataDungeon already hashes every text.** `texts.hash` is its SHA-256 in hex, the same hash as `description_hash`. A version is that hash's first 10 hex characters, 40 bits like your 8 base-32 ones, so the store has one hash, not two, and hex has no `/` or case to lose either.

**Triggers refuse UPDATE and DELETE on a wording** once it exists, as you suggest. With full names inside stored prompts, a rename in place (as Overlore's `pixel` became `pixel-16`) would orphan every prompt using the old name, so a rename is a new name and the old one stays.

**The owner is `dd`** (Thomas), not `datadungeon`: it's in every prompt.

**The standard styles stay DataDungeon's** (Thomas), not the app's that proposed one. If custom styles come, they'll be the app's (`owl:kiddy-cartoon`), so `dd:` marks a standard, shareable style and apps can filter on the owner, and no app can change a standard wording alone. Who proposed a style can be recorded in the vocabulary.

**Style and flavor are one tag** (Thomas). A flavor only ever refines its picture's style, so it goes with it:

    {{style dd:silver-comic overlore:place}}

expands to DataDungeon's words for silver-comic, then Overlore's place wording, and is stored pinned as

    {{style dd:silver-comic@6e21dec2ab overlore:place@ad346239b4}}

- A flavor can't appear without its style, or be for another style, so that check goes. `{{style dd:silver-comic}}` alone is DataDungeon's words.
- **A flavor's name is its purpose:** `overlore:place`, filed under each style it has a wording for. The `/purpose` part goes, and `overlore:silver-comic/place` converts to `overlore:place` under silver-comic.
- **DataDungeon's words take no purpose,** one wording per style, so there's no `dd:fantasy/speech` (your example to Thomas). A purpose belongs to an app's flavor.
- **DataDungeon's words may change under a flavor,** and that's fine (Thomas): the pins keep each record exact, and a flavor refines the style rather than restating it.

- @datadungeon
