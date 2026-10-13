# Which text format retrieves best (DESIGN-embeddings.md). Needs OPENAI_API_KEY.
# Run: python3 bench/embedding_format.py text-embedding-3-small text-embedding-3-large
import itertools, json, math, os, sys, urllib.request

def embed(texts, model):
    out = []
    for i in range(0, len(texts), 512):
        req = urllib.request.Request(
            "https://api.openai.com/v1/embeddings",
            data=json.dumps({"model": model, "input": texts[i:i + 512]}).encode(),
            headers={"Authorization": "Bearer " + os.environ["OPENAI_API_KEY"], "Content-Type": "application/json"})
        with urllib.request.urlopen(req) as r:
            out += [d["embedding"] for d in json.load(r)["data"]]
    return out

def cos(a, b):
    return sum(x * y for x, y in zip(a, b)) / math.sqrt(sum(x * x for x in a) * sum(y * y for y in b))

RACES, COLORS = ["human", "elf", "orc", "dwarf"], ["red", "black", "blonde", "silver"]
STYLES, SKINS = ["braids", "short", "long", "ponytail"], ["pale", "dark", "green", "tan"]
STYLE_PHRASE = {"braids": "in braids", "short": "cut short", "long": "worn long", "ponytail": "in a ponytail"}
DESC = "A fantasy adventurer."
chars = [dict(zip(["race", "hair-color", "hair-style", "skin"], c))
         for c in itertools.product(RACES, COLORS, STYLES, SKINS)]

def tags(c):  # alphabetical by name, as the design writes them
    return sorted(c.items())

FORMATS = {
  "lines":      lambda c: DESC + "\n" + "\n".join(f"{k.replace('-', ' ')}: {v}" for k, v in tags(c)),
  "json":       lambda c: json.dumps({"description": DESC, **dict(tags(c))}),
  "statements": lambda c: DESC + " " + " ".join(f"{k.replace('-', ' ').capitalize()} is {v}." for k, v in tags(c)),
  "values":     lambda c: DESC + " " + " ".join(v for _, v in tags(c)),
  "prose*":     lambda c: f"{DESC[:-1]}: {'an' if c['race'][0] in 'aeiou' else 'a'} {c['race']} with "
                          f"{c['hair-color']} hair {STYLE_PHRASE[c['hair-style']]} and {c['skin']} skin.",
}
QUERIES = [
  ("a dwarf with red braided hair and tan skin",        ("dwarf", "red", "braids", "tan")),
  ("pale elf, long silver hair",                        ("elf", "silver", "long", "pale")),
  ("green-skinned orc with a black ponytail",           ("orc", "black", "ponytail", "green")),
  ("a blonde human with short hair and dark skin",      ("human", "blonde", "short", "dark")),
  ("dark-skinned dwarf, short black hair",              ("dwarf", "black", "short", "dark")),
  ("an elf with green skin and red hair in a ponytail", ("elf", "red", "ponytail", "green")),
  ("tan human with long blonde hair",                   ("human", "blonde", "long", "tan")),
  ("orc, pale skin, silver braids",                     ("orc", "silver", "braids", "pale")),
  ("silver-haired dwarf with a ponytail and green skin",("dwarf", "silver", "ponytail", "green")),
  ("human with black braids and pale skin",             ("human", "black", "braids", "pale")),
  ("red-haired elf, hair cut short, dark skin",         ("elf", "red", "short", "dark")),
  ("orc with long red hair and tan skin",               ("orc", "red", "long", "tan")),
]
key = lambda c: (c["race"], c["hair-color"], c["hair-style"], c["skin"])

print(f"{len(chars)} characters, {len(QUERIES)} queries. prose* is a hand-written template per type (not generic).")
for model in sys.argv[1:]:
    qv = embed([q for q, _ in QUERIES], model)
    print(f"\n== {model}")
    print(f"  {'format':11} top-1  MRR    attrs right in top 5 (of 4)  margin")
    for name, fmt in FORMATS.items():
        dv = embed([fmt(c) for c in chars], model)
        top1 = rr = attrs = margin = 0.0
        for (q, target), v in zip(QUERIES, qv):
            scored = sorted(((cos(v, d), c) for d, c in zip(dv, chars)), key=lambda x: -x[0])
            rank = next(i for i, (_, c) in enumerate(scored) if key(c) == target) + 1
            top1 += rank == 1
            rr += 1 / rank
            attrs += sum(sum(a == b for a, b in zip(key(c), target)) for _, c in scored[:5]) / 5
            best_wrong = next(s for s, c in scored if key(c) != target)
            margin += next(s for s, c in scored if key(c) == target) - best_wrong
        n = len(QUERIES)
        print(f"  {name:11} {int(top1):2}/{n}  {rr / n:.3f}  {attrs / n:.2f}                         {margin / n:+.4f}")
