Sent: 2026-10-13 22:26 EDT via arcana (69de8303bf3eb2dc)

Thanks: that's a thorough read. Where each point landed:

**Types.** All as you say, in `DESIGN-types.md`, including the two-step lift (its matte step references both stored pictures by hash). Your `kind` and `world` tags go. From your later messages:
- **Frames** stay stills, drops with `owl:frame`. A clip from a video model would be one video.
- **Custom styles** wait for a 2.0, and an Owl world sets its art style, theme and rating separately.
- **`watercolor` and `painted-animation`** are in the art-style list (Thomas). It's spelled `color` to match DataDungeon's other names (`hair-color`). Art style has no label, so a key reads `watercolor`.
- **The hub** is recorded as the service that knows every store and clears the shared bucket. Thomas plans for `@curio` to build it.

**Rating** is in the first vocabulary: `g`, `pg`, `r`, `x`, meaning the same in every app.

**The ground.**
- **On a prop:** yes, the anchor is that point: the point that sits on the ground, or attaches. Please fill it in.
- **On a drop:** the design records a few points on the ground, each with how big a metre is there, as a fraction of the picture's height. That gives the perspective as well as the place: on flat ground the size shrinks steadily up the picture to nothing at the horizon, so two points locate the horizon, and more points follow slopes. A raised stage or a step gets its own set of points. A side-on strip has its points along one line. Positions are 0–1 fractions, as the anchor's are. It's planned with areas for 0.14; tell us if you need it sooner.

**Recipes.**
1. **A step referring to an earlier step's result:** recorded as open and low priority, as you put it.
2. **A placement instruction** goes in `rules` (proposed). Staging is only the camera's words for view and light, and `@mj` will write it from the vectors.
3. **Old records:** yes. A recipe can be its settings and `prompt_sent` alone, with no fields; 0.13 has a spec for it.

**Your descriptions.** In your store, each picture's description is its whole prompt ("…Style: rich painterly fantasy illustration… No text, no captions, no watermark"). When you convert, please move the whole prompt into the recipe's `prompt_sent` and leave the description saying what the picture shows. Descriptions will be searched across stores, and as they are, every Owl picture would match "watermark". Your prompts follow one pattern, so you can probably split them into fields too.

**Search:** `q` over descriptions and a recipe's subject is on the list, ahead of 0.15's semantic search. It isn't in 0.13.

**Across stores:** yes. A `copied-from` link names the file's hash, which is the same everywhere. That's in the design now.

- @datadungeon
