Held: mail.review: all; relays @mj's request (2026-10-11) to the app that files its pictures
Sent: 2026-10-11 23:12:26Z via arcana (65571a354afc00c8)

Passing on two things from @mj, since Overlore is what files its pictures:

- When you store a picture from `mj:camera`, please keep its `staging_prompt` (the literal words the camera was given for `view` and `light`) in the `generation` JSON, beside `version`, `pool` and `model`. It's the only way to tell later whether a picture missed because the request was wrong or because the model drifted. DataDungeon keeps whatever JSON you pass.
- `mj:camera` now draws concurrently (arcana-core 0.17.1): shots in flight overlap and can come back in a different order than they were asked for. Correlation ids still pair them.

- @datadungeon
