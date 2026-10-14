Sent: 2026-10-13 22:26 EDT via arcana (98ba0b5b23aabaac)

Thanks, and for the follow-up on the texts. Where each point landed:

1. **A store per app:** 0.13 lets stores share a bucket safely. With `shared: true` on the storage (`DD_SHARED_STORAGE=1` for dd-serve), a store never deletes a file, and it writes every file it stores even when it's already there. `object_keys` (`GET /objects`) lists the files a store uses, for the hub Thomas has proposed: a service that knows every store and clears files none of them use. Without the setting, deleting in one store could remove a file another store still uses, so set it on any bucket two stores share.
2. **Your own tags:** in the design. Each is kept as two fields, owner and name, and written `overlore:room-id`. They're searchable like any tag and can be used in your indexes. **The description's hash:** 0.13 already puts `description_hash` on every asset (the same hash in every store) and can list by it (`list_assets(description_hash:)`). The design lets an index key on it beside tags, so `content_hash` and `look` can go once 0.14's indexes do that.
3. **Pools:** `find_pool` and `count_pool_assets` stay, over a tag filter.
4. **Cost:** `cost_basis` beside `cost` (in US dollars) in 0.13, e.g. `priced: arcana-ai 0.5.2`, `reported: runware`, `estimated`.
5. **Retro:** it has left the art styles, and `ascii` waits for real ASCII art.

The smaller points:
- **Areas:** noted the onboarding hall's doors as the likely first need.
- **Opacity:** the pixels are checked, not the format, so an opaque PNG with an alpha channel passes.
- **The panel's name:** `plug` (Thomas: a stagecraft term, a scenic insert). There's also a new type, `placard`, for intros, title cards and end credits.

**One change to plan for:** a picture's fields now join as preamble, subject, description, staging, theme, style, rules, with the rules last, at `@mj`'s request. A `prompt_sent` that joins them in another order is kept whole, so it's best to compose prompts in this order before converting your 916 records.

- @datadungeon
