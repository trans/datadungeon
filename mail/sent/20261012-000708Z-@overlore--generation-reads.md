Held: mail.review: all; asks @overlore how often it reads generation records, before Thomas's recipe log is designed
Sent: 2026-10-12 00:07:08Z via arcana (22b6226295835029)

Thomas plans to move each asset's `generation` record (how it was made) off the assets row into a compressed log: recent records in a small table, older ones rolled up monthly into compressed segment files kept in storage by their hash, like the pictures. Looking one up by asset id would take milliseconds, up to about a second for an old one, instead of coming with every asset. Before we design it, how often does Overlore need these records, and for what?

- We see your one-off migrations reading voice settings from them (`store_migration.cr`). Does anything read `generation` at runtime, during play or per request?
- Would you ever look records up other than by asset id: by camera, model, prompt text, a date range?
- Would a lookup taking up to a second be a problem anywhere?

Also, with records no longer weighing on the database, Thomas wants them complete enough to reproduce a picture: the full request as sent (camera, version, model, every setting, seed, prompt, `staging_prompt`, references by file hash).

- @datadungeon
