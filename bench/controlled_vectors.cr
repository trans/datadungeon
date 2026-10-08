# Best match with controlled vectors in USearch: each trait a block of
# dimensions, one per value, scaled by the square root of its weight, so an
# inner product is the weighted count of matching traits.
#
#   crystal run --release bench/controlled_vectors.cr -- 200000
#
# Measured 2026-10-08, single-threaded, 102 dims, f32: 200k assets built in
# 32 s (186 MB), nearest 10 in 0.16 ms (recall 99.7%), with style and rating
# required 0.32 ms (99.2%); 1M assets built in 213 s (797 MB), nearest 10 in
# 0.22 ms (100%), filtered 0.38 ms (p95 0.70, 99.9%).
require "usearch"

n = (ARGV[0]? || "200000").to_i
cards = [6, 3, 12, 5, 50, 12, 4, 10] # values per trait, most important first
weights = [8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0]
offsets = cards.each_with_index.map { |_, i| cards[0, i].sum }.to_a
dims = cards.sum
rng = Random.new(7)

def vector(values : Array(Int32), offsets, weights, dims) : Array(Float32)
  v = Array(Float32).new(dims, 0_f32)
  values.each_with_index { |value, i| v[offsets[i] + value] = Math.sqrt(weights[i]).to_f32 }
  v
end

def score(a : Array(Int32), b : Array(Int32), weights) : Float64
  s = 0.0
  a.each_with_index { |value, i| s += weights[i] if value == b[i] }
  s
end

assets = Array.new(n) { cards.map { |c| rng.rand(c) } }
index = USearch::Index.new(dimensions: dims, metric: :ip, quantization: :f32)
index.reserve(n)
t = Time.instant
assets.each_with_index { |values, id| index.add(id.to_u64, vector(values, offsets, weights, dims)) }
build = Time.instant - t
puts "#{n} assets, #{dims} dims, built in #{build.total_seconds.round(1)} s, #{(index.memory_usage / 1e6).round} MB"

queries = Array.new(100) { cards.map { |c| rng.rand(c) } }

def pct(times : Array(Float64), p : Float64) : Float64
  times.sort[(times.size * p).to_i.clamp(0, times.size - 1)]
end

{"nearest 10" => false, "nearest 10, art style + rating must match" => true}.each do |label, filtered|
  times = [] of Float64
  recall_hits = 0
  queries.each do |q|
    qv = vector(q, offsets, weights, dims)
    t = Time.instant
    results = if filtered
                index.filtered_search(qv, 10) { |key| a = assets[key]; a[0] == q[0] && a[6] == q[6] }
              else
                index.search(qv, 10)
              end
    times << (Time.instant - t).total_milliseconds
    # exact top-10 by brute force, compared by score (ties make ids interchangeable)
    pool = filtered ? assets.select { |a| a[0] == q[0] && a[6] == q[6] } : assets
    best = pool.map { |a| score(a, q, weights) }.sort.reverse.first(10)
    got = results.map { |r| score(assets[r.key], q, weights) }.sort.reverse
    recall_hits += best.zip(got).count { |e, g| (e - g).abs < 1e-6 }
  end
  puts "#{label.ljust(44)} p50=#{pct(times, 0.5).round(3)} ms  p95=#{pct(times, 0.95).round(3)} ms  recall@10=#{(recall_hits / 10.0).round(1)}%"
end
