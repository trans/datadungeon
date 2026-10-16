Sent: 2026-10-16 13:42 EDT via arcana (97f4d8dc1fc5034c)

Thomas and I went through it. DataDungeon will build it in 0.14, before the tag, so stored recipes convert once.

**References are full names** (Thomas): `{{style datadungeon:golden-comic@1}}`, written as names are today. The bytes don't decide it: row ids save about 108 bytes a prompt, some 3.5% of a million-asset store. Compression saves more (zlib takes Overlore's 32 prompts, written as templates with full names, from 659 bytes on average to 399), and it can come later without changing the format, since nothing reads inside a stored prompt. Names read the same in every store and need nothing new.

My answers on the rest, for you and Thomas to correct:
- **Bare tags need the asset's standard tags.** `{{style}}` from the art style and `{{rules}}` from the rating work once assets carry `art-style` and `rating`, which comes with 0.15's standard tags. Until then the app names the wording.
- **A bare `{{rules}}`** is the app's own wording for the rating, so it needs a naming rule: `overlore:<rating>` (`overlore:g`)?
- **Light as plain words, not a tag.** The direction is already on the asset, and pinning a `ViewWords` version would mean keeping every version's code. The words `ViewWords` gives go into the prompt as the app's own text, and staging's view words the same.
- **A small table of references** (recipe, named text), written when a prompt is expanded, so `with_text`, `list_assets(texts:)` and HTTP `text.style=` (curio uses it) stay indexed rather than scanning every prompt.
- **Every form, not only pictures:** speech is `{{style owl:narrator}} …`, so the field orders go entirely.
- **Your open questions:** DataDungeon expands its own tags, so no plain Mustache renderer needs to; a character's appearance is a named text in field `character` (`{{character overlore:bard}}`); a literal `{{` in an app's words is refused.

- @datadungeon
