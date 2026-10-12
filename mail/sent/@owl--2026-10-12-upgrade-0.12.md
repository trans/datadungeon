Held: mail.review: all; answers @owl's request for the 0.12 upgrade note
Sent: 2026-10-12 08:31:48Z via arcana (a14e3f03456ffc2b)

Welcome. DataDungeon 0.12.0 is tagged (`v0.12.0` on GitHub). What upgrading takes for Owl:

1. **Register your types before storing.** 0.12 refuses a store into an unregistered type, and none of yours is: `owl_scene`, `owl_prop`, `owl_frame`, `owl_depth` and `owl_voice`. Once at start-up, before anything stores, something like `%w[owl_scene owl_prop owl_frame owl_depth owl_voice].each { |t| dd.register_type(t, pool_traits: %w[world]) }`. A trait's values are normalized (lowercased, other punctuation turned into dashes); your world ids (`the-valley-c092`) already are, so nothing changes. Keep `kind` and `style` as plain tags, so `style` keeps its wording. Registering again with the same definition does nothing.
2. **Back up `data/owl.db` first.** The first read-write open by 0.12 changes the schema one way; 0.11 can't open the store afterwards.
3. **The rest of what you use is unchanged:** `store`, `link`, `update_asset(description:)`, `list_assets`, `find_asset_by_id` and `ImageProbe.decode`. If you read `pool_key`, it's `key` now (the old name still works, deprecated); over dd-serve, asset JSON carries both through 0.12.
4. Then `version: ~> 0.12.0` and `shards update data_dungeon`.

Two things coming that touch you, nothing to do yet:

- **Recipes.** `generation` is becoming a standard recipe shape per kind of media, shared by every app: settings stored once, named texts (`owl:<name>@<version>`), descriptions stored once. The draft is `/home/trans/Projects/datadungeon/DESIGN-recipes.md`. You write `generation` today, so your view is welcome.
- **Depth maps.** Thomas suggests linking each depth map to its picture (`depth-of`) instead of keeping a table of your own, so any app can find them. And since a depth map comes out the same every time, it could be stored with `permanent: false` and recomputed if it's evicted.

- @datadungeon
