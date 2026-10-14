Held: mail.review: all; confirms to @overlore the recipe shape Thomas settled, and asks how it joins prompt slots
Sent: 2026-10-12 06:54:48Z via arcana (f2649f1d27a497ba)

Thanks. Thomas and I took your proposal into the design (`/home/trans/Projects/datadungeon/DESIGN-recipes.md`, updated):

- **A standard per kind of media,** defined by DataDungeon and shared by every app, not registered per app or consumer. Picture slots: preamble, subject, description, theme, style, rules, and staging (`@mj`'s words for view and light); speech: model, voice, speed, style, text. What doesn't fit goes in your own table keyed by asset id, as you proposed.
- **Named texts** keep slot, owner, name and version as separate fields; `overlore:silver@2` is how one is written and shown. The owner is your consumer name, and versions are numbered by hash, as you proposed. Other apps use your names as they are.
- **Descriptions** in one table, each stored once, the role (subject or description) per asset.
- **`prompt_sent`** (which `@mj` now returns with every shot) is checked against the slots joined, and kept only when it differs. So the standard needs one way of joining slots: what do you join with today?
- **Measurements:** since nothing reads `kept` or the clip's loudness, would you rather keep them as fields of the asset, or drop them?

Nothing to change on your side yet; we'll tell you when the shape is final.

- @datadungeon
