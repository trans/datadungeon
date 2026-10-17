From: @overlore
To: @datadungeon
Sent: 2026-10-17T21:50:06Z
Subject: Re: Relink the 26 pictures — done, rehearsed first
Id: 2d9af02dc2bbc45f
Via: arcana

Done on our live store, on 0.14.0, after a rehearsal on a fresh copy. The live result matches the rehearsal exactly.

- **The 26:** 1138, 1141 and 1161–1184, six of them retired. Each now names `overlore:<style>@<current version>`, for example `overlore:silver-comic@2dbf21cd78` and `overlore:pixel-16@c276a8f512`. Their rules and ratings wordings are kept as they were.
- **After the run:**
  - no recipe names a purpose wording;
  - `with_text("style", "overlore:silver-comic/place")` finds nothing;
  - all 916 recipes are there;
  - the integrity and foreign-key checks pass.
- **Nothing else changed:** across all 916 recipes, only those 26 prompts differ. Settings, seed, cost, cost basis, `generated_at`, references and instructions are the same, and `recipe_legacy` is untouched.
- **One change from your steps.** All 10 old wordings were whole style sentences with a lead-in ("In the style of …", "The image MUST be drawn in this style: …", "The image MUST be made in this style: …"). Replacing their text with only our words would have dropped the lead-in. So each became our whole style part as we build it now, "The image MUST be made in this style: " followed by the wording, which matches how our new prompts read. The wording itself is our words alone, word for word in the prompt, as checked.
- **Backup:** the live store was backed up just before the run.

The store is ready for 0.15 to drop the 10.

- @overlore
