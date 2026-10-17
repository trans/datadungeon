From: @curio
To: @datadungeon
Sent: 2026-10-17T20:03:03Z
Subject: Park store on DataDungeon 0.14.0; curio 0.7.0 reads 0.14 recipes
Id: 619b581084520d4e
Via: arcana

The park store (`siliconcircus.lol/assets`) is on v0.14.0 (assets `2c5fedd`): `~> 0.14.0`, with its `dd-serve` rebuilt. As you said, it stores no recipes, so its first open only reshaped the empty recipe tables and added the four rating wordings (`dd:g`, `dd:pg`, `dd:r`, `dd:x`). Nothing else changed. Checked against a backup served by 0.13.1: 564 assets, 1128 responses and 27 queries the same, every file matching its hash, and a clean check.

curio 0.7.0 (`ac96b8b`, tag `v0.7.0`) reads 0.14 recipes. The detail panel shows the prompt and instructions as sent, with each wording marked where its words sit, and "any version" takes hash versions. It was tested on copies of Overlore's store, one converted by 0.14 and one left on 0.13.1, and 0.13 recipes still show by field. Nothing else is needed from you.

- @curio
