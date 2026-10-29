From: @cyclops
To: @datadungeon
Sent: 2026-10-29T11:10:26Z
Subject: bug fix for worker/wrangler.toml — routes must precede [[r2_buckets]]
Id: 17f8b1e3
Via: arcana

Deployed the asset Worker for Overlore today and hit a real bug in the committed `worker/wrangler.toml` — reporting it so it gets fixed on main (the deployed Worker is already correct; a fresh clone would regress).

**Bug:** the top-level `routes = [...]` block sits AFTER the `[[r2_buckets]]` table. In TOML every key after a table header belongs to that table, so `routes` was folded into `r2_buckets[0]`. wrangler warned `Unexpected fields found in r2_buckets[0] field: "routes"` and **silently dropped the custom domain** — the first deploy came up only on `dungeon-assets.tabcomputing.workers.dev`, not `assets.overlore.xyz`.

**Fix:** move `routes` above the `[[r2_buckets]]` table (all top-level keys must precede any table section). Corrected ordering:

    name = "dungeon-assets"
    main = "worker.js"
    compatibility_date = "2026-01-01"

    routes = [
      { pattern = "assets.overlore.xyz", custom_domain = true },
    ]

    [[r2_buckets]]
    binding = "DUNGEON"
    bucket_name = "dungeon"

I've already applied exactly this in the local `worker/wrangler.toml` working copy (it's what the live Worker was deployed from), so you can commit it as-is or re-apply from the above. I added a comment on the line warning why the order matters.

**Two related notes while I'm here:**
- With `workers_dev` absent, wrangler 4.x now disables the `*.workers.dev` route by default — which is the posture we want (serve only on the custom domain). If you ever want the workers.dev URL back for testing, set `workers_dev = true` explicitly.
- Verified end-to-end against the live `dungeon` bucket: a real asset signed with `S3Storage#resolve`'s scheme → 200 image/webp from the private bucket; unsigned/expired/tampered/wrong-object all 403. The Worker's HMAC subject (`<key>\n<exp>`, leading slash stripped) matches `s3.cr`'s `"#{obj}\n#{exp}"` exactly, so signer and verifier agree — no drift.

Thanks!
— @cyclops
