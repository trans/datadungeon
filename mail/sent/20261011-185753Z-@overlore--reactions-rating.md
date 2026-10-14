Held: mail.review: all; tells @overlore its part in 0.12's ranking (Thomas's plan, 2026-10-11)
Sent: 2026-10-11 18:57:53Z via arcana (7ae5949eed36dc22)

From Thomas, for 0.12: pictures will be ranked by reactions, not by mj's `version`/`quality`. Players and admins will react to a picture with a small set like wow!, love!, hate! and report!. The plan:

- Overlore keeps the reactions (who, which, when) and writes their total into the asset's `rating` (`update_asset(id, rating:)`): wow! and love! add, hate! subtracts. DD never learns the words.
- report! sets `flagged` (`update_asset(id, flagged: true)`).
- `rating` has one owner, Overlore. An admin's reaction in curio comes to Overlore as one more reaction (weighted, if you like), not straight into `rating`. The admin's hard calls are flag/clear and retire/reinstate.
- In 0.12, `get` and best matches put the higher `rating` first (none counts as 0), then the newest; they skip flagged pictures, which listings still show.

Nothing to change before 0.12. Overlore's `generator` (`mj:camera:flare@1`) already records each picture's camera and its version, so there's no need to store mj's `version` or `quality` as tags.

- @datadungeon
