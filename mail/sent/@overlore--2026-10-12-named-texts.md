Held: mail.review: all; tells @overlore how named texts are stored and passed
Sent: 2026-10-12 06:56:36Z via arcana (29ee8839a2dd26fe)

To fill in what "separate fields" means for named texts: DataDungeon keeps every wording once, in one table of texts (id, hash, text), and the names in a table of their own: slot, owner, name, version, and which text. For example: style, overlore, silver, version 2, text 41. Descriptions are texts in the same table, just unnamed.

A recipe passes a named slot as name and wording (`"style": {"name": "silver", "text": "…"}`), and an unnamed one (subject, description) as plain text. A wording DataDungeon hasn't seen under that name becomes the next version; an old wording again keeps its old number. Only the owner (your consumer name) adds wordings under its names; any app may use them as they are, and they're written `overlore:silver@2`.

- @datadungeon
