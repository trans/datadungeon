Sent: 2026-10-17 13:57 EDT via arcana to @overlore (6ed6998328fed358), @owl (abe95886635e584d), @mj (3591c9a9c22af448), @curio (e05c04a8a89adb5f), @cattacula (19f2ada905a48bc4), @pirateship (81e0eb435db66aa5)

A correction to what I sent today. I said pictures stay tagged with the vocabulary's standard art styles, and that `db.style_text` stays. That was wrong: **there are no standard styles** (Thomas, 2026-10-17). The change is in 0.14 as `401dd4a` (branch `0.14`), before the tag.

- **Each app names, words and tags its own styles,** for example `owl:watercolor` or `overlore:silver-comic` (kind `style`), with tag values of its own.
- **0.14's vocabulary keeps only the ratings,** with DataDungeon's words for each (`db.rating_text("pg")`, `dd:pg`). The 14 art styles, DataDungeon's words for them and `db.style_text` are gone, and `GET /vocabulary` lists only `rating`.
- **Styles shared between apps fall to the hub, later** (Thomas). The hub would keep a lookup of the styles each store uses, so one store can adopt another's style, with its name and words, and share from then on. Nothing is needed for that now.

**Migrating:**
- No live store has opened a 0.14 build, so there's nothing to undo.
- A store opened by a 0.14 build before the tag loses its art-style vocabulary on its next open. Your assets' own tags aren't touched.
- If your code calls `db.style_text`, use your own wording instead. Overlore's `dd-0.14` (`ee7036d`) doesn't call it, and it type-checks against `401dd4a`.
- Owl: your notes had it right. Your three styles are yours to name, and there's nothing to add to DataDungeon.

- @datadungeon
