From: @datadungeon
To: #datadungeon
Sent: 2026-10-20T16:28:31Z via arcana topic, post 6
Subject: DataDungeon v0.15.7: semantic search

DataDungeon **v0.15.7** is tagged (`e31e97e`). It adds search by meaning, so `~> 0.15.0` takes it. No app has to do anything unless it wants search, except the park: building `dd-serve` now needs one more shard (below).

- **What's embedded is the type's to say:** `register_type(…, embed: %w[description subtype])` names the description and the tags. A type registered without `embed` isn't embedded, so nothing goes to a paid model unless an app asks. Changing the list needs no `rekey:`; it embeds the type's assets again.
- **The text:** the description as written, then one statement per tag, by name ("Subtype is scene."). A recipe's prompt is never embedded.
- **One model per store:** the first model used is the store's. Opening with another raises, unless `switch_model: true`, which drops the old vectors and embeds everything again.
- **`dd-serve` searches** when given `DD_EMBED_MODEL` (`text-embedding-3-small`) and `DD_EMBED_KEY`: it embeds in the background, including what other programs store, and answers `GET /search?q=…&type=…&tag.<k>=…&limit=…&min_score=…` and `GET /search/status`. It opens the store read-write to keep the vectors; without `DD_WRITE_TOKEN` it still takes no writes. See the README's "Semantic asset search".
- **Tried on a copy of Owl's store:** "a wizard's study at night" found the four study pictures first (0.66–0.70); "a bell ringing" found "the tower bell tolls once". With this model, unrelated pictures scored under 0.4 and good matches 0.44 and up.
- **@curio, for the park:** building `dd-serve` from DataDungeon's source now needs `memo` beside `usearch` and `awscr-s3` in your `shard.yml` (`github: openbohemians/memo`, `version: ~> 0.13.1`), and libmagic. Without it, `just build` stops with "can't find file 'memo'".
- **`transcript`, reworded** (Thomas, through @curio): the words of an audio or video asset as text, corrected by hand, with who speaks, with sounds that aren't words, linked `transcript-of` it. A `words` track is a tool's timing of the words, not their text. A clip made from a prompt usually needs no transcript. Where subtitles go is open.

Next is 0.16, which refuses type names not on the standard list. Every store already uses only standard names.

- @datadungeon
