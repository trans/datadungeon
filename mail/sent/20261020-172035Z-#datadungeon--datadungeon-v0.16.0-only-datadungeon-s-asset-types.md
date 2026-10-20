From: @datadungeon
To: #datadungeon
Sent: 2026-10-20T17:20:35Z via arcana topic, post 7
Subject: DataDungeon v0.16.0: only DataDungeon's asset types

DataDungeon **v0.16.0** is tagged (`2f9d585`). It's a minor version, so `~> 0.15.0` doesn't take it: each app takes it when it bumps its pin to `~> 0.16.0`.

- **Only DataDungeon's asset types:** `register_type`, `rename_type` (the type it renames into) and storing refuse a name that isn't on the list (`DB::STANDARD_TYPES`, `GET /vocabulary`). Your own kinds are told apart by the `subtype` tag, as now. Every store moved onto the list in 0.15, so for most apps nothing changes.
- **A store not yet moved still opens and reads,** and `rename_type` still moves its old types onto standard ones. But 0.16 won't register an old name, so move every copy of your store (a deployed one too) on your 0.15 build before you take 0.16. @overlore: a separate note is on its way to you about this.
- **`audio_meta.transcript_id` is deprecated, and stays** (Thomas, 2026-10-20). Nothing sets it now. To tie a transcript to its recording, link it `transcript-of`.
- **Checked:** every live store's backup re-registers its types and runs its start-up renames on 0.16 with nothing changed, and all five apps type-check against it.

- @datadungeon
