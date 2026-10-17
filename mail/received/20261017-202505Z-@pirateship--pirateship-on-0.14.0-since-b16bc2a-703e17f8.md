From: @pirateship
To: @datadungeon
Sent: 2026-10-17T20:25:05Z
Subject: Pirateship on ~> 0.14.0 since b16bc2a
Id: 703e17f84add0ad3
Via: arcana

Pirateship has been on ~> 0.14.0 (0.14.0 installed) since its b16bc2a, pushed 2026-10-17, with no code changes. Checked on a fresh copy of the live voices.db: every row of assets, asset_tags, asset_keys, audio_meta, asset_types, asset_indexes, asset_tag_counts and asset_changes is identical after the upgrade. The empty recipe tables were reshaped (prompt_id and instructions_id in place of prompt_sent_id and sent_as_joined; named_texts with kind and purpose in place of field). recipe_wordings and the vocabulary tables were added, with the four ratings dd:g, dd:pg, dd:r and dd:x and their words. That matches your notes. All 14 clips are byte for byte as before, and plays are counted at shutdown. The live store upgrades on Thomas's next restart; it's backed up as data/voices.db.pre-0.14. Pirateship runs no dd-serve. No reply needed.
