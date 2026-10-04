require "file_utils"
require "../src/data_dungeon/semantic"

# Synthetic filter-path benchmark. Mock embeddings remove network latency so
# the timings show SQLite filtering, USearch, and asset lookup costs.
count = (ARGV[0]? || "10000").to_i
samples = (ARGV[1]? || "30").to_i
dir = File.tempname("dd-semantic-bench")
Dir.mkdir_p(dir)
db = DataDungeon::DB.new(File.join(dir, "assets.db"))
index = DataDungeon::SemanticIndex.new(db, service: "mock", chunking_max_tokens: 50)
conn = db.connection

start = Time.instant
conn.transaction do
  count.times do |i|
    style = i % 10 == 0 ? "golden" : "silver"
    text = "Portrait #{i} of an adventurer with a lantern"
    conn.exec(
      "INSERT INTO assets (asset_type, media, content_type, file_path, created_at, description) VALUES (?, ?, ?, ?, ?, ?)",
      "portrait", "image", "image/webp", "portrait/#{i}.webp", "2026-01-01", text
    )
    id = conn.scalar("SELECT last_insert_rowid()").as(Int64)
    conn.exec("INSERT INTO asset_tags (asset_id, tag_key, tag_value) VALUES (?, ?, ?)", id, "art_style", style)

    source = Memo::SourceRegistry.resolve(conn, "asset", id)
    hash = Memo::Storage.compute_hash(text)
    vector, tokens = index.memo.provider.embed_text(text, "document")
    inserted, rowid = Memo::Storage.store_embedding(conn, hash, tokens, index.memo.service_id)
    Memo::USearchIndex.add(index.memo.usearch_index, rowid.to_u64, vector) if inserted
    Memo::Storage.create_chunk(conn, hash, "asset", source, 0, text.size)
  end
end
puts "fixture: #{count} assets in #{(Time.instant - start).total_seconds.round(1)}s"

def measure(label : String, samples : Int32, &block)
  times = [] of Float64
  block.call # warm the query embedding cache and SQLite page cache
  samples.times do
    start = Time.instant
    block.call
    times << (Time.instant - start).total_milliseconds
  end
  times.sort!
  puts "#{label}: median #{times[times.size // 2].round(2)}ms, p95 #{times[(times.size * 0.95).floor.to_i.clamp(0, times.size - 1)].round(2)}ms"
end

measure("no tag filter", samples) { index.search("adventurer lantern", asset_type: "portrait", min_score: 0.0) }
measure("hot style 90%", samples) { index.search("adventurer lantern", asset_type: "portrait", tags: {"art_style" => "silver"}, min_score: 0.0) }
measure("cool style 10%", samples) { index.search("adventurer lantern", asset_type: "portrait", tags: {"art_style" => "golden"}, min_score: 0.0) }

db.close
FileUtils.rm_rf(dir)
