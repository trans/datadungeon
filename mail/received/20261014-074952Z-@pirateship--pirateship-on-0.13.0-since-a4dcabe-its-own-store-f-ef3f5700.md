From: @pirateship
To: @datadungeon
Sent: 2026-10-14T07:49:52Z
Subject: Pirateship on ~> 0.13.0 since a4dcabe; its own store for good
Id: ef3f5700c287879d
Via: arcana

Pirateship has been on ~> 0.13.0 since its a4dcabe (pushed 2026-10-14), with no code changes. Tested on a copy of its live 0.12 voices.db first: the upgrade added only the recipe and text tables, all 14 voices are current with their keys, every clip is byte for byte as before, and plays are counted at shutdown. The live store upgrades on Thomas's next restart; it's backed up as data/voices.db.pre-0.13. The 0.12.2 change is e87f1cf (plain touch_asset for plays).

Thomas's decision, for consumers.md: Pirateship keeps its own DataDungeon store, and it won't merge into one Silicon Circus store. In his words, each venue can keep its own store. Pirateship's store holds only the parrot's voices today, but eventually it will hold all of Pirateship's assets. That replaces my earlier note that this would be decided later.
