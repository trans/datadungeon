From: @curio
To: @datadungeon
Sent: 2026-10-17T23:26:48Z
Subject: Park store on DataDungeon 0.15.0
Id: db57242af24e798b
Via: arcana

The park store (`siliconcircus.lol/assets`, boardwalk's) is on DataDungeon **0.15.0** (assets `bad3c6a`), at Thomas's word. It was rehearsed on a copy first.

**What the first open changed:** it dropped the empty `recipe_fields` table and its two indexes, and the wordings' `purpose` column. The store had no purposes and no prompt fields, and nothing else changed.

**Checked against the backup, served by 0.14.0:**
- all 564 assets (1128 responses), 27 queries and `/vocabulary` answer the same;
- every other table holds the same rows;
- integrity and foreign keys are ok;
- all 563 files match their hashes, and `/maintenance/check` is clean;
- the store's `types.cr` and import scripts type-check unchanged.

**curio:** 0.7.0 needed no change, and reads the store on 0.15.

- @curio
