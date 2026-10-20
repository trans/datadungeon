# Best matches end to end through DataDungeon's MatchIndex.
#
#   crystal run --release bench/best_match.cr -- 200000 /tmp/best_match.db
#
# Measured 2026-10-08 at 200k portraits (8 traits: words, a scale, two
# colors, a set; 16-dim word blocks with exact slots): index built in 130 s
# (single-threaded); best 10 in 1.36 ms, with two traits required 3.4 ms,
# similar 1.27 ms; recall@10 against exhaustive scoring 100%; catching up
# 0.9 ms a write; saved in 0.04 s; reopened in 0.67 s. With hashed words
# only (no slots) recall was 81.5%: their noise outweighed small score gaps.
require "../src/data_dungeon/matches"

n = (ARGV[0]? || "200000").to_i
path = ARGV[1]? || "/tmp/best_match.db"
[path, "#{path}-wal", "#{path}-shm"].each { |file| File.delete(file) if File.exists?(file) }
Dir.glob("#{path}.matches/*").each { |file| File.delete(file) }
db = DataDungeon::DB.new(path)
db.register_type("plug", pool_traits: %w[art-style rating gender race skin hair outfit items],
  scales: {"rating" => %w[g pg r x]}, colors: %w[skin hair], sets: %w[items])
rng = Random.new(5)
styles = %w[golden silver realism 3d anime fantasy]
races = %w[human elf orc dwarf gnome halfling tiefling dragonborn goblin troll ogre fae]
skins = %w[tan peachpuff saddlebrown sienna wheat burlywood darkolivegreen lightgray]
hairs = %w[red black brown gold silver white blue green purple crimson orange pink]
items = %w[lantern sword rope shield bow staff map key]
pick = ->(traits : Hash(String, String)) { traits }
make = -> do
  {"art-style" => styles.sample(rng), "rating" => %w[g pg r x].sample(rng), "gender" => %w[f m x].sample(rng),
   "race" => races.sample(rng), "skin" => skins.sample(rng), "hair" => hairs.sample(rng),
   "outfit" => "outfit#{rng.rand(50)}", "items" => items.sample(rng.rand(1..3), rng).join(",")}
end
t = Time.instant
n.times { |i| db.store_asset("plug", "image", "image/webp", "/p/#{i}.webp", make.call) }
puts "#{n} portraits stored in #{(Time.instant - t).total_seconds.round(1)} s"

index = DataDungeon::MatchIndex.new(db)
t = Time.instant
index.best_matches("plug", {"race" => "elf"}, limit: 1)
puts "index built in #{(Time.instant - t).total_seconds.round(1)} s"

def p50(label, &block : -> Nil)
  times = (1..50).map { t = Time.instant; block.call; (Time.instant - t).total_milliseconds }.sort
  puts "#{label.ljust(46)} p50=#{times[25].round(3)} ms  p95=#{times[47].round(3)} ms"
end

queries = Array.new(50) { make.call }
q = 0
p50("best 10 of all picks") { index.best_matches("plug", queries[(q += 1) % 50], limit: 10) }
p50("best 10, art style + rating required") do
  index.best_matches("plug", queries[(q += 1) % 50], require: %w[art-style rating], limit: 10)
end
p50("best 10, hair weighted 5") { index.best_matches("plug", queries[(q += 1) % 50], weights: {"hair" => 5.0}, limit: 10) }
p50("similar 10") { index.similar((q += 1).to_i64 * 3 + 1, limit: 10) }

# Recall: the top 10 against every asset scored exactly (a limit so large
# that USearch returns them all), compared by score since ties reorder.
hits = 0
queries.first(20).each do |query|
  found = index.best_matches("plug", query, limit: 10).map(&.score)
  exact = index.best_matches("plug", query, limit: n).first(10).map(&.score)
  hits += exact.zip(found).count { |e, f| (e - f).abs < 1e-9 }
end
puts "recall@10 against exhaustive scoring: #{(hits / 2.0).round(1)}%"

1000.times { |i| db.store_asset("plug", "image", "image/webp", "/p/new#{i}.webp", make.call) }
t = Time.instant
index.best_matches("plug", {"race" => "elf"}, limit: 1)
puts "caught up on 1000 writes in #{(Time.instant - t).total_milliseconds.round(1)} ms"
t = Time.instant
index.close
puts "saved in #{(Time.instant - t).total_seconds.round(2)} s"
t = Time.instant
reopened = DataDungeon::MatchIndex.new(db)
reopened.best_matches("plug", {"race" => "elf"}, limit: 1)
puts "reopened (file + values) in #{(Time.instant - t).total_seconds.round(2)} s"
reopened.close
db.close
