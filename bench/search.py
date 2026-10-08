"""Search-box queries over DataDungeon's full-text index (asset_search).

Run with: python3 bench/search.py 1000000 /tmp/search.db
Uses only Python's standard library; deletes its database afterwards.
Replicates DD's FTS5 table (unicode61, '-' and '_' inside words) and its
page query, driven by the index in descending id order.

Measured 2026-10-08 at 1M assets (84 MB): a rare word 0.07 ms; two common
words 5.5 ms; a word in half the store 10.8 ms; counting a word's matches
9 ms. FTS5 decodes a word's whole posting list even for one page (about
20 ns per match), so a common word's page grows linearly with the store,
and a short prefix covering many words merges all their lists (43 ms for
`thing1*`). detail=none was about 3x slower, not faster.
"""

import os, random, sqlite3, statistics, sys, time

n = int(sys.argv[1]); path = sys.argv[2]
if os.path.exists(path): os.remove(path)
random.seed(11)
db = sqlite3.connect(path)
db.execute("CREATE TABLE assets (id INTEGER PRIMARY KEY, asset_type TEXT)")
db.execute("""CREATE VIRTUAL TABLE asset_search USING fts5(words, tokenize = "unicode61 tokenchars '-_'")""")
types = ["front", "sprite", "prop", "voice", "portrait"]
venues = ["boardwalk", "pirate-ship", "cattacula", "midway", "big-top"] + [f"venue{i}" for i in range(45)]
looks = ["night", "day", "dusk", "fog"]
things = [f"thing{i}" for i in range(2000)]
batch_a, batch_s = [], []
for i in range(1, n + 1):
    t = random.choice(types)
    words = [t, random.choice(venues), random.choice(looks), random.choice(things), "real" if random.random() < 0.5 else "toon"]
    batch_a.append((i, t)); batch_s.append((i, " ".join(words)))
    if len(batch_a) == 50000:
        db.executemany("INSERT INTO assets VALUES (?, ?)", batch_a)
        db.executemany("INSERT INTO asset_search (rowid, words) VALUES (?, ?)", batch_s)
        batch_a, batch_s = [], []
db.executemany("INSERT INTO assets VALUES (?, ?)", batch_a)
db.executemany("INSERT INTO asset_search (rowid, words) VALUES (?, ?)", batch_s)
db.commit()
print(f"{n:,} assets, {os.path.getsize(path)/1e6:.0f} MB")

PAGE = """SELECT a.* FROM asset_search s CROSS JOIN assets a
          WHERE asset_search MATCH ? AND a.id = s.rowid {extra} ORDER BY s.rowid DESC LIMIT 50"""

def q(*words): return " ".join(f'"{w}"*' for w in words)

def bench(label, sql, args, runs=50):
    times = []
    for _ in range(runs):
        t0 = time.perf_counter(); rows = db.execute(sql, args).fetchall(); times.append((time.perf_counter() - t0) * 1000)
    times.sort()
    print(f"{label:52} p50={statistics.median(times):8.3f} ms  p95={times[int(runs*0.95)-1]:8.3f} ms  rows={len(rows)}")

bench("common word (real: half of all)", PAGE.format(extra=""), (q("real"),))
bench("two words, any order (night boardwalk)", PAGE.format(extra=""), (q("night", "boardwalk"),))
bench("prefix (catt night)", PAGE.format(extra=""), (q("catt", "night"),))
bench("rare word (thing1234)", PAGE.format(extra=""), (q("thing1234"),))
bench("word + type filter (night, type=sprite)", PAGE.format(extra="AND a.asset_type = ?"), (q("night"), "sprite"))
bench("deep page (night, before the middle)", PAGE.format(extra="AND s.rowid < ?"), (q("night"), n // 2))
bench("count every match (night)", "SELECT COUNT(*) FROM asset_search WHERE asset_search MATCH ?", (q("night"),), runs=5)
db.close(); os.remove(path)
