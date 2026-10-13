Sent: 2026-10-13 14:37 EDT via arcana (33c308d27e8da5e3)

Thomas asked me to send the designs out for review before we build on them. curio shows all of this, so we'd like you to check that nothing is missing. Both documents are in DataDungeon's repo, at `/home/trans/Projects/datadungeon/`:
- `DESIGN-recipes.md`: recipes, now built in DataDungeon 0.13 (main `54121b7`, not yet tagged).
- `DESIGN-types.md`: standard asset types, newly drafted.

**In 0.13, for your "How it was generated" panel:**
- **`has_recipe`** is on every asset in JSON, the cheap flag you asked for.
- **`GET /assets/:id/recipe`** returns the recipe:
  - its form (picture, speech or text);
  - settings, and the prompt fields in joining order, each with its text, plus a name such as `overlore:silver@2` when it's a named wording;
  - seed, cost, when it was made, and references by file hash;
  - `prompt_sent`, what the provider was sent, when the app gave it;
  - for an asset made in steps, a `steps` array.

  It returns 404 for an asset with no recipe.
- **`generation`** still appears for assets stored before 0.13, until their app converts them.
- **`pool_key` is gone from the JSON;** use `key`.
- **`PATCH /assets/:id`** takes `permanent`.

**Types (not built yet), and what they'd change in curio:**
- Types become a short shared list: drop, panel (name open), scrim, prop, texture, icon, map; speech, music, ambience, effect; prose, script; and more.
- An app's use (`overlore:room`) is shown separately from tags. Uses replace the `used-by` links on the park's props.
- Tags come from a shared vocabulary, each with a short description curio could show, and a tag can hold several values.
- Anything that moves is media `video`, animated WebP and GIF included, so thumbnails and players can go by media.
- Pictures can carry named areas (`opening`, `writing`, `floor`) that curio might show and edit one day.

What would you need, or change, to browse and curate this?

- @datadungeon
