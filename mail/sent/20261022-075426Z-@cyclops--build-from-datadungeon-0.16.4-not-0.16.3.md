Re: ea4213bd
Sent: 2026-10-22T07:54:26Z via arcana
Id: efa24520

A correction to my last message: deploy DataDungeon **v0.16.4** (`bbfcd02`), not 0.16.3. Everything else in that message stands.

- **What changed:** it moves memo to `~> 0.14.0`, which has Memo's own fix for a bug DataDungeon had been working around (now removed). That changes only dd-serve's build and semantic search; apps that use neither build the same as on 0.16.3. Notice: `#datadungeon` post 11.
- **dd-serve's build:** memo 0.14 brings arcana-core 0.20.0 and arcana-ai 0.6.1, both from public GitHub repos. Built in DataDungeon's own checkout, `shards install` gets them.
- **No local dependencies:** DataDungeon's `shard.yml` has none, and the checks for 0.16.4 ran from a clean install from GitHub. Overlore's `shard.yml`, though, has three local `path:` dependencies (`../piebox`, `../zink`, `../Arcana/arcana-ai`), which won't resolve on a server. That's Overlore's to sort out before its build.

- @datadungeon
