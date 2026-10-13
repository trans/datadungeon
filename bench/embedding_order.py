# How part order moves an embedding (DESIGN-embeddings.md). Needs OPENAI_API_KEY.
# Run: python3 bench/embedding_order.py
import json, math, os, urllib.request

def embed(texts, model):
    req = urllib.request.Request(
        "https://api.openai.com/v1/embeddings",
        data=json.dumps({"model": model, "input": texts}).encode(),
        headers={"Authorization": "Bearer " + os.environ["OPENAI_API_KEY"], "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return [d["embedding"] for d in json.load(r)["data"]]

def cos(a, b):
    return sum(x * y for x, y in zip(a, b)) / math.sqrt(sum(x * x for x in a) * sum(y * y for y in b))

sets = {
  "whole asset": [
    ("base",             "A human adventurer\nhair color: red\nhair style: braids\nskin: pale"),
    ("tags reordered",   "A human adventurer\nskin: pale\nhair style: braids\nhair color: red"),
    ("description last", "hair color: red\nhair style: braids\nskin: pale\nA human adventurer"),
    ("red -> auburn",    "A human adventurer\nhair color: auburn\nhair style: braids\nskin: pale"),
    ("red -> black",     "A human adventurer\nhair color: black\nhair style: braids\nskin: pale"),
    ("braids -> short",  "A human adventurer\nhair color: red\nhair style: short\nskin: pale"),
  ],
  "hair facet": [
    ("base",             "hair color: red\nhair style: braids"),
    ("reordered",        "hair style: braids\nhair color: red"),
    ("red -> auburn",    "hair color: auburn\nhair style: braids"),
    ("red -> black",     "hair color: black\nhair style: braids"),
    ("braids -> short",  "hair color: red\nhair style: short"),
  ],
}
query = "a red-haired adventurer with braided hair"
for model in ["text-embedding-3-small", "text-embedding-3-large"]:
    print("==", model)
    for name, cases in sets.items():
        vecs = embed([t for _, t in cases] + [query], model)
        q = vecs[-1]
        print(f"  {name}:  {'variant':18} sim-to-base  query-score")
        for (label, _), v in zip(cases, vecs):
            print(f"    {label:18} {cos(vecs[0], v):.4f}       {cos(q, v):.4f}")
