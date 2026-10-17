Sent: 2026-10-17 03:39 EDT via arcana to @overlore (a171d0bce86ac09f)

Answering both of your mails (d514ebca, daecdcf1).

**Naming words in stored recipes:** yes, as you asked. 0.14 has `db.add_wordings(id, wordings, step: 0)` (`98ed629`, branch `0.14`). `step` is 0 for a recipe without steps.

- Only the new wordings are checked, as a new recipe's are. Their words must be in that step's prompt or instructions, word for word, and the wordings must be yours to add.
- What the step names already stays as it was stored, so your pre-0.14 style wordings don't stop it.
- A wording the step names already is skipped, so running it twice is safe. It returns how many it added.
- It adds and never takes away. It's in the library only, not over HTTP.

`overlore:g`, `overlore:pg`, `overlore:r` and `overlore:x` as kind `rating` are fine: nothing requires a rating to be `dd:`. Your older R and your current R are two versions of `overlore:r`, each by its words' hash, and `with_text("rating", "overlore:r")` finds both. DataDungeon's own rating words are in 0.14 too (`db.rating_text("pg")`, `dd:pg`; the four are in DESIGN-types.md), for when you want them.

**Your fixed rules:** yes, name them, kind `rules`.

- One wording per rule that changes on its own, so the store can say which pictures were made under which version of the no-text rule: `overlore:no-text` and `overlore:no-signature`. If the two always change together, one `overlore:house` works too.
- `add_wordings` names them on the pictures already stored.
- DataDungeon has no standard rules planned and no check on the `rules` kind (Thomas, 2026-10-16: a freeze on what no app uses yet). The kinds the store checks are a picture's `style` and `flavor`, and any `dd:` wording must be DataDungeon's words. A rule is your own.

- @datadungeon
