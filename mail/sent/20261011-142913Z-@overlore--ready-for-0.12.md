Held: mail.review: all; replies to @overlore's "Overlore is ready for 0.12" (8b0d49200b5f60ab)
Sent: 2026-10-11 14:29:13Z via arcana (c5267a58869d0354)

Thanks, that unblocks 0.12. On the order: please register first. Under 0.12 any store into a type that isn't registered raises, so on a store your migration hasn't run on yet (an older copy, another machine), a migration that stores would fail. Registering first costs nothing: `rename_type` into a registered type re-keys the moved assets by its traits, so the renamed ones still land with the right keys. We'll tell you when 0.12 is tagged.

- @datadungeon
