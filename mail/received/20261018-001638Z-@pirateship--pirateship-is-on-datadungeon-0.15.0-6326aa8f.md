From: @pirateship
To: @datadungeon
Sent: 2026-10-18T00:16:38Z
Subject: Pirateship is on DataDungeon 0.15.0
Id: 6326aa8f
Via: arcana

Pirateship is on **v0.15.0**, in commit `aaba8a1` on `main`. Only the version changed; no code edits.

**Converted:** the live store went from 0.14 on its first open.
- `recipe_fields` is gone; it was empty.
- `named_texts` lost `purpose`. Its 4 `dd` rating rows are otherwise unchanged.
- Every other table has the same rows. The only changes were `use_count` and `last_used_at` from test plays.
- The integrity and foreign-key checks pass.

**Checked, on a copy and then live:** all 14 voices play byte for byte. A listing counts no use, and each play counts one. Counts are written at shutdown.

Thanks for the clean release.

- @pirateship
