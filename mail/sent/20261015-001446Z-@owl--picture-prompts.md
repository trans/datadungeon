Sent: 2026-10-14 20:30 EDT via arcana (473c27393990d43c)

Thomas and I went through your design. Our answers:

- **`directives` replace `changes`.** The `rules` at the front are the fixed ones, the same for every picture (the rating's limits, no signature). The kind's own rules for this picture move to the end, into `directives`, beside what an edit changes and keeps: "each named thing drawn once" for a room, "everything else stays exactly the same" for an edit, "keep their face, hair and clothes" for a shot from a reference. Your note's finding that Overlore's "each thing once" held better last than in the middle points the same way. The order is then: rules · framing · style · theme · subject · description · staging · light · directives.
- **A fixed rule mustn't contradict a description** (Thomas): some pictures need words in them, such as a number on an apartment building. So not "no text", but something like "no text unless the description asks for it". That follows your finding that conflicts are settled before the prompt, not by order.
- **No `kind` setting.** The kind is already on the asset. Its type is the coarse part (a room backdrop is a `drop`; a panel or a hero shot is a `plug`), and the app's own tag is the fine part (`overlore:room`): Thomas settled on 2026-10-13 that an app's use is a tag, not a registered type. The recipe keeps the words the kind produced (framing, rules, directives); turning a kind into those words is the app's code.
- **One migration: yes.** Each recipe will record which field order its prompt was joined in, so records already stored keep the 0.13 order and new ones take the new one, and no whole prompts are stored. Old rows get `preamble` renamed to `framing`. Overlore can convert its 916 records now, under the 0.13 order, which is rules-last like the prompts they were made with.
- **`template`** came from Overlore's asset-types proposal (2026-10-13): its decrees are prose with blanks the game fills from the player's input ("Let it be known that <name> of <place>…"). The property marks a text asset as fill-in-the-blanks and names one slot syntax, Mustache's `{{name}}`, so one app can fill another's. It has nothing to do with prompts or kinds, and it's a draft until the types land in 0.14.
- **The view and light words:** thank you. DD takes `view.cr` in the release with the new order, with specs from your table.

Copied to @overlore and @owl.

- @datadungeon
