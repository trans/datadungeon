# Coordination

*Updated 2026-10-19*

- Our Arcana identity is **`@datadungeon`** (it was bare `datadungeon`
  before 2026-10-04). In this project, "check mail" means Arcana, not Gmail.
  On resuming, check the directory, register if needed, and read the inbox.
- Peers: `@overlore` (Overlore, the game formerly called Infocomic, renamed
  2026-10-09 because Activision holds the Infocomics name; it was
  `@infocomics`, which notes before that date call it), `@mj`, `@memo`,
  `@curio` (the DD web UI and the
  Silicon Circus park store), and `siliconcircus` (Silicon Circus, renamed
  from `siliconcircus-dev` 2026-07-07). On 2026-10-09 `siliconcircus` had no
  mailbox and no Silicon Circus agent was registered, so mail for Cattacula
  is delivered into Cattacula's `.ai` inbox (`inbox/` there on 2026-10-11,
  the layout before the `ai` branch), where `@curio` leaves notes too.
  **Cattacula has its own agent, `@cattacula`,** since at least
  2026-10-14 (its 0.13.0 report came from it), and `@pirateship` and
  `@owl` are peers too (consumers.md).
- **`@curio` is DataDungeon's frontman** (Thomas, 2026-10-14: "like your
  sidekick, or frontman"). DD stays generic and UI-free; curio is its face
  for people (browsing, curating, with override permission on uses) and
  does the work across stores, such as the hub (DESIGN-types.md, "Shared
  files"). So what people or several stores need goes to curio, and DD
  gives each store the calls curio builds on.
- **Thomas, 2026-10-14: "let them all know" is the go-ahead.** When he
  asks for mail to go ("let X know", "let them all know"), write it and
  send it; don't hold it for a second look ("just send them please"). A
  heads-up such as a release notice has nothing in it to review. Mail he
  hasn't asked for still waits for him.
- **`#datadungeon`, an Arcana topic, holds DD's notices to every app**
  (Thomas, 2026-10-19: try "arcana's new topic boxes"; created the same
  day, the first topic on the bus). Releases and decisions that touch all
  stores are posted there with `arcana_publish`, once, instead of a
  message to each app; requests to one app (a store's piece) stay direct
  mail. Post 1 is the 0.15.2 notice. Thomas tells each agent to read the
  topic for now; @overlore and @mj were told of it directly on 2026-10-19
  (ac718d81, 4080294f). **Subscribing is left for later** (Thomas): the dot-ai
  hooks don't look at topics, so a subscription's notice is the only way
  an agent would hear of a post unprompted; a loose end in the hooks.
  `arcana_publish` files no copy, so each post is filed by hand in
  `mail/sent/` as `<time>-#datadungeon--<subject>.md`, its `Sent:` line
  naming the post's number.
- `.ai/mail/` holds our mail as files: drafts, outbox, the committed
  `sent/` record, and the inbox, where mail that didn't come live lands
  (see README.md).

## From `@mj` (2026-10-08)

- Its project is `~/Projects/mjanime` (renamed from `minanime`; a
  temporary symlink keeps the old path, so build nothing new on it). Bus
  addresses unchanged: `mj:camera`, `mj:voice`, `mj`, agent `@mj`.
- `mj:camera` has two independent capacity pools (`cameras` reports
  `pools`; the `openai` pool reaches OpenAI directly). Failing over helps
  only across pools, not between cameras in one pool.
- Each `shoot` result carries `version` (bumped rarely and deliberately
  when a camera's output changes) and `quality` (the camera's rank). A
  bump is a **freshness rank, not an expiry**: keep every image, never
  regenerate on a bump, and among images fitting a request prefer higher
  `version`, then higher `quality`. Thomas wants "favour newer" easy in DD.
  **Closed 2026-10-11:** DD ranks by `rating` then newest instead, and
  doesn't use `version`/`quality` (handoff.md).

## From `@mj` (2026-10-10)

- `view` and `light` are live on `shoot`: it takes the vector or the
  readable form, checked against our worked cases, and renders them into
  the prompt as words (expect 10-20 degrees off). Nothing is added when
  neither is asked; passing a default view everywhere would cost quality.
- Pass its `generated_at` as `made_at`; keep its `staging_prompt` (what the
  model was told) in the `generation` JSON.
- A third pool, `google` (`dnano`, `dlite`, the fastest at ~2.8 s); every
  result carries `pool`. `format` now describes the bytes (it re-encodes
  Google's JPEGs). `usd_estimated` is false only for `klein`.

## From `@mj` (2026-10-11)

- Agreed DD ranks by rating, not `version`/`quality`: both describe the
  camera, and `quality` is a rank that changes; `generator`
  (`mj:camera:flare@1`) keeps them as provenance.
- `mj:camera` now draws concurrently (arcana-core 0.17.1): shots in flight
  overlap and can come back out of order; correlation ids pair them.
  `cameras` reports `pool_limits` beside `pools`.
- Still asks that `staging_prompt` go into the `generation` JSON. DD stores
  whatever JSON the app passes, so that's the filing app's (Overlore's),
  which didn't keep it on 2026-10-11.

## From `@mj` (2026-10-14)

- Thomas decided DD owns turning `view` and `light` vectors into words; mj
  handed over its `src/arcana/view.cr` (handoff.md, "Picture prompts
  redesigned"). mj may later offer it as a bus tool for apps without DD,
  wrapping DD's copy; until then `shoot` keeps taking `view` and `light`.
- Thomas's view, under review on mj's side: mj sends exactly the prompt
  it's given, and publishes how each camera behaves; deciding what's asked
  is the calling app's job (or DD's join).
- mj's cow tests (2026-10-14): on `klein` and `flare` a positive mention
  beats a "don't" in either order; on `nano` the later instruction won 5 of
  6. So a prompt mustn't contradict itself: code settles conflicts first.

## Every outbound message needs Thomas's go-ahead

Don't send Arcana messages to other agents on your own. Thomas invites each
one case by case (confirmed 2026-07-09). His asking "want to send a message
to X?" is the invitation; a general nod doesn't cover later messages.

Reading and receiving mail is fine. Draft and offer ("want me to tell
them?"), then wait for his go-ahead for that message. He coordinates with
the other agents separately and wants to know exactly what's said to them.
Since 2026-10-11 the draft is a file in `mail/drafts/` with a `Held:` line,
and `mail.review: all` in `config.yml` records this rule; sent messages
are kept in `mail/sent/`. Messages before then are in Arcana and in this
note's history, not in `sent/`.
