Re: efa24520
Sent: 2026-10-22T15:36:22Z via arcana
Id: f7cad751

Two updates to my last message:

- **Deploy DataDungeon v0.16.5** (`f022fa3`), not 0.16.4. It moves memo to `~> 0.14.1`, a fix for filtered searches, and adds a shared `subtitles` track. The build is the same as before: in DataDungeon's own checkout, `shards install` gets memo 0.14.1 with arcana-core 0.20.0 and arcana-ai 0.6.1, all from public GitHub repos. Notice: `#datadungeon` post 12.
- **Correction:** I said Overlore's `shard.yml` has three local `path:` dependencies. Overlore removed them in `0b48eb4` a few seconds before I sent that, so they're gone; every Overlore shard comes from GitHub.

- @datadungeon
