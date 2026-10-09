require "usearch"
require "digest/sha256"
require "../data_dungeon"
require "./css_colors"

module DataDungeon
  # Best matches for registered types: the assets whose traits come closest
  # to what was asked, even when none matches every pick, ranked by
  #
  #     score = Σ weight × similarity, over the traits asked for
  #
  # where a word trait is alike only when equal, a scale's values are alike
  # by how near they sit on it, colors by how alike they look (CIE76 ΔE in
  # Lab), and sets by the members they share. See DESIGN-best-match.md.
  #
  # Each asset gets a controlled vector built from its tags (no model, no
  # API calls): one block per trait, so its inner product with a query's
  # vector approximates the score. USearch finds the nearest candidates in
  # one file per type, beside the database, and they are then scored
  # exactly from their traits. Weights travel with the query, so changing
  # them rebuilds nothing; changing a type's traits, scales or colors
  # rebuilds its file from the tags.
  #
  # One process owns a store's match files (a lock). Before each query it
  # catches up on every process's writes from the database's change log;
  # a checkpoint beside each file means a restart replays only what changed.
  class MatchIndex < Matcher
    WORD_DIMS     =   16 # a word or set trait's block
    FALLBACK_DIMS =    8 # added to a scale's or color's block, for values it doesn't know
    SHORTLIST     =  200 # candidates USearch finds before exact scoring
    ENCODING      =    2 # bump when vectors change meaning: rebuilds every file
    YIELD_EVERY   =  256 # a rebuild lets other fibers run this often
    COLOR_SIGMA   = 25.0
    ANCHOR_SIGMA  = 35.0

    # Colors that place the others by appearance: a color's block holds how
    # close it is to each.
    ANCHORS = [0x000000, 0xFFFFFF, 0x808080, 0xFF0000, 0xFFA500, 0xFFFF00,
               0x008000, 0x00FFFF, 0x0000FF, 0x800080, 0xFFC0CB, 0x8B4513]

    class InUse < Exception
    end

    enum Kind
      Word
      Set
      Scale
      Color
    end

    record Block, trait : String, kind : Kind, offset : Int32, dims : Int32

    getter dir : String
    @types = {} of String => TypeIndex
    @mutex = Mutex.new(:reentrant)
    @lock : File

    # Owns the match files in `dir` (by default beside the database).
    def initialize(@db : DB, dir : String? = nil)
      @dir = dir || "#{db.path}.matches"
      Dir.mkdir_p(@dir)
      @lock = File.open(File.join(@dir, "lock"), "a+")
      begin
        @lock.flock_exclusive(blocking: false)
      rescue IO::Error
        @lock.close
        raise InUse.new("#{@dir} is open in another process; one process owns a store's match index")
      end
    end

    # The assets of a registered type closest to `picks` (trait => value),
    # best first, with their scores. Traits in `require` must equal their
    # picks. `weights` give this query's emphasis; others come from the
    # registration, else 1.
    def best_matches(asset_type : String, picks : Hash(String, String), *,
                     require required_traits : Array(String) = [] of String,
                     weights : Hash(String, Float64) = {} of String => Float64,
                     limit : Int32 = 10) : Array(BestMatch)
      search(asset_type, picks, required_traits, weights, limit, nil)
    end

    # The assets closest to this one, by its own traits.
    def similar(id : Int64, *,
                require required_traits : Array(String) = [] of String,
                weights : Hash(String, Float64) = {} of String => Float64,
                limit : Int32 = 10) : Array(BestMatch)
      rec = @db.find_asset_by_id(id) || raise ArgumentError.new("No asset #{id}")
      search(rec.asset_type, @db.load_tags(id), required_traits, weights, limit, id)
    end

    # Saves every file and releases the lock.
    def close : Nil
      @mutex.synchronize do
        @types.each_value { |ti| save(ti) }
        @types.each_value(&.index.close)
        @types.clear
      end
      @lock.close unless @lock.closed?
    end

    private def search(asset_type, picks, required_traits, weights, limit, exclude) : Array(BestMatch)
      @mutex.synchronize do
        ti = current(asset_type)
        type = ti.type
        picks = @db.normalize_tags(asset_type, picks).select { |trait, _| type.trait?(trait) }
        raise ArgumentError.new("Pick at least one of #{asset_type}'s traits: #{type.pool_traits.join(", ")}") if picks.empty?
        unless (unknown = required_traits - type.pool_traits).empty?
          raise ArgumentError.new("#{unknown.join(", ")}: not traits of #{asset_type}")
        end
        unless (unpicked = required_traits - picks.keys).empty?
          raise ArgumentError.new("Required but not picked: #{unpicked.join(", ")}")
        end
        weights.each do |trait, weight|
          raise ArgumentError.new("Weight #{trait} must be positive") unless weight > 0 && weight.finite?
        end
        weights = picks.keys.to_h { |trait| {trait, weights[trait]? || type.weights[trait]? || 1.0} }

        required = required_traits.map { |trait| {ti.position(trait), ti.code_of(ti.position(trait), picks[trait])} }
        return [] of BestMatch if required.any? { |(_, code)| code.nil? } # no asset has that value

        query = vector(ti, picks, weights)
        k = Math.max(SHORTLIST, limit * 4)
        hits = if required.empty?
                 ti.index.search(query, k)
               else
                 ti.index.filtered_search(query, k) { |key| ti.matches?(key.to_i64, required) }
               end
        ids = hits.map(&.key.to_i64)
        # Too few found through the filter: the required group is small, so
        # score all of it (DD's tag filter finds it from its rarest value).
        if !required.empty? && ids.size < limit + 1
          ids = @db.find_assets_by_tags(asset_type, required_traits.to_h { |trait| {trait, picks[trait]} }).map(&.id)
        end
        ids.reject! { |id| id == exclude }

        best = ids.map { |id| {id, score(ti, picks, weights, id)} }.sort_by! { |(id, s)| {-s, -id} }.first(limit)
        best.compact_map { |(id, s)| @db.find_asset_by_id(id).try { |rec| BestMatch.new(rec, s) } }
      end
    end

    # The type's index, loaded or built, and caught up on changes.
    private def current(asset_type : String) : TypeIndex
      type = @db.registration(asset_type) || raise ArgumentError.new("#{asset_type} is not a registered asset type")
      sig = signature(type)
      ti = @types[asset_type]?
      if ti.nil? || ti.signature != sig
        ti.try(&.index.close)
        ti = @types[asset_type] = open_type(type, sig)
      end
      ti.type = type # weights may have changed; they need nothing rebuilt
      ti = @types[asset_type] = rebuild(type, sig) unless catch_up(ti)
      ti
    end

    private def open_type(type : AssetType, sig : String) : TypeIndex
      path, checkpoint = files(type.name)
      if File.exists?(path) && File.exists?(checkpoint)
        saved = Hash(String, JSON::Any).from_json(File.read(checkpoint)) rescue nil
        if saved && saved["signature"]?.try(&.as_s?) == sig && saved["slots"]?
          blocks = layout(type)
          begin
            index = USearch::Index.load(path, dimensions: blocks.sum(&.dims), metric: :ip, quantization: :f16)
            ti = TypeIndex.new(type, blocks, sig, index, saved["seq"].as_i64)
            ti.slot_lists = saved["slots"].as_a.map(&.as_a.map(&.as_s))
            each_asset(type.name) { |id, tags| ti.put_values(id, tags) }
            return ti
          rescue
            # Fall through: rebuilt from the tags
          end
        end
      end
      rebuild(type, sig)
    end

    # Every vector again from the tags, then saved.
    private def rebuild(type : AssetType, sig : String) : TypeIndex
      blocks = layout(type)
      index = USearch::Index.new(dimensions: blocks.sum(&.dims), metric: :ip, quantization: :f16)
      count = @db.connection.scalar("SELECT COUNT(*) FROM assets WHERE asset_type = ?", type.name).as(Int64)
      index.reserve(Math.max(count + 1024, 1024))
      ti = TypeIndex.new(type, blocks, sig, index, latest_change) # read first: later writes replay
      added = 0
      each_asset(type.name) do |id, tags|
        ti.put_values(id, tags)
        add(ti, id, vector(ti, tags))
        Fiber.yield if (added += 1) % YIELD_EVERY == 0
      end
      save(ti)
      ti
    end

    # Apply the changes logged since the index's checkpoint; false when the
    # log no longer reaches back that far (pruned), so it must be rebuilt.
    private def catch_up(ti : TypeIndex) : Bool
      latest = latest_change
      return true if latest <= ti.seq
      oldest = @db.connection.query_one("SELECT min(seq) FROM asset_changes", as: Int64?)
      return false if oldest.nil? || oldest > ti.seq + 1
      changed = @db.connection.query_all("SELECT DISTINCT asset_id FROM asset_changes WHERE seq > ? AND seq <= ?",
        ti.seq, latest, as: Int64)
      changed.each_slice(500) do |batch|
        types = {} of Int64 => String
        @db.connection.query("SELECT id, asset_type FROM assets WHERE id IN (#{batch.join(", ")})") do |rs|
          rs.each { types[rs.read(Int64)] = rs.read(String) }
        end
        tags = @db.load_tags_batch(batch.select { |id| types[id]? == ti.type.name })
        batch.each do |id|
          ti.index.remove(id.to_u64) if ti.index.contains?(id.to_u64)
          ti.drop_values(id)
          next unless types[id]? == ti.type.name
          values = tags[id]? || {} of String => String
          ti.put_values(id, values)
          add(ti, id, vector(ti, values))
        end
      end
      ti.seq = latest
      true
    end

    # USearch needs room reserved before adding; the Crystal wrapper reserves
    # 1,024 once, so grow it by doubling, as Memo does.
    private def add(ti : TypeIndex, id : Int64, vector : Array(Float32)) : Nil
      capacity = ti.index.capacity
      ti.index.reserve(Math.max(capacity.to_i * 2, 1024)) if ti.index.size >= capacity
      ti.index.add(id.to_u64, vector)
    end

    private def latest_change : Int64
      @db.connection.query_one?("SELECT seq FROM sqlite_sequence WHERE name = 'asset_changes'", as: Int64) || 0_i64
    end

    private def each_asset(asset_type : String, &) : Nil
      last = 0_i64
      loop do
        ids = @db.connection.query_all("SELECT id FROM assets WHERE asset_type = ? AND id > ? ORDER BY id LIMIT 1000",
          asset_type, last, as: Int64)
        break if ids.empty?
        tags = @db.load_tags_batch(ids)
        ids.each { |id| yield id, tags[id]? || {} of String => String }
        last = ids.last
      end
    end

    private def save(ti : TypeIndex) : Nil
      path, checkpoint = files(ti.type.name)
      ti.index.save(path)
      tmp = "#{checkpoint}.tmp"
      File.write(tmp, {signature: ti.signature, seq: ti.seq, slots: ti.slot_lists}.to_json)
      File.rename(tmp, checkpoint)
    end

    private def files(asset_type : String) : {String, String}
      path = File.join(@dir, "#{asset_type}.usearch")
      {path, "#{path}.checkpoint"}
    end

    # ── Vectors ──

    private def layout(type : AssetType) : Array(Block)
      offset = 0
      type.pool_traits.map do |trait|
        kind = if type.set?(trait)
                 Kind::Set
               elsif type.scales.has_key?(trait)
                 Kind::Scale
               elsif type.colors.includes?(trait)
                 Kind::Color
               else
                 Kind::Word
               end
        dims = case kind
               in .scale?       then 2 + FALLBACK_DIMS
               in .color?       then ANCHORS.size + FALLBACK_DIMS
               in .word?, .set? then WORD_DIMS
               end
        block = Block.new(trait, kind, offset, dims)
        offset += dims
        block
      end
    end

    # What the vectors mean; a file built under another signature is rebuilt.
    private def signature(type : AssetType) : String
      Digest::SHA256.hexdigest({ENCODING, WORD_DIMS, FALLBACK_DIMS, type.pool_traits, type.sets, type.scales,
                                type.colors}.to_json)
    end

    # Each trait's block for these values, times its weight. A stored
    # vector (no weights) gives new words slots; a query only uses them.
    private def vector(ti : TypeIndex, values : Hash(String, String),
                       weights : Hash(String, Float64)? = nil) : Array(Float32)
      vector = Array(Float32).new(ti.dims, 0_f32)
      ti.blocks.each_with_index do |block, position|
        value = values[block.trait]? || next
        weight = weights ? (weights[block.trait]? || next) : 1.0
        encode(ti, position, value, assign: weights.nil?).each_with_index do |x, i|
          vector[block.offset + i] = (x * weight).to_f32
        end
      end
      vector
    end

    private def encode(ti : TypeIndex, position : Int32, value : String, assign : Bool) : Array(Float64)
      type, block = ti.type, ti.blocks[position]
      case block.kind
      in .word?
        word_or_slot(ti, position, value, assign)
      in .set?
        sum = Array(Float64).new(WORD_DIMS, 0.0)
        value.split(TraitKey::MEMBER).each do |member|
          word_or_slot(ti, position, member, assign).each_with_index { |x, i| sum[i] += x }
        end
        unit(sum)
      in .scale?
        scale = type.scales[block.trait]
        if position = scale.index(value)
          angle = Math::PI / 2 * position / (scale.size - 1)
          [Math.cos(angle), Math.sin(angle)] + Array(Float64).new(FALLBACK_DIMS, 0.0)
        else
          [0.0, 0.0] + word(value, FALLBACK_DIMS)
        end
      in .color?
        if rgb = MatchIndex.color(value)
          lab = MatchIndex.lab(rgb)
          unit(ANCHOR_LABS.map { |anchor| MatchIndex.closeness(MatchIndex.delta_e(lab, anchor), ANCHOR_SIGMA) }) +
            Array(Float64).new(FALLBACK_DIMS, 0.0)
        else
          Array(Float64).new(ANCHORS.size, 0.0) + word(value, FALLBACK_DIMS)
        end
      end
    end

    # A word's direction in its trait's block: one of the block's own
    # dimensions (exact: perpendicular to every other) for the trait's first
    # WORD_DIMS values, else pseudo-random from its name, nearly
    # perpendicular to the rest. Slots are kept with the file.
    private def word_or_slot(ti : TypeIndex, position : Int32, value : String, assign : Bool) : Array(Float64)
      slot = ti.slot(position, value) || (assign ? ti.assign_slot(position, value, WORD_DIMS) : nil)
      return word(value, WORD_DIMS) unless slot
      Array(Float64).new(WORD_DIMS) { |i| i == slot ? 1.0 : 0.0 }
    end

    # A value's own direction: pseudo-random from its name, so different
    # values are nearly perpendicular and equal ones line up.
    private def word(value : String, dims : Int32) : Array(Float64)
      seed = IO::ByteFormat::LittleEndian.decode(UInt64, Digest::SHA256.digest(value)[0, 8])
      random = Random::PCG32.new(seed)
      unit(Array(Float64).new(dims) { random.rand * 2 - 1 })
    end

    private def unit(vector : Array(Float64)) : Array(Float64)
      norm = Math.sqrt(vector.sum { |x| x * x })
      norm == 0 ? vector : vector.map { |x| x / norm }
    end

    # ── Exact scores ──

    private def score(ti : TypeIndex, picks : Hash(String, String), weights : Hash(String, Float64), id : Int64) : Float64
      codes = ti.values?(id) || return 0.0
      picks.sum do |trait, pick|
        position = ti.position(trait)
        value = ti.value(position, codes[position]) || next 0.0
        weights[trait] * similarity(ti.type, ti.blocks[position], pick, value)
      end
    end

    private def similarity(type : AssetType, block : Block, a : String, b : String) : Float64
      case block.kind
      in .word?
        a == b ? 1.0 : 0.0
      in .set?
        members_a, members_b = a.split(TraitKey::MEMBER), b.split(TraitKey::MEMBER)
        (members_a & members_b).size / Math.sqrt(members_a.size * members_b.size)
      in .scale?
        scale = type.scales[block.trait]
        i, j = scale.index(a), scale.index(b)
        i && j ? 1.0 - (i - j).abs / (scale.size - 1) : (a == b ? 1.0 : 0.0)
      in .color?
        rgb_a, rgb_b = MatchIndex.color(a), MatchIndex.color(b)
        if rgb_a && rgb_b
          MatchIndex.closeness(MatchIndex.delta_e(MatchIndex.lab(rgb_a), MatchIndex.lab(rgb_b)), COLOR_SIGMA)
        else
          a == b ? 1.0 : 0.0
        end
      end
    end

    # ── Colors ──

    # A color value's RGB: a CSS name (with or without dashes) or a hex code
    # (stored values lose the `#`).
    def self.color(value : String) : Int32?
      CSS_COLORS[value.delete('-')]? || (value.matches?(/\A[0-9a-f]{6}\z/) ? value.to_i(16) : nil)
    end

    # CIE L*a*b* (D65) of an sRGB color.
    def self.lab(rgb : Int32) : {Float64, Float64, Float64}
      r, g, b = {(rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF}.map do |channel|
        c = channel / 255.0
        c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
      end
      x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
      y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
      z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
      fx, fy, fz = {x, y, z}.map { |t| t > (6 / 29.0) ** 3 ? Math.cbrt(t) : t / (3 * (6 / 29.0) ** 2) + 4 / 29.0 }
      {116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)}
    end

    # 1 for the same color, falling off with distance: about 0.6 at `sigma`.
    def self.closeness(delta_e : Float64, sigma : Float64) : Float64
      Math.exp(-(delta_e * delta_e) / (2 * sigma * sigma))
    end

    def self.delta_e(a : {Float64, Float64, Float64}, b : {Float64, Float64, Float64}) : Float64
      Math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)
    end

    ANCHOR_LABS = ANCHORS.map { |rgb| MatchIndex.lab(rgb) }

    # One type's vectors, and each asset's trait values (interned as codes,
    # for exact scoring and filtering without reading the database).
    private class TypeIndex
      property type : AssetType
      getter blocks : Array(Block)
      getter dims : Int32
      getter signature : String
      getter index : USearch::Index
      property seq : Int64
      @positions : Hash(String, Int32)
      @codes = {} of Int64 => Slice(Int32)
      @value_codes : Array(Hash(String, Int32))
      @code_values : Array(Array(String))
      @slots : Array(Hash(String, Int32))

      def initialize(@type : AssetType, @blocks : Array(Block), @signature : String, @index : USearch::Index, @seq : Int64)
        @dims = @blocks.sum(&.dims)
        @positions = @blocks.each_with_index.to_h { |block, i| {block.trait, i} }
        @value_codes = Array.new(@blocks.size) { {} of String => Int32 }
        @code_values = Array.new(@blocks.size) { [] of String }
        @slots = Array.new(@blocks.size) { {} of String => Int32 }
      end

      def slot(position : Int32, value : String) : Int32?
        @slots[position][value]?
      end

      # The next free slot for a new word, if any are left.
      def assign_slot(position : Int32, value : String, dims : Int32) : Int32?
        slots = @slots[position]
        slots[value] = slots.size if slots.size < dims
      end

      # Each trait's slotted words, in slot order (saved with the file).
      def slot_lists : Array(Array(String))
        @slots.map { |slots| slots.keys }
      end

      def slot_lists=(lists : Array(Array(String)))
        @slots = lists.map { |values| values.each_with_index.to_h { |value, i| {value, i} } }
      end

      def position(trait : String) : Int32
        @positions[trait]
      end

      def put_values(id : Int64, tags : Hash(String, String)) : Nil
        @codes[id] = Slice(Int32).new(@blocks.size) { |i| intern(i, tags[@blocks[i].trait]?) }
      end

      def drop_values(id : Int64) : Nil
        @codes.delete(id)
      end

      def values?(id : Int64) : Slice(Int32)?
        @codes[id]?
      end

      def value(position : Int32, code : Int32) : String?
        code < 0 ? nil : @code_values[position][code]
      end

      def code_of(position : Int32, value : String) : Int32?
        @value_codes[position][value]?
      end

      def matches?(id : Int64, required : Array({Int32, Int32?})) : Bool
        codes = @codes[id]? || return false
        required.all? { |(position, code)| codes[position] == code }
      end

      private def intern(position : Int32, value : String?) : Int32
        return -1 unless value
        @value_codes[position][value] ||= begin
          @code_values[position] << value
          @code_values[position].size - 1
        end
      end
    end
  end
end
