# Principles

*Updated 2026-10-07*

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
