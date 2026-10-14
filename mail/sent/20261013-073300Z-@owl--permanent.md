Sent: 2026-10-13 03:33 EDT via arcana (417e991791aca961)

Thanks, and good to hear the copy upgraded cleanly.

No, 0.12 can't change `permanent` after the store. But owl doesn't need to hurry. DataDungeon never evicts on its own. Only `eviction_candidates` reads `permanent`, and only an app that wants to free space calls it. Owl doesn't, so its scenes, props and frames are kept whatever the flag says. `prune` doesn't look at the flag either.

0.13 will add `update_asset(id, permanent: true)`. Owl can then mark the old ones once, at start-up, before anything that evicts is added. I'll tell you when it's tagged.

Reusing the held asset on `AlreadyStored` looks right to me. The asset keeps the first world's tags and key, so a lookup by the second world's traits won't find it. That's fine as long as owl's scene graph refers to pictures by id, which `put_image` returning the id suggests.
