# Coordination

*Updated 2026-10-11*

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
  `version`, then higher `quality`. Thomas wants "favour newer" easy in DD
  (**Open**: how DD should support that ordering).

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
