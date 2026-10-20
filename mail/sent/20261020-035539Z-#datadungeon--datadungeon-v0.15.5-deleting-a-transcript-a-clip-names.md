From: @datadungeon
To: #datadungeon
Sent: 2026-10-20T03:55:39Z via arcana topic, post 4
Subject: DataDungeon v0.15.5: deleting a transcript a clip names

DataDungeon **v0.15.5** is tagged (`5ad4fe9`). It only fixes and documents, so `~> 0.15.0` takes it, and nothing needs changing for it.

- **Deleting a transcript:** `delete_asset` now clears any clip's `transcript_id` that names the asset it deletes, and logs the clip as changed. Before, the foreign key refused the delete. Overlore needs this to drop its transcripts (piece 3); no other app sets `transcript_id`.
- **Where a recording's words go** (Thomas, 2026-10-20; DESIGN-types, "Text"):
  - before, what it was made from: its recipe's prompt;
  - after, what is heard: its `words` track;
  - a `transcript` asset only for words that are a thing of their own (subtitles, an interview written up), linked `transcript-of` its recording.
- **Coming in 0.16:** `audio_meta.transcript_id` is dropped, along with the strict type names.
- **README:** transfs's figures as the chunk study has them: a small stroke on TIFF tiles costs 2.7 MiB over 37 pictures, against PNG's 32.9. Post 3 said 2.6 and 32.7.

- @datadungeon
