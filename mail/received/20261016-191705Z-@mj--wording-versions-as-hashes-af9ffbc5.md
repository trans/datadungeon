From: @mj
To: @datadungeon
Sent: 2026-10-16T19:17:05Z
Subject: A wording's version as a hash of its words
Id: af9ffbc5
In-Reply-To: 97f4d8dc
Via: local

A follow-up to the prompt template, worked out with Thomas: a wording's version number means different words in different stores, and we propose a short hash of the words instead.

**The gap.** Each store numbers a wording's versions itself. `put_named` gives a wording it hasn't seen the next number for its name (`recipes.cr`), and a release holds only the vocabulary's current wordings. So:
- A store that skipped a release with an in-between wording gives the next one a different number, and `datadungeon:fantasy@2` means different words in two stores.
- An app's own wordings have the same problem: one tried in a local store takes a number the live store never sees.

Anything that moves records between stores (an export, the hub) then carries a name pointing at the wrong words. Full names were chosen because they read the same in every store, and the numbers undo that.

**The proposal: a version is a hash of its words.** The first 40 bits of the SHA-256 of the wording's exact bytes, in Crockford's base 32, lowercase, always 8 characters. `datadungeon:fantasy@mjdgh455` is "Classic fantasy cover art, slightly painterly." in every store, and nobody has to hand out numbers.
- **The words alone are hashed, exactly as sent,** with no tidying. A stray space is a new version, as it is to the model.
- **Base 32,** because base 64's `/` already separates a flavor's name and its case is lost in filenames and search. Crockford's alphabet leaves out I, L, O and U, so a hash survives being copied by hand.
- **Fixed length.** A git-style shortest unique prefix would make names depend on what each store holds again.
- **Every numbered version becomes its hash in the same 0.14 conversion,** so no `@1` is left to be confused with a hash that happens to be all digits.
- **What's lost:** seeing at a glance which version is newer. The store can record when it first saw each wording.

**A collision** only matters among the versions of one wording (`overlore:silver-comic/place`'s, say): at 40 bits, about 1 in 200 million for a wording with 100 versions. A store has both wordings' words, so it sees a clash when the second arrives and refuses it. An export carries its words, so a store receiving a reference whose words differ from its own refuses that too. A wrong expansion would need a reference that travels without its words, and nothing does.

**A mutated wording:**
- **Edited at the source,** in an app's code or data: that's simply a new hash, a new version. It's harmless, where with numbers it was the mistake that broke things.
- **Rewritten in the database:** this becomes detectable, since the words no longer match their name and a check that re-hashes each wording finds it. With numbers it was invisible. SQLite triggers refusing UPDATE and DELETE on a wording once it exists would prevent it in the first place, and they fire in the `sqlite3` shell too.

- @mj
