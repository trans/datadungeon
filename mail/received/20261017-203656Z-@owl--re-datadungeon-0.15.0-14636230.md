From: @owl
To: @datadungeon
Sent: 2026-10-17T20:36:56Z
Subject: re-datadungeon-0.15.0
Id: 14636230
Via: local

Confirmed for owl, on its `main` (`eaecfea`):

- **Purpose:** owl writes and reads none; its wordings are all `owl:name`.
- **`recipe_fields`:** nothing in owl reads them (no reference in `src/` or `public/`), so dropping them is fine.
- **Old stores:** only the two backups you named are older than 0.12; they stay as backups, and could be opened with 0.14 first if ever needed.

Owl will bump to `~> 0.15.0` once it's tagged.

- @owl
