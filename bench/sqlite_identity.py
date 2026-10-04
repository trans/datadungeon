"""Compare DataDungeon's canonical lookup with indexed attribute lookups.

Run with: python3 bench/sqlite_identity.py 100000
Uses only Python's standard library and deletes its temporary SQLite database.
The workload models infocomic portraits: exact lookup on five identity tags,
plus candidate lookup on style/rating/race/gender.
"""

import hashlib
import random
import sqlite3
import statistics
import sys
import tempfile
import time
from pathlib import Path


STYLE = "art_style"
FIELDS = (STYLE, "rating", "race", "gender", "description_hash")
EXACT_TAG_SQL = """
SELECT a.id FROM assets a JOIN asset_tags t ON t.asset_id = a.id
WHERE a.asset_type = ? AND (
  (t.tag_key = 'art_style' AND t.tag_value = ?) OR
  (t.tag_key = 'rating' AND t.tag_value = ?) OR
  (t.tag_key = 'race' AND t.tag_value = ?) OR
  (t.tag_key = 'gender' AND t.tag_value = ?) OR
  (t.tag_key = 'description_hash' AND t.tag_value = ?))
GROUP BY a.id HAVING COUNT(*) = 5
"""
EXACT_ANCHORED_SQL = """
SELECT a.id FROM asset_tags d JOIN assets a ON a.id = d.asset_id
WHERE a.asset_type = 'portrait'
  AND d.tag_key = 'description_hash' AND d.tag_value = ?
  AND EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = 'art_style' AND t.tag_value = ?)
  AND EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = 'rating' AND t.tag_value = ?)
  AND EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = 'race' AND t.tag_value = ?)
  AND EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = 'gender' AND t.tag_value = ?)
"""
FUZZY_TAG_SQL = """
SELECT a.id FROM assets a JOIN asset_tags t ON t.asset_id = a.id
WHERE a.asset_type = ? AND (
  (t.tag_key = 'art_style' AND t.tag_value = ?) OR
  (t.tag_key = 'rating' AND t.tag_value = ?) OR
  (t.tag_key = 'race' AND t.tag_value = ?) OR
  (t.tag_key = 'gender' AND t.tag_value = ?))
GROUP BY a.id HAVING COUNT(*) = 4
"""
FUZZY_ANCHORED_SQL = """
SELECT a.id FROM asset_tags r JOIN assets a ON a.id = r.asset_id
WHERE a.asset_type = 'portrait'
  AND r.tag_key = 'race' AND r.tag_value = ?
  AND EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = 'art_style' AND t.tag_value = ?)
  AND EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = 'rating' AND t.tag_value = ?)
  AND EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = 'gender' AND t.tag_value = ?)
"""


def canonical_key(values):
    pairs = sorted(zip(FIELDS, values))
    payload = "\n".join(f"{key}={value}" for key, value in pairs)
    return hashlib.sha256(payload.encode()).hexdigest()


def percentile(values, fraction):
    values = sorted(values)
    return values[min(len(values) - 1, int((len(values) - 1) * fraction))]


def measure(conn, name, cases, query, warmups=2):
    for case in cases[:warmups]:
        query(conn, case)
    samples = []
    counts = []
    for case in cases:
        start = time.perf_counter_ns()
        rows = query(conn, case)
        samples.append((time.perf_counter_ns() - start) / 1_000_000)
        counts.append(len(rows))
    print(f"{name:20s} p50={statistics.median(samples):9.3f} ms "
          f"p95={percentile(samples, 0.95):9.3f} ms "
          f"rows={min(counts)}..{max(counts)}")
    return counts


def main(count):
    rng = random.Random(9173)
    exact_ids = set(rng.sample(range(1, count + 1), 30))
    exact_cases = []
    fuzzy_cases = []

    with tempfile.TemporaryDirectory(prefix="dd-lookup-bench-", dir=Path(__file__).resolve().parent) as directory:
        db_path = Path(directory) / "assets.sqlite"
        conn = sqlite3.connect(db_path)
        conn.execute("PRAGMA journal_mode=OFF")
        conn.execute("PRAGMA synchronous=OFF")
        conn.execute("PRAGMA cache_size=-65536")
        conn.executescript("""
          CREATE TABLE assets (id INTEGER PRIMARY KEY, asset_type TEXT NOT NULL, canonical_key TEXT NOT NULL);
          CREATE TABLE asset_tags (
            asset_id INTEGER NOT NULL, tag_key TEXT NOT NULL, tag_value TEXT NOT NULL,
            PRIMARY KEY (asset_id, tag_key));
          CREATE TABLE portrait_attributes (
            asset_id INTEGER PRIMARY KEY, art_style TEXT, rating TEXT, race TEXT,
            gender TEXT, description_hash TEXT);
        """)

        assets, tags, attrs = [], [], []
        for asset_id in range(1, count + 1):
            style = "golden" if rng.random() < 0.45 else f"style{rng.randrange(7)}"
            description_hash = hashlib.sha256(f"description:{asset_id}".encode()).hexdigest()
            values = (style, f"rating{rng.randrange(3)}", f"race{rng.randrange(12)}",
                      f"gender{rng.randrange(3)}", description_hash)
            assets.append((asset_id, "portrait", canonical_key(values)))
            tags.extend((asset_id, key, value) for key, value in zip(FIELDS, values))
            attrs.append((asset_id, *values))
            if asset_id in exact_ids:
                exact_cases.append(values)
            if asset_id % max(1, count // 30) == 0 and len(fuzzy_cases) < 30:
                fuzzy_cases.append(values[:4])
            if len(assets) == 5000:
                conn.executemany("INSERT INTO assets VALUES (?, ?, ?)", assets)
                conn.executemany("INSERT INTO asset_tags VALUES (?, ?, ?)", tags)
                conn.executemany("INSERT INTO portrait_attributes VALUES (?, ?, ?, ?, ?, ?)", attrs)
                assets.clear(); tags.clear(); attrs.clear()
        if assets:
            conn.executemany("INSERT INTO assets VALUES (?, ?, ?)", assets)
            conn.executemany("INSERT INTO asset_tags VALUES (?, ?, ?)", tags)
            conn.executemany("INSERT INTO portrait_attributes VALUES (?, ?, ?, ?, ?, ?)", attrs)
        conn.commit()
        conn.executescript("""
          CREATE INDEX idx_assets_lookup ON assets(asset_type, canonical_key);
          CREATE INDEX idx_tags_kv ON asset_tags(tag_key, tag_value);
          CREATE INDEX idx_portrait_attributes ON portrait_attributes(
            art_style, rating, race, gender, description_hash);
        """)
        print(f"assets={count:,} database={db_path.stat().st_size / 1_000_000:.1f} MB")

        samples = 12 if count >= 500_000 else 30
        exact_cases = exact_cases[:samples]
        fuzzy_cases = fuzzy_cases[:samples]
        exact = [
            ("canonical hash", lambda db, v: db.execute(
                "SELECT id FROM assets WHERE asset_type = 'portrait' AND canonical_key = ? LIMIT 1",
                (canonical_key(v),)).fetchall()),
            ("current tag query", lambda db, v: db.execute(
                EXACT_TAG_SQL, ("portrait", *v)).fetchall()),
            ("anchored tag query", lambda db, v: db.execute(
                EXACT_ANCHORED_SQL, (v[4], *v[:4])).fetchall()),
            ("typed attributes", lambda db, v: db.execute(
                "SELECT asset_id FROM portrait_attributes WHERE art_style = ? AND rating = ? "
                "AND race = ? AND gender = ? AND description_hash = ? LIMIT 1", v).fetchall()),
        ]
        print("exact five-trait lookup (including unique description_hash):")
        for name, query in exact:
            counts = measure(conn, name, exact_cases, query)
            assert set(counts) == {1}, (name, counts)
        for case in exact_cases[:3]:
            expected = {row[0] for row in exact[0][1](conn, case)}
            assert all({row[0] for row in query(conn, case)} == expected for _, query in exact)

        fuzzy = [
            ("current tag query", lambda db, v: db.execute(
                FUZZY_TAG_SQL, ("portrait", *v)).fetchall()),
            ("anchored tag query", lambda db, v: db.execute(
                FUZZY_ANCHORED_SQL, (v[2], v[0], v[1], v[3])).fetchall()),
            ("typed attributes", lambda db, v: db.execute(
                "SELECT asset_id FROM portrait_attributes WHERE art_style = ? AND rating = ? "
                "AND race = ? AND gender = ?", v).fetchall()),
        ]
        print("four-trait candidate lookup (all matching rows returned):")
        fuzzy_counts = []
        for name, query in fuzzy:
            fuzzy_counts.append(measure(conn, name, fuzzy_cases, query))
        assert fuzzy_counts[0] == fuzzy_counts[1] == fuzzy_counts[2]
        for case in fuzzy_cases[:3]:
            expected = {row[0] for row in fuzzy[0][1](conn, case)}
            assert all({row[0] for row in query(conn, case)} == expected for _, query in fuzzy)
        conn.close()


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 100_000)
