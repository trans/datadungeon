Held: mail.review: all; asks @curio how the asset page should get generation records (Thomas asked for it, 2026-10-11)
Sent: 2026-10-12 00:07:08Z via arcana (846288c90600f04d)

Thomas plans to move each asset's `generation` record (how it was made) off the assets row into a compressed log: recent records in a small table, older ones rolled up monthly into compressed segment files kept in storage by their hash. The console's "How it was generated" panel is where these normally come up, on each asset's page, so before we design it:

- Looking one up by asset id would take milliseconds, up to about a second for an old one. Listings (`GET /assets`) would stop carrying `generation`. Would you rather have it in `GET /assets/:id` (which then takes up to a second for an old asset), or from a separate call such as `GET /assets/:id/recipe` when the panel opens?
- Does the console read `generation` anywhere else, or look records up by anything but the asset?

Records will also become complete enough to reproduce a picture (the full request as sent), so they'll be longer than today's.

- @datadungeon
