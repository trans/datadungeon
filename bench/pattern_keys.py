"""Pattern matching on keys whose traits are sorted by name.

Run with: python3 bench/pattern_keys.py 1000000 /tmp/pattern_keys.db
Uses only Python's standard library; deletes its database afterwards.
Each key holds 8 trait values in alphabetical order of trait name; queries
fix some traits and leave the rest open (GLOB). Exact keys and fixed leading
traits use the index; an open leading trait scans every key, so its time
grows linearly with the store. Measured 2026-10-08 at 1M keys: exact
0.005 ms, first 3 fixed 0.8 ms, first 2 fixed with gaps 4.8 ms, first open
79 ms, only the last fixed 88 ms.
"""

import random, sqlite3, statistics, sys, time, os
n = int(sys.argv[1]); path = sys.argv[2]
if os.path.exists(path): os.remove(path)
random.seed(7)
# traits sorted by name, with realistic numbers of values
traits = [("art-style", 6), ("gender", 3), ("hair-color", 12), ("hair-length", 5),
          ("outfit", 50), ("race", 12), ("rating", 4), ("skin", 10)]
db = sqlite3.connect(path)
db.execute("CREATE TABLE a (id INTEGER PRIMARY KEY, k TEXT)")
db.execute("CREATE INDEX a_k ON a(k)")
def key(vals): return ".".join(vals)
rows = []
for i in range(n):
    rows.append((i, key([f"{name[:2]}{random.randrange(card)}" for name, card in traits])))
db.executemany("INSERT INTO a VALUES (?, ?)", rows); db.commit()
sample = [r[1] for r in random.sample(rows, 200)]

def bench(label, make):
    times, found = [], []
    for k in sample[:100]:
        q, arg = make(k.split("."))
        t = time.perf_counter(); res = db.execute(q, (arg,)).fetchall(); times.append((time.perf_counter() - t) * 1000)
        found.append(len(res))
    times.sort()
    print(f"{label:58} p50={statistics.median(times):9.3f} ms  p95={times[94]:9.3f} ms  rows={min(found)}..{max(found)}")

print(f"{n:,} keys, {os.path.getsize(path)/1e6:.0f} MB")
bench("exact key (all 8 traits)", lambda v: ("SELECT id FROM a WHERE k = ?", ".".join(v)))
bench("pattern, first 3 fixed, rest open (prefix)", lambda v: ("SELECT id FROM a WHERE k GLOB ?", ".".join(v[:3]) + ".*"))
bench("pattern, first 2 fixed + race + rating", lambda v: ("SELECT id FROM a WHERE k GLOB ?", f"{v[0]}.{v[1]}.*.*.*.{v[5]}.{v[6]}.*"))
bench("pattern, first trait open (hair, race, rating)", lambda v: ("SELECT id FROM a WHERE k GLOB ?", f"*.*.{v[2]}.*.*.{v[5]}.{v[6]}.*"))
bench("pattern, only skin fixed (last trait)", lambda v: ("SELECT id FROM a WHERE k GLOB ?", f"*.{v[7]}"))
db.close(); os.remove(path)
