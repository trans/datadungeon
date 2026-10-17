# Principles

*Updated 2026-10-16*

## DD stays generic

DataDungeon serves several apps (Infocomic, Cattacula, Pirateship, Silicon
Circus venues, future ones). Thomas, 2026-10-06: don't get embroiled in
coding things just for Infocomic's use case.

- When a consumer asks for something, find the generic capability underneath
  and build only that: "depicted items" became set-valued traits, "embed the
  customization" became per-type embedding sources. The app's policy and
  vocabulary stay in the app. If a request has no generic form, say so and
  suggest it live in the consumer.
- Use neutral examples in the README and code comments; app-flavoured
  examples are fine in specs.
- 0.7.0 moved the last Infocomic-only code (prompts, portrait index, image
  cache layout) out to Infocomic.

## Be very careful with deleting

Thomas, 2026-10-13, reviewing 0.13. Whatever DataDungeon deletes, replaces
or drops is gone for every app sharing the store.

- Keep by default; deleting or replacing takes an explicit argument
  (`set_recipe(replace: true)`, `drop_generation: true`), never a default.
- Don't add a sweep (delete what nothing refers to) unless someone needs
  it: a later table that refers to the same rows, missed by the sweep,
  turns it into data loss. 0.13 dropped its `prune_texts` for this.
- Let SQLite refuse instead: a foreign key on every reference to shared
  rows (texts), so a mistaken delete fails rather than orphans.
- A migration that drops a column first checks every value reads back the
  same from where it moved, and raises otherwise, so the open's
  transaction leaves the store as it was.
- No app deletes for everyone: an app drops its own use (DESIGN-types.md,
  pruning).

## Each store is one owner's

Thomas, 2026-10-16. A store belongs to the app that opens it (its
`consumer:`) and that app's dd-serve. An app that wants another store's
assets copies the records into its own (`copied-from`; a provenance table
when copying is built), and the bytes stay one object in the shared R2
bucket, which no store deletes from. So nothing is built for several apps
sharing one store: uses, owner tags and refusing a delete while another
app uses an asset were dropped, and the hub waits until stores connect.

**Pictures stay in their app** (Thomas, 2026-10-17: "you are probably
correct"). Each app words its own styles for its own models, so one art
style looks different from app to app; Owl starts from what a player asks
for and Overlore from what its game needs; and style, theme and rating
multiply the misses. On the store copies (2026-10-17) Owl and Overlore
shared no art style at all (Owl's are watercolor), and the one overlap was
photorealism, Overlore's 83 and the park's 61. So nothing more is built
for sharing pictures across apps until a real case shows up: photorealism
between Overlore and the park, or assets with no style (sound effects).
Reuse pays within an app (Overlore's heads on bodies, Owl serving one
player's picture to another), which semantic search is for. **There are no
standard styles** either (Thomas, 2026-10-17): each app names, words and
tags its own. Sharing styles between apps is the hub's to coordinate,
later: a lookup of what each store uses, so a store can adopt another's.
Before acting on a decision relayed by another agent, check which parts
were Thomas's and which were the agent's own asks.

## Freeze what no app uses

Thomas, 2026-10-16, after an independent review found DataDungeon
over-engineered in places (about 2,500-3,000 of 7,300 lines serving no
caller). Keep what exists, extend nothing no app uses yet: MatchIndex,
per-consumer indexes, views/light/keyframes beyond what's there, the 0.15
types and several values per tag. SemanticIndex stays live: players will
find characters matching their customization prompts with it. Removing
the pre-0.12 migrations waits until we've checked no store is missed. When
a consumer asks for something new, build the smallest thing that serves
that call.

## No underscores in asset names

Thomas, 2026-10-07: asset type, trait and tag names use dashes or nothing
(`art-style`, `artstyle`), not underscores. DD accepts both, since other
apps may use underscores, but its README examples use dashes. Crystal
identifiers in DD's own API (`pool_key`) are unaffected.

## The plain design comes first

Lead with the simplest version that meets the requirement, and prefer
formats a person can read at the sqlite3 prompt. In the 2026-10-05 key
design Thomas moved from SHA-256-of-CBOR keys to plain dotted values
(`golden.pg.f.human.tan-skin.red-hair`): "I think you make it more
complicated than it needs to be". He preferred per-trait labels over a
compound-segment scheme.

Mention heavier alternatives (hashing, enumeration, extra separators) only
with the concrete problem they'd solve. Do raise real correctness costs,
such as an ambiguity that would merge distinct values; he wants those
raised, then decides.

## Design for scale, not for today's sizes

Thomas, 2026-10-08: "You have to stop doing 'fast enough for current
sizes'; we need fast enough for a lot more than current sizes." Today's
stores (hundreds to thousands of assets) are not an argument for a design.
Choose structures that stay fast at far larger sizes (indexed lookups,
keyset paging, an ANN or full-text index rather than a scan), and say how a
proposal behaves as a store grows. This refines the next section: build
things simply and get them working, but on designs that scale.

## Working first, then optimize

Thomas, 2026-10-07: "I don't want to go crazy setting up elaborate fake test
scenarios, just yet at least. We need to get it all working reasonably well
and then optimize." There's an Infocomic demo coming with unknown traffic,
but he said to stop worrying about it.

- Make features work correctly and simply. Don't build elaborate load tests,
  fake services (such as a fake embedding API) or demo hardening unless asked.
- Fix real bugs found along the way, as with BEGIN IMMEDIATE, which the
  simple `bench/concurrency.cr` found.
- Deferred: @memo's Memo-under-load checklist (handoff.md item 7). Memo stays
  in DD's SQLite file for now.
