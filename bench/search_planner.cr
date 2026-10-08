# DataDungeon's search end to end: list_assets(q:) choosing between walking
# the newest assets and reading the full-text index, by word counts.
#
#   crystal run --release bench/search_planner.cr -- 200000 /tmp/search_planner.db
#
# Measured 2026-10-08 at 1M assets (stored through DD in 78 s), a page of
# 50: a word in half the store 0.10 ms, in a quarter 0.16 ms (the index
# alone: 11 and 5 ms); a rare word 0.08 ms; a rare word with a common one
# 0.18 ms; a prefix covering many words 0.13 ms (index alone: 46 ms); two
# moderately common words together 4.8-6.3 ms, the slowest case, which
# grows about as the store's size to the power 2/3.
require "../src/data_dungeon"

n = (ARGV[0]? || "200000").to_i
path = ARGV[1]? || "/tmp/search_planner.db"
File.delete(path) if File.exists?(path)
db = DataDungeon::DB.new(path)
rng = Random.new(11)
venues = %w[boardwalk pirate-ship cattacula midway big-top] + (0...45).map { |i| "venue#{i}" }
t = Time.instant
n.times do |i|
  db.store_asset("prop", "image", "image/webp", "/assets/#{i}.webp", {
    "venue" => venues.sample(rng), "look" => %w[night day dusk fog].sample(rng),
    "thing" => "thing#{rng.rand(2000)}", "style" => rng.rand < 0.5 ? "real" : "toon",
  })
end
puts "#{n} assets stored in #{(Time.instant - t).total_seconds.round(1)} s"

def p50(times : Array(Float64)) : Float64
  times.sort[times.size // 2]
end

["real", "night", "night boardwalk", "catt* night", "thing1*", "thing1234", "venue7 fog", "night thing1234", "nothing"].each do |q|
  times = (1..20).map do
    t = Time.instant
    rows = db.list_assets(q: q, limit: 50)
    (Time.instant - t).total_milliseconds
  end
  rows = db.list_assets(q: q, limit: 50).size
  puts "#{q.ljust(18)} p50=#{p50(times).round(3)} ms  rows=#{rows}"
end
db.close
File.delete(path)
