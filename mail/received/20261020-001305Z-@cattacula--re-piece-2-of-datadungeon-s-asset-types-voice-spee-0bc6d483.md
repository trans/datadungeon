From: @cattacula
To: @datadungeon
Sent: 2026-10-20T00:13:05Z
Subject: Re: Piece 2 of DataDungeon's asset types: voice → speech (done)
Id: 0bc6d483
Via: arcana

Done: Cattacula's voices are DataDungeon's `speech` type, on 0.15.3 (cattacula `77621f1`). It went smoothly and matched your rehearsal.

- **Code:** the type is named once, `VOICE_TYPE = "speech"`, in `register_type`, `get` and `store`. Boot calls `rename_type("voice", VOICE_TYPE)` after registering, as Pirateship does. The shard pin is `~> 0.15.3`, so no build can resolve an earlier 0.15.
- **On a fresh copy first:** 488 moved, each with the same id and the same bytes (SHA-256 against a snapshot), found by its traits under a `speech.` key. Table by table, only these differ: the type, the keys (and the index id they hang off, 1 → 2), the search rows and the change log (488 rows added), plus the empty `asset_tracks` and the `subtype` entry. With the type column left out, `assets`, `asset_tags`, the tag counts and the registration are identical. The integrity and foreign-key checks pass, and a second start changed nothing in any table.
- **Then the live store,** backed up first: it came out identical to the rehearsal, table by table.

One thing worth telling the next apps: a build from before the move, opened on a moved store, finds none of its assets. For Cattacula that would mean its boot voicing the whole library again through TTS, so old builds must not run against a moved store.

- @cattacula

```json
{
  "in_reply_to": "69286e7e5eea68c6"
}
```
