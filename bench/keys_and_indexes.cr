# Keys as an index (0.11, 0.12): lookups by traits through the planner, which
# starts from the narrowest of the type's own index, a consumer's index and
# each tag; listings and counts that leave retired assets out; and what a
# consumer's index costs to build and keep.
#
#   crystal run --release bench/keys_and_indexes.cr -- 1000000 /tmp/keys_and_indexes.db
#
# Cattacula-like voice lines: 50,000 bits, 5 beats, 20 voices, 1% wav, a
# tenth retired; the type keyed voice bit beat fmt, a consumer's index
# bit beat voice fmt.
#
# Measured 2026-10-09 at 1M (a page is 50, p50): by the consumer's index or
# the type's key 0.04-0.06 ms; one common trait (5%) 0.5 ms and two common
# together 0.2-2.6 ms, walking the newest; a rare tag (1%) 3.8 ms; a rare
# tag with others 19-21 ms (about 10,000 rows checked whichever way: an
# index on those traits is the fix). Counting is linear: 16-52 ms for
# 9,000-45,000 matches, 174 ms for 179,000. `get` 0.003 ms; asset_types
# 0.9 ms, tag_keys 2.5 ms, tag_values 0.01 ms, from the kept counts;
# registering an index over 1M assets 4.7 s; retiring 0.05 ms. A store
# costs about 23 us more for the kept counts (102 to 125 us at 200k).
#
# Again 2026-10-11 with 0.12, the type's own key in asset_keys like any
# index: pages, counts and the rest the same within noise; `get` 0.016 ms
# (a missing key; about 8 us for a hit, read whole, on a real store),
# find_pool and find_group 0.004 ms; registering an index 6.2 s; a store
# 0.126 ms with the index; 1M stored in 143 s.
require "../src/data_dungeon"

n = (ARGV[0]? || "200000").to_i
path = ARGV[1]? || "/tmp/keys_and_indexes.db"
File.delete(path) if File.exists?(path)
db = DataDungeon::DB.new(path, consumer: "bench")
db.register_type("speech", pool_traits: %w[voice bit beat fmt])
rng = Random.new(11)

def tags(rng : Random) : Hash(String, String)
  {"voice" => "voice#{rng.rand(20)}", "bit" => "b#{rng.rand(50_000)}", "beat" => rng.rand(5).to_s,
   "fmt" => rng.rand < 0.01 ? "wav" : "mp3"}
end

t = Time.instant
n.times { |i| db.store_asset("speech", "audio", "audio/mpeg", "/voices/#{i}.mp3", tags(rng)) }
puts "#{n} assets stored in #{(Time.instant - t).total_seconds.round(1)} s"
db.connection.exec("UPDATE assets SET retired_at = created_at WHERE id % 10 = 0")

t = Time.instant
db.register_index("speech", "lines", traits: %w[bit beat voice fmt])
puts "index registered (#{n} keys) in #{(Time.instant - t).total_seconds.round(1)} s"

t = Time.instant
1000.times { db.store_asset("speech", "audio", "audio/mpeg", "/voices/more.mp3", tags(rng)) }
puts "stores with the index: #{((Time.instant - t).total_milliseconds / 1000).round(3)} ms each"

def p50(&) : Float64
  times = (1..20).map do
    t = Time.instant
    yield
    (Time.instant - t).total_milliseconds
  end
  times.sort[times.size // 2]
end

{
  "bit beat (the index)"        => {"bit" => "b123", "beat" => "2"},
  "bit (the index, prefix)"     => {"bit" => "b123"},
  "voice bit (the type's key)"  => {"voice" => "voice3", "bit" => "b123"},
  "voice (key prefix, 5%)"      => {"voice" => "voice3"},
  "fmt wav (rare tag, 1%)"      => {"fmt" => "wav"},
  "voice fmt=wav"               => {"voice" => "voice3", "fmt" => "wav"},
  "beat fmt=mp3 (common, none)" => {"beat" => "2", "fmt" => "mp3"},
  "voice beat (1% together)"    => {"voice" => "voice3", "beat" => "2"},
  "beat voice fmt=wav (rare)"   => {"beat" => "2", "voice" => "voice3", "fmt" => "wav"},
  "beat fmt=wav"                => {"beat" => "2", "fmt" => "wav"},
}.each do |name, filter|
  page = p50 { db.list_assets("speech", filter, limit: 50) }
  count = p50 { db.count_assets("speech", filter) }
  puts "#{name.ljust(28)} page p50=#{page.round(3)} ms  count p50=#{count.round(3)} ms  " \
       "(#{db.count_assets("speech", filter)} current)"
end

puts "get by key            p50=#{p50 { db.get("speech", {"voice" => "voice3", "bit" => "b123", "beat" => "2", "fmt" => "mp3"}, touch: false) }.round(3)} ms"
puts "find_pool by traits   p50=#{p50 { db.find_pool("speech", {"voice" => "voice3", "bit" => "b123", "beat" => "2", "fmt" => "mp3"}) }.round(3)} ms"
puts "find_group by prefix  p50=#{p50 { db.find_group("speech.voice3.b123.") }.round(3)} ms"
puts "asset_types           p50=#{p50 { db.asset_types }.round(3)} ms"
puts "asset_types retired   p50=#{p50 { db.asset_types(retired: true) }.round(3)} ms"
puts "tag_keys              p50=#{p50 { db.tag_keys("speech") }.round(3)} ms"
puts "tag_values voice      p50=#{p50 { db.tag_values("speech", "voice") }.round(3)} ms"
puts "list retired page     p50=#{p50 { db.list_assets("speech", retired: true, limit: 50) }.round(3)} ms"
ids = db.list_assets("speech", limit: 1000).map(&.id)
t = Time.instant
ids.each { |id| db.retire(id) }
puts "retire                #{((Time.instant - t).total_milliseconds / ids.size).round(3)} ms each"
puts "memory                #{(File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i // 1024)} MB resident"
db.close
File.delete(path)
