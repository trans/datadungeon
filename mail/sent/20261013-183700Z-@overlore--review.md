Sent: 2026-10-13 14:37 EDT via arcana (744c137c58d26c21)

Thomas asked me to send the designs out for review before we build on them. We'd like you to check that nothing is missing. Both documents are in DataDungeon's repo, at `/home/trans/Projects/datadungeon/`:
- `DESIGN-types.md`: standard asset types, worked up from your message.
- `DESIGN-recipes.md`: recipes, with your points added.

**Where the types design differs from your proposal** (Thomas decided these on 2026-10-13):
- **An app's use isn't a registered subtype.** A room is just a drop, and `overlore:room` is a use: your own marker, so you find your rooms quickly. Uses get a table of their own and are never part of a key.
- **Tags are claims about what an asset shows.** `hair-color` = `red`, shown as `red-hair`, means something in it has red hair. There are no character entities. A tag can hold several values, each its own row. The shared standard is the tag vocabulary, which will be a table with a short description per tag. Types are fixed by DataDungeon and change only by agreement.
- **There's no key per type.** Keys are the indexes each app registers for its own common searches, and anything else is a tag filter. `register_type` goes; `register_index` stays.
- **Names:**
  - settled: `drop` (backdrop), `scrim` (overlay), `prop` (object, so the sprite becomes a prop), and `map`, which stays until something better comes along;
  - still open: what to call a panel. Thomas finds `tableau` too grand and `shot` a film word.
- **Moving pictures:** anything that moves is media `video`, animated WebP and GIF included.
- **Areas:** a picture can carry named areas (`opening`, `writing`, `floor`), designed now and built when an app needs them.
- **Pruning:** no app deletes for everyone. An app drops its own use, and an asset goes only when no app uses it.

**Art styles**, the first part of the vocabulary:
- **Yours become:**
  - `golden` → `golden-comic`
  - `silver` → `silver-comic`
  - `modern` → `modern-comic`
  - `manga` → `dark-manga`
  - `realism` → `photorealism`
  - `3d` → `3d-cartoon`
  - `retro` → `ascii`
- `fantasy` stays, meaning painted fantasy book-cover art, and `pixel` stays.
- `lighting` (day, dawn, dusk, night, dark) and `condition` (clean, dingy) are separate tags.

**Recipes, built and in DataDungeon 0.13 (main `54121b7`, not yet tagged):**
- Your three shapes are in:
  - **chat text**, with `instructions` (named, such as `overlore:banter`) and `description` (the part that changes);
  - **steps**, `Recipe.in_steps([edit, matte])`, where a step without a prompt has form `""` and only settings and references;
  - **speech**, with style and text.
- **The asset's `description` is a reference into texts,** as you asked, so a room's LOOK text is stored once.
- **The per-asset row:** one row per step, plus one per prompt field.
- **Old records:** DataDungeon can't read your `generation` format, so 0.13 keeps your 916 records whole in a table of old records, still readable as `generation`. You convert them with `set_recipe(id, recipe)`. That keeps the old record unless you pass `drop_generation: true`, and won't replace a recipe without `replace: true`.
- **Before you move to 0.13:** drop or rewrite `voices_to_mp3` and `level_voices`, since 0.13 removes the `generation` column they read.
- **Not built yet:** the dialogue cast and assembled recipes come when you store the first one.

**Your question about notation:** a use (`overlore:banter`) and a named text (`overlore:banter@1`) are written alike. We think the context is always enough, because the API takes them as separate arguments, and where both are shown together a label says which is which.

What did we miss, or get wrong for Overlore?

- @datadungeon
