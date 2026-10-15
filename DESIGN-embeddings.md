# Embeddings: what DataDungeon embeds, and who says so

*Draft 2026-10-11, with Thomas. Nothing here is built yet.*

## Why

Semantic search (`data_dungeon/semantic`, `SemanticIndex`) works and is
tested, but no consumer uses it and `dd-serve` doesn't offer it. Before
hooking it up, what gets embedded needs a home. Today it's decided in two
places, and only one of them is stored:

- **The whole-asset embedding:** the description plus the tags named by
  `semantic_tag_keys`, an argument to `SemanticIndex.new`. It lives in each
  process's code, is the same for every type, and isn't recorded: two
  processes with different lists re-embed each other's work.
- **Facets** (0.5.7): named groups of tags, each embedded on its own
  (`hair` from `hair-color` and `hair-style`), declared in
  `register_type(…, facets:)` beside the type's key, so changing one means
  registering the type again.

The embedding model is also only in each process's setup.

## Decided (Thomas, 2026-10-11)

1. **One registry of named embeddings.** A consumer registers, per type,
   named entries, each a recipe of the parts its text is made from. The
   whole-asset embedding and facets are both just entries.
2. **Names per consumer, work shared.** Names are per consumer and type, as
   indexes are (0.11), so consumers never collide. Two entries with the same
   recipe for a type share one stored recipe and one set of vectors; the
   vectors go when the last name pointing at them is unregistered.
3. **A recipe is a set of parts, not a list.** DD writes the text in one
   fixed order, so the same set always yields the same text (and memo 0.13,
   which stores each distinct text once, embeds it once).

### What part order does to an embedding (measured 2026-10-11)

One portrait's text in `text-embedding-3-small`, cosine to the original,
and the score for the query "a red-haired adventurer with braided hair"
(`text-embedding-3-large` agrees within a few hundredths):

| Variant | Whole asset: sim | score | Hair facet: sim | score |
|---|---|---|---|---|
| original | 1.000 | 0.770 | 1.000 | 0.578 |
| tags reordered | 0.974 | 0.750 | 0.948 | 0.554 |
| description last | 0.934 | 0.712 | | |
| red → auburn | 0.950 | 0.700 | 0.845 | 0.461 |
| red → black | 0.975 | 0.723 | 0.890 | 0.457 |
| braids → short | 0.956 | 0.713 | 0.759 | 0.466 |

Transformer embeddings aren't a sum, so order moves them: in the whole
asset, reordering moves the vector as far as changing the hair colour, and
moving the description moves it further. Two things follow. A fixed order
matters, so that one set of parts always lands on one vector. And facets
earn their place: within the hair facet a colour change moves the vector
two to three times as far as reordering does, where in the whole asset it
is lost among everything else.

### How to write the parts (measured 2026-10-11)

256 characters (every mix of 4 races, hair colours, hair styles and skins),
each written five ways, searched with 12 plain-English queries ("green-
skinned orc with a black ponytail"), each with exactly one right answer
among distractors one attribute off. Top-1 is how often the right one came
first; the margin is how far it led the best wrong one.

| Format | Example | small: top-1 | margin | large: top-1 | margin |
|---|---|---|---|---|---|
| lines | `hair color: red` | 12/12 | +0.010 | 12/12 | +0.019 |
| JSON | `{"hair-color": "red", …}` | 12/12 | +0.008 | 12/12 | +0.010 |
| statements | `Hair color is red.` | 12/12 | **+0.012** | 12/12 | **+0.022** |
| values only | `red braids …` | 6/12 | +0.004 | 10/12 | +0.024 |
| hand prose | `an elf with red hair in braids …` | 11/12 | +0.013 | 12/12 | +0.022 |

- **Names matter:** values alone lose the right answer half the time on
  the small model; "red" alone doesn't say whose red.
- **JSON is the weakest labelled form,** half the margin of statements on
  the large model: the punctuation is shared by every asset and dilutes
  what differs.
- **Statements lead,** 15-25% more margin than lines, and match prose
  written by hand for the type, which DD couldn't write generically
  anyway.

Margins are a hundredth or two: everything near the top is close, which is
why a facet, compared on its own, separates better. A small synthetic test;
`bench/embedding_format.py` and `bench/embedding_order.py` rerun both.

## Proposed (to confirm)

- **Parts:** tag names, plus a short fixed list of fields: `description`,
  `prompt` (the `prompt` in `generation`, where Overlore's pictures keep
  theirs), and `view` (the view's name). No arbitrary JSON paths.
- **Text order:** fields first, as listed above, then tags by name
  alphabetically. Empty parts are left out; an entry whose parts are all
  empty has no vector for that asset.
- **Text format:** the description as written, then one short statement
  per part, `Hair color is red.`, instead of today's `hair color: red`
  lines (measured below).
- **Default entry:** a consumer's entry named `default` is what a search
  uses when it names no entry. There is no implicit one: a type with no
  entries isn't embedded.
- **One model per store,** recorded in the store on first use. Opening with
  another model raises, rather than mixing vectors that can't be compared;
  switching is an explicit call that re-embeds everything.

## Shape

```crystal
db = DataDungeon::DB.new("assets.db", consumer: "overlore")
db.register_embedding("portrait", "default", parts: %w[description art-style race])
db.register_embedding("portrait", "hair", parts: %w[hair-color hair-style])
db.unregister_embedding("portrait", "hair")
db.embeddings("portrait")  # every consumer's entries and their recipes

index = DataDungeon::SemanticIndex.new(db, model: "text-embedding-3-small", api_key: key)
index.search("red braids", asset_type: "portrait", embedding: "hair")
index.search({"hair" => "long red braids", "body" => "hulking"}, asset_type: "portrait")
  # several entries at once: an asset scores its weakest, as search_facets does today
```

Tables: `embedding_recipes (id, asset_type, parts)`, unique on the type and
its canonical parts (sorted JSON), and `asset_embeddings (consumer,
asset_type, name, recipe_id)`, keyed by the first three. Memo holds each
recipe's vectors under its own source type (`dd:<recipe id>`), so renaming
an entry, or a second consumer registering the same set, touches no
vectors. Registering a new recipe queues the type's current assets;
retired assets stay out, as now.

`dd-serve` gets a `SemanticIndex` when given a model and key: it works the
queue in the background and answers `GET /types/:type/embeddings` and
`GET /types/:type/search?q=…&embedding=…` (several entries as
`embedding.<name>=<query>`).

## Replaced

`semantic_tag_keys:`, `register_type(…, facets:)`, `search(facet:)` and
`search_facets` go; no consumer uses them (checked 2026-10-11). Facets
already registered move into the registry on first open, and memo's
existing `asset` and `<type>.<facet>` sources are dropped and queued again.

## Open

- **Scale:** every recipe's vectors share memo's one USearch index, and a
  search filters to its recipe's source type. With many recipes per type, a
  recipe is a small fraction of the index; check the filtered search's cost
  at 1M assets × several recipes before settling on one index.
- **Registering over HTTP:** indexes are registered only from code; curio
  may want to register entries.
- **Which release:** 0.16, after the standard types (Thomas, 2026-10-15).
