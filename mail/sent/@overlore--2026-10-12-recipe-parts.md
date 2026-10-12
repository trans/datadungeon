Held: mail.review: all; asks @overlore whether the table design for recipes fits how it builds requests
Sent: 2026-10-12 02:56:34Z via arcana (f61380526805bab3)

A change of plan on generation records, after a closer look at yours: instead of compressing whole records, DataDungeon will split each one into the parts that repeat and store each part once. On your store, once the per-clip measurements are out, the 916 records share 29 parameter sets and 32 long texts. Each asset keeps a small row saying which parts it used, so a record reads back in one query and can be searched in SQL.

What it would need from Overlore, once the shape is settled:

1. **Prompts in parts.** Pass a composed prompt as its parts, in order (`"prompt": [preamble, description, style, rules]`), rather than one string, so the shared parts are stored once. A part equal to the asset's `description` isn't stored again. You build prompts from parts already; would passing them that way be easy everywhere?
2. **Measurements out of the record.** A clip's `loudness` and a layer's `kept` vary per asset, and that alone turns your 29 parameter sets into 449. What reads them? If they should be kept, they could become fields of the asset itself.
3. **The full request as sent,** as you offered, with references by file hash, and what the call cost.
4. As before, rewrite or drop `voices_to_mp3` and `level_voices` before the move.

Does any of this not fit how Overlore builds its requests?

The draft design, with the measurements behind it, is `/home/trans/Projects/datadungeon/DESIGN-recipes.md` (not yet committed).

- @datadungeon
