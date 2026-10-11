# Concurrency check: many simultaneous lookups and stores on one database.
#
#   crystal run --release bench/concurrency.cr -- [options]
#
#   --assets N    pictures to seed (default 5000)
#   --fibers F    concurrent clients per process (default 100)
#   --seconds S   how long to run (default 10)
#   --procs P     processes sharing the database (default 1)
#   --think MS    average pause between a client's requests (default 5); with 0,
#                 clients still yield between requests, as a request handler
#                 does on its socket
#   --dir PATH    where to put the database (default: a temporary directory)
#
# Seeds a database with a pooled "picture" type (with set traits) and a
# single-best "voice" type, then runs F clients per process for S seconds,
# each mixing lookups and stores in the proportions of WEIGHTS. Note that
# `get` touches usage, so it writes too. With --procs above 1, that many
# processes share the database, as several app servers or a separate worker
# would; that's where SQLite's single writer is actually contended. Reports
# latency per operation, throughput, errors (such as "database is locked"),
# and whether the store is still consistent afterwards.
require "../src/data_dungeon"
require "option_parser"
require "json"
require "file_utils"

STYLES  = %w[golden silver noir]
RATINGS = %w[g pg r]
STATES  = %w[troll-dead trapdoor-open window-ajar lit]
ITEMS   = %w[lantern sword rope leaflet garlic bottle]

WEIGHTS = {
  "find_pool"        => 30, # exact pool, by traits
  "find_group"       => 15, # leading traits, by key prefix
  "find_pool_custom" => 10, # pool with the items free
  "find_by_tags"     => 10, # tag filter not led by the key
  "get_voice"        => 15, # single-best lookup; touches usage (a write)
  "store_picture"    => 12, # a new pool member (row + object)
  "store_voice"      => 8,  # replace a single-best asset
}

# Deterministic per index, so every process draws from the same catalogue.
def picture_traits(i : Int32) : Hash(String, String)
  rng = Random.new(i)
  {
    "portrait"  => (i % 200).to_s,
    "art_style" => STYLES[rng.rand(STYLES.size)],
    "rating"    => RATINGS[rng.rand(RATINGS.size)],
    "room"      => (rng.rand(60) + 1).to_s,
    "state"     => STATES.sample(rng.rand(3), rng).join(","),
    "items"     => ITEMS.sample(rng.rand(3), rng).join(","),
  }
end

def voice_traits(i : Int32) : Hash(String, String)
  {"bit" => "b#{i % 2000}", "beat" => (i % 7).to_s, "voice" => "fable"}
end

def open_db(dir : String) : DataDungeon::DB
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("picture", pool_traits: %w[portrait art_style rating room state items],
    group_traits: %w[portrait art_style rating], labels: {"portrait" => "portrait", "room" => "room"},
    sets: %w[state items])
  db.register_type("voice", pool_traits: %w[bit beat voice])
  db
end

def bytes(rng : Random) : Bytes
  Bytes.new(2048) { rng.rand(256).to_u8 }
end

class Results
  include JSON::Serializable

  property latencies = {} of String => Array(Float64)
  property errors = {} of String => Int32
  property stored_pictures = 0

  def initialize
  end

  def merge(other : Results) : Nil
    other.latencies.each { |op, samples| (latencies[op] ||= [] of Float64).concat(samples) }
    other.errors.each { |message, count| errors[message] = errors.fetch(message, 0) + count }
    @stored_pictures += other.stored_pictures
  end
end

def run_clients(dir : String, assets : Int32, fibers : Int32, seconds : Float64, think_ms : Float64, seed : Int32) : Results
  db = open_db(dir)
  results = Results.new
  ops = WEIGHTS.flat_map { |op, weight| Array.new(weight, op) }
  deadline = Time.instant + seconds.seconds
  done = Channel(Nil).new

  fibers.times do |f|
    spawn do
      rng = Random.new(seed * 10_000 + f)
      while Time.instant < deadline
        op = ops.sample(rng)
        i = rng.rand(assets)
        start = Time.instant
        begin
          case op
          when "find_pool"        then db.find_pool("picture", picture_traits(i))
          when "find_group"       then db.find_group("picture", picture_traits(i))
          when "find_pool_custom" then db.find_pool("picture", picture_traits(i), custom: %w[items])
          when "find_by_tags"
            traits = picture_traits(i)
            db.find_assets_by_tags("picture", {"room" => traits["room"], "rating" => traits["rating"]})
          when "get_voice" then db.get("voice", voice_traits(i))
          when "store_picture"
            db.store("picture", picture_traits(i), bytes: bytes(rng), content_type: "image/webp")
            results.stored_pictures += 1
          when "store_voice"
            db.store("voice", voice_traits(i), bytes: bytes(rng), content_type: "audio/mpeg", media: "audio")
          end
          (results.latencies[op] ||= [] of Float64) << (Time.instant - start).total_milliseconds
        rescue ex
          message = (ex.message || ex.class.name)[0, 80]
          results.errors[message] = results.errors.fetch(message, 0) + 1
        end
        if think_ms > 0
          sleep (rng.rand * 2 * think_ms).milliseconds
        else
          Fiber.yield # a real request handler yields at least on its socket
        end
      end
      done.send(nil)
    end
  end
  fibers.times { done.receive }
  begin
    db.close
  rescue ex
    message = "close: #{ex.message}"[0, 80]
    results.errors[message] = results.errors.fetch(message, 0) + 1
  end
  results
end

def percentile(sorted : Array(Float64), fraction : Float64) : Float64
  sorted[((sorted.size - 1) * fraction).round.to_i]
end

assets = 5000
fibers = 100
seconds = 10.0
procs = 1
think_ms = 5.0
dir_option : String? = nil
child_seed : Int32? = nil

OptionParser.parse do |parser|
  parser.on("--assets N", "pictures to seed") { |v| assets = v.to_i }
  parser.on("--fibers F", "clients per process") { |v| fibers = v.to_i }
  parser.on("--seconds S", "run time") { |v| seconds = v.to_f }
  parser.on("--procs P", "processes") { |v| procs = v.to_i }
  parser.on("--think MS", "average pause between requests") { |v| think_ms = v.to_f }
  parser.on("--dir PATH", "database directory") { |v| dir_option = v }
  parser.on("--child SEED", "internal: run as one of several processes") { |v| child_seed = v.to_i }
end

if seed = child_seed
  puts run_clients(dir_option.not_nil!, assets, fibers, seconds, think_ms, seed).to_json
  exit
end

given_dir = dir_option # a local, so its type narrows (the option block captures dir_option)
dir = given_dir || File.tempname("dd-concurrency")
Dir.mkdir_p(dir)
begin
  db = open_db(dir)
  seeding = Time.instant
  rng = Random.new(1)
  assets.times { |i| db.store("picture", picture_traits(i), bytes: bytes(rng), content_type: "image/webp") }
  2000.times { |i| db.store("voice", voice_traits(i), bytes: bytes(rng), content_type: "audio/mpeg", media: "audio") }
  db.close
  puts "seeded #{assets} pictures and 2000 voices in #{(Time.instant - seeding).total_seconds.round(1)} s"
  puts "running #{procs} process(es) x #{fibers} clients for #{seconds} s, think #{think_ms} ms"

  results = Results.new
  if procs == 1
    results = run_clients(dir, assets, fibers, seconds, think_ms, 1)
  else
    exe = Process.executable_path.not_nil!
    children = (1..procs).map do |seed|
      Process.new(exe, ["--child", seed.to_s, "--dir", dir, "--assets", assets.to_s, "--fibers", fibers.to_s,
                        "--seconds", seconds.to_s, "--think", think_ms.to_s],
        output: Process::Redirect::Pipe, error: Process::Redirect::Inherit)
    end
    children.each do |child|
      results.merge(Results.from_json(child.output.gets_to_end))
      child.wait
    end
  end

  total = results.latencies.sum { |_, samples| samples.size }
  puts
  printf("%-17s %8s %9s %9s %9s %9s\n", "operation", "count", "p50 ms", "p95 ms", "p99 ms", "max ms")
  WEIGHTS.each_key do |op|
    samples = (results.latencies[op]? || [] of Float64).sort
    next if samples.empty?
    printf("%-17s %8d %9.3f %9.3f %9.3f %9.3f\n", op, samples.size,
      percentile(samples, 0.5), percentile(samples, 0.95), percentile(samples, 0.99), samples.last)
  end
  puts
  puts "throughput: #{(total / seconds).round} operations/s"
  if results.errors.empty?
    puts "errors: none"
  else
    puts "errors:"
    results.errors.each { |message, count| puts "  #{count} x #{message}" }
  end

  db = open_db(dir)
  pictures = db.connection.scalar("SELECT COUNT(*) FROM assets WHERE asset_type = 'picture'").as(Int64)
  expected = assets + results.stored_pictures
  report = db.check_consistency
  puts "pictures: #{pictures} (expected #{expected})#{pictures == expected ? "" : "  MISMATCH"}"
  puts "consistency: #{report.clean? ? "clean" : "#{report.missing_objects.size} missing objects, #{report.orphan_objects.size} orphan objects"}"
  db.close
ensure
  FileUtils.rm_rf(dir) unless given_dir
end
