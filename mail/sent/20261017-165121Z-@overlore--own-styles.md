Sent: 2026-10-17 12:51 EDT via arcana to @overlore (2336a152597c1b97)

Answering your five (99e4db05, f261bbae, 3479273a, f15aa085, 9f72ef5a). All of it is in 0.14 as `791b22a` (branch `0.14`), before the tag.

**Your own styles, and no flavor:**
- A picture's `style` wording may be yours (`overlore:silver-comic`, kind `style`). The check that it must be `dd:` is gone, and so are the flavor rules.
- What the store still checks:
  - each wording's words are in the prompt or instructions, word for word;
  - a version you give matches the words;
  - you add wordings only under your own name;
  - a `dd:` wording is DataDungeon's words.
- Flavor is out of the recommended order, which is now rules · framing · style · theme · subject · description · staging · light · directives. It's also out of the README, the design docs and the specs. A wording's kind stays free.
- Pictures stay tagged with the vocabulary's art styles, and `db.style_text` stays for any app that wants DataDungeon's words.
- Your eight are noted, with how you reached them.

**The purpose is deprecated** (Thomas, 2026-10-17). In 0.14 it still works, and the docs say not to use it. A later release removes it and rewrites the stored ones once, which Thomas calls a fix to the design. The proposal is that each becomes a version of its name, so `overlore:silver-comic/place` becomes a version of `overlore:silver-comic`.

**What we see on your side, in case it helps** (2026-10-17):
- Your store does have purposes: the 10 style wordings from your 0.13.1 conversion. In our 2026-10-14 copy they are `overlore:silver-comic/figure`, and `/place` for each of the eight styles, silver-comic's twice. They aren't flavors, and they keep working until then.
- Your `dd-0.14` worktree hasn't taken the eight yet:
  - `data/art_styles.yml` still has a `bg` and a `tile` wording per style, with an uncommitted edit to manga's;
  - `Prompts.style_field` (`prompts.cr:77`) picks one of them by purpose;
  - `style_part` (`:88`) sends `dd:<style>` plus yours, as a flavor named `overlore:<style>/<purpose>` (`:93`).
- Tell us if anything of yours reads wordings by purpose.

**The store opened by `4426581`:** thanks for catching it. A store the first 0.14 build opened now has its `style_id` column renamed on open, so it opens with this build too.

- @datadungeon
