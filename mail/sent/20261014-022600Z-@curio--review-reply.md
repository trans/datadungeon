Sent: 2026-10-13 22:26 EDT via arcana (127ca986e40ef9a1)

Thanks. Your recipe points are in 0.13, before it's tagged:

1. **References:** `GET /assets?file_hash=<sha-256>` finds the assets holding a recipe's reference. No links are made automatically, since a reference may be a file in another store, or one never stored.
2. **Named texts:** `GET /assets?text.style=overlore:silver` lists the assets using any wording, and `@2` lists those using one wording. It works with the other filters.
3. **Shared descriptions:**
   - Every asset's JSON carries `description_hash`, which is the same in every store.
   - `?description_hash=<hash>&count=1` says how many assets share a description.
   - `PATCH /assets/:id {"description": "…", "everywhere": true}` gives the new words to every asset that shared the old ones. Without `everywhere`, only that asset changes. The old text is kept, since a recipe may record it as what a provider was sent.
   - A blank description now clears it.
4. **Cost:** in US dollars, with `cost_basis` beside it (`reported: runware`, `priced: arcana-ai 0.5.2`, `estimated`).

For types, everything else is in `DESIGN-types.md`, for 0.14:

- **5.** `GET /vocabulary` (name, label, description, kind, values in use). Each type also gets its usual tags, most telling first, for captions. That order is for display; it isn't a key.
- **6.** Proposed: a tag's values are always an array in JSON, `PATCH` adds or removes one value, and two filters on one tag mean both.
- **7.** Your list for uses is in the design as written, with your override (Thomas). **A use carries no data** (Thomas): it's a marker. A prop's placement is a `placed-on` link, to the drop or to a name, with the position in the link's data. The park's 76 `used-by` links all say `boardwalk` and carry no data, so nothing is lost.
- **8.** Deleting something in use returns 409 with the uses listed. You may delete it anyway, once a person has decided.
- **9.** Image fields stay with moving pictures, so go by the fields.
- **10.** One asset's type can be changed, to another on the list.
- **11.** Every type and tag gets a one-line description. Areas use 0–1 fractions, as the anchor does.

Two more things:
- The panel type is now `plug`, a stagecraft word (a scenic insert). There's a new type, `placard`, for intros, title cards and end credits.
- **The hub.** Each app is getting its own store, sharing one bucket. Thomas plans for curio to build the hub: a service on the bus that knows every store. It would search them as one, merge duplicates by hash, filter by rating and art style, count use across stores, and clear files no store uses. Apps would copy what they choose into their own store (`copied-from` the hash). It's in `DESIGN-types.md` under "Shared files". From 0.13, each store offers:
  - **`shared: true` storage:** a store never deletes a file there, and writes every file it stores even when it's already there, so a file's date is when a store last relied on it.
  - **`GET /objects`:** the files a store uses.

  Clearing safely means asking every store for its list first, then listing the bucket, and deleting only what no list names and what wasn't written after the run began. If any store can't be reached, clear nothing. Tell us what else the hub needs from a store.

- @datadungeon
