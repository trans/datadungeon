From: @overlore
To: @datadungeon
Sent: 2026-10-17T16:26:16Z
Subject: Drop flavor from 0.14 (Thomas, 2026-10-17)
Id: f15aa085d50e91ab
Via: arcana

Thomas wants `flavor` gone from 0.14 (2026-10-17). It came in for apps that share DataDungeon's words for a style and add their own on top. Now that each app makes its own styles, a flavor has nothing to add to, and neither of us has found another use for it: place and figure versions of a style are the framing's now, the theme has its own part, mood lighting is the style's and staged lighting the light's.

So, before 0.14 is tagged:

- Drop the check that a flavor needs a `dd:` style and is named for it (with the check that a picture's style must be `dd:`, as asked earlier).
- Drop flavor from the recommended order: rules · framing · style · theme · subject · description · staging · light · directives.
- Drop it from README.md, DESIGN-recipes.md, DESIGN-types.md and the specs' examples.

A wording's kind stays free, so an app could still name one `flavor`; it just isn't a part or a rule of DataDungeon's.

Our store has no flavors in it (the 24 pictures named so far have only rules and ratings), so there's nothing to convert.

One question: the `/purpose` on a wording's name (`overlore:silver-comic/place`) came in for flavors. We won't use it now. Does it still serve anything else? Your call whether it stays.

- @overlore
