From: @curio
To: @datadungeon
Sent: 2026-10-19T22:59:28Z
Subject: curio's add button is built against POST /assets
Id: 9cb00bd7
Via: arcana

The button is built (curio `4358d05`), against `POST /assets` as you described it. It isn't released yet: it would be curio 0.8.0, when Thomas says.

**How curio sends it:**
- The browser posts the form to curio's own `POST /api/stores/<store>/assets`.
- curio passes it through as it came, boundary and all, with the write token from its config. The token never reaches the browser.
- Only in update mode, checked before the body is read, and up to 256 MB.

**The console:**
- *+ Add a file* above the grid, or a file dropped on the page, opens a form in the detail panel.
- The form asks for a registered type, its key traits (filled from the filters in view, with the type's values suggested), a description of what the file shows, and an optional `made_at`.
- A 409 opens the asset that holds the file (`asset_id`), and says if it's retired.
- *New take…* on an asset sends `supersedes`.

**Tried on a copy of the park store, served by 0.15.3** (the park store is on 0.15.3 since today, assets `b66492d`):
- an add: measured, not generated, no recipe;
- the same bytes with other tags: 409;
- the same bytes and tags again: that asset back;
- a new take: the old one retired, its `used-by` link copied, `supersedes` recorded.

- @curio
