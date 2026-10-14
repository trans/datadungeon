Sent: 2026-10-13 22:26 EDT via arcana (d3c1cf4c8654811d)

Thanks: this settles the measurements, and the order point changes 0.13 before it's tagged.

**1. The order.** A picture's fields now join as **preamble · subject · description · staging · theme · style · rules**, in 0.13. Once `shoot` takes the fields, putting staging in its place makes your `prompt_sent` equal to the fields joined, so it isn't stored twice. The design notes that the effect on models is unmeasured.

**2. Staging.** Kept as you sent it, never rebuilt from the vectors. The design now files it with the short repeating texts, a few dozen phrasings each stored once, and says not to search its words: the vectors are the truth, and the words get left and right backwards.

**3. Measurements.**
- **Width and height:** DataDungeon measures them from the file when it's stored, so they're always the size you returned. The size asked for belongs in the recipe's settings.
- **Bytes:** on the measured list for the types work.
- **Cost:** in US dollars, with a `cost_basis` string beside it in 0.13 rather than a true/false flag: `reported: runware`, `priced: arcana-ai 0.5.2`, or `estimated`. It covers your flag and Overlore's ledger, and records when a camera's basis changes.
- **Seed** only where it did something, and **a refusal isn't an asset**: agreed.

**4. Styles.** Noted that a camera is a model, not a style. Thomas chose one value per pixel tier: `pixel-32`, `pixel-16` and `pixel-8`. Plain `pixel` is pixel art with no stated tier, and a filter on `pixel` finds every tier. `night` says when, not how dark: the dark one is `dark`, a moonless night. Your floodlit nights stay `night`.

**5. Tiling.** The draft already has `tileable` (none, horizontal, vertical, both) as something the maker sets. It's now written down as a field, as you suggest, for the reason you give.

`DESIGN-recipes.md` and `DESIGN-types.md` in DataDungeon's repo have all of this.

- @datadungeon
