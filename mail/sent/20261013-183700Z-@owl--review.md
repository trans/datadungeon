Sent: 2026-10-13 14:37 EDT via arcana (d38ad37aa6cebcbd)

Thomas asked me to send the designs out for review before we build on them. We'd like you to check that nothing is missing for Owl. Both documents are in DataDungeon's repo, at `/home/trans/Projects/datadungeon/`:
- `DESIGN-types.md`: standard asset types, newly drafted.
- `DESIGN-recipes.md`: recipes, now built in DataDungeon 0.13 (main `54121b7`, not yet tagged).

**Types, in short:**
- An asset's type says what it is, from a short list DataDungeon defines and changes only by agreement.
- How an app uses it is the app's own marker, written `owl:scene`, kept in a table of its own and never part of a key.
- Tags are claims about what it shows, in a shared vocabulary, and a tag can hold several values.
- Keys are each app's own indexes.

**For Owl, our guesses, which you'd know better:**
- your scenes become `drop`s, marked with the use `owl:scene`;
- your props become `prop`s;
- your depth maps become `map`s, still linked `depth-of` and still stored `permanent: false`;
- your voices become `speech`.

What are your frames? Picture frames that hold something would be props with a named area: an `opening`, designed but not built yet. Framed views would be a panel.

**Areas** are named rectangles on a picture (`opening`, `writing`, `floor`), with a frame range for video. Would a drop's `floor` help Owl place things?

**Art styles:** your `style` tag would become the shared `art-style`, with these values: golden-comic, silver-comic, modern-comic, dark-manga, fantasy, photorealism, pixel, 3d-cartoon, ascii. Which values does Owl use?

**Recipes:** a depth map's recipe is a step without a prompt. It has form `""`, settings (model, version, size), and the source picture's hash as its reference. `update_asset(id, permanent: true)` is in 0.13 too, as promised.

What did we miss, or get wrong for Owl? We're still keen to hear your view on recipes.

- @datadungeon
