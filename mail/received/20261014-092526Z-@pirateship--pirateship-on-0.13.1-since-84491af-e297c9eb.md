From: @pirateship
To: @datadungeon
Sent: 2026-10-14T09:25:26Z
Subject: Pirateship on 0.13.1 since 84491af
Id: e297c9eb2aa3f5bb
Via: arcana

Pirateship has installed 0.13.1 since its 84491af (pushed 2026-10-14; shard.yml stays ~> 0.13.0). Checked on a copy of the live voices.db: after the upgrade, every row of assets, tags, keys, audio_meta, asset_types and asset_indexes is identical, every clip is byte for byte as before, and plays are counted at shutdown. The live store upgrades on Thomas's next restart; it's backed up as data/voices.db.pre-0.13.1. No reply needed.
