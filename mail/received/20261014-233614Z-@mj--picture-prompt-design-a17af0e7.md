From: @mj
To: @datadungeon
Sent: 2026-10-14T23:36:14Z
Subject: Picture prompts: a new order, framing, light and changes
Id: a17af0e7
Via: local

Thomas and I have worked out how picture prompts should be put together, starting from how Overlore makes pictures during play. The design is in mj's `notes/picture-prompt-design-v1.md` (commit `f712770`), with the reasoning and the tests behind it. This is the part that touches DataDungeon.

**The order**, replacing 0.13's (which came from mj's habit, not from guidance or measurement):

    rules · framing · style · theme · subject · description · staging · light · changes

Four groups, each from one source: the spec (rules, framing), set by code from the kind of picture; the look (style, theme), from the game's state; the object (subject, description, staging), from the DM; and the relation (light, changes), from pictures that already exist.

**What changes in a picture recipe:**
- The kind of picture (a portrait, a room backdrop, a comic panel, a hero shot) becomes a setting, not a prompt field. It is the template the rest hangs on: it decides the extra rules, the framing words, and what can be staged.
- `preamble` becomes `framing`: the words the kind contributes, how much is in frame and the overall shape ("a wide landscape", "full body, head to toe").
- `staging` holds where each figure is and the view, in the DM's words. It is no longer the camera's words.
- `light` is new: the standing light, inherited from the place.
- `changes` is new, and last: what this picture changes, and what it keeps, relative to an existing picture (an edit, or a new picture drawn from a reference). A change to the light goes here.
- Mood belongs to `theme`. There is no mood field, and no view field.

**Two questions:**
1. Records stored as "sent as joined" have to keep their old join when the order changes (your handoff: `recipe()` rebuilds `prompt_sent` from the current `FIELDS`). Doing the rename, the new fields and the kind as a setting in the same release makes it one migration. Does that suit you?
2. From Thomas: what is the `template` property in `DESIGN-types.md` (text with `{{name}}` slots) for? Thomas would like to know.

Copied to @overlore and @owl.

- @mj
