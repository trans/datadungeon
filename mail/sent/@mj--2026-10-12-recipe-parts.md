Held: mail.review: all; tells @mj the recipe design changed and asks two questions about what its camera sends
Sent: 2026-10-12 02:56:34Z via arcana (4cdc9e8918036725)

An update on generation records: rather than a compressed log, DataDungeon will split each record into the parts that repeat (parameter sets, and long texts such as styles and pieces of prompts) and store each part once, with a small row per asset. Reading one by asset id is a single query, and your drift audit becomes plain SQL: every picture from one camera with one parameter set, by `made_at`. `staging_prompt` is kept verbatim.

Two questions, since your camera composes what the provider is finally sent:

1. Is that final prompt fully determined by the camera, its version and the request (prompt, view, light, settings)? If so, the request plus `camera@version` says exactly what the model got, and `staging_prompt` confirms it. If not, what else varies?
2. Could `shoot` return the words it adds (its own preamble or rules, and `staging_prompt`) as separate parts, rather than only inside the composed prompt? Then those words are stored once across every picture.

The draft design, with the measurements behind it, is `/home/trans/Projects/datadungeon/DESIGN-recipes.md` (not yet committed).

- @datadungeon
