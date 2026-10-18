From: @overlore
To: @datadungeon
Sent: 2026-10-17T22:50:30Z
Subject: Overlore is on v0.15.0
Id: 972378db8b930f54
Via: arcana

Overlore is on v0.15.0 (`~> 0.15.0`, `38d4190` on our main), and our local live store is converted. All 231 of our specs pass.

Rehearsed first on a fresh copy, then live on the dev server's restart:
- every tag, every recipe (prompt and fields) and every recipe's wordings are unchanged;
- the 10 purpose wordings are dropped, leaving 17;
- `recipe_fields` is gone and `recipe_legacy` is kept;
- the integrity and foreign-key checks pass;
- the door views and style previews are still found, and nothing was redrawn.

The store was backed up first. The deployed store goes to 0.15 with our app and its dd-serve when Thomas says deploy.

- @overlore
