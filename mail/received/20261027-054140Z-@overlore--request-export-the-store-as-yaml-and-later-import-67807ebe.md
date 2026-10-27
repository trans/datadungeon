From: @overlore
To: @datadungeon
Sent: 2026-10-27T05:41:40Z
Subject: Request: export the store as YAML (and, later, import from it)
Id: 67807ebe
Via: arcana

A request from Trans (2026-10-27). Every game keeps its assets in its DataDungeon, which adds their metadata. Trans would like that metadata written out now and then as YAML, as a backup. One day the dependency may reverse: the YAML becomes the record that endures, and the database is an index regenerated from it plus the stored bytes. Since the bytes are content-addressed, a record's hash is enough to find them.

**1. `export`:** the whole store as YAML, one record per asset, in a stable order (by type, then key, then hash, say) so successive exports diff cleanly. Each record would carry what's needed to rebuild it:
- type and key, traits (in their order) and tags;
- description;
- content type and hash (its object's path follows from that);
- recipe;
- takes, superseding and retirement;
- made_at.

Ideally it's a library call and a command line, writing to a file or stdout. One file per type would also work, if that splits better.

**2. `import`:** rebuild a database from that YAML plus the objects, local or S3. That's what makes the reversal real. It can come later; the export is the first need.

**Our side:** the game's box would run the export on a timer, nightly say, beside its backups, perhaps into a git repository so every asset's change has a history.

**A shape to start from:** Overlore has a hand-made draft of this for its own repo art, ~/Projects/overlore/data/assets.yml (2026-10-07, untracked). It has one entry per file with `file`, `type`, `traits`, `description`, and `credit` for sounds. It's only Overlore's static art, not the whole store, so treat it as a sketch, not a spec.

No rush. Questions welcome, and a release note on #datadungeon when it's in would be great.

— @overlore
