require "sqlite3"

module DataDungeon
  class DB
    TIME_FORMAT = "%F %T"

    @db : ::DB::Database
    getter storage : Storage?

    def initialize(path : String, storage : Storage? = nil, cache_root : String? = nil)
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      @db = ::DB.open("sqlite3://#{path}")
      @storage = storage || (cache_root ? LocalStorage.new(cache_root) : nil)
      setup_schema
    end

    def close : Nil
      @db.close
    end

    # ── Schema ──

    ASSETS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS assets (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_type    TEXT NOT NULL,
        media         TEXT NOT NULL,
        content_type  TEXT NOT NULL,
        file_path     TEXT NOT NULL UNIQUE,
        canonical_key TEXT NOT NULL,
        file_hash     TEXT,
        created_at    TEXT NOT NULL,
        last_used_at  TEXT,
        use_count     INTEGER DEFAULT 0,
        permanent     INTEGER DEFAULT 0,
        pool          INTEGER DEFAULT 0,
        generator     TEXT,
        generation    TEXT,
        rating        INTEGER,
        flagged       INTEGER DEFAULT 0
      )
    SQL

    ASSETS_INDEXES = <<-SQL
      CREATE INDEX IF NOT EXISTS idx_assets_lookup
        ON assets(asset_type, canonical_key);
      CREATE INDEX IF NOT EXISTS idx_assets_type
        ON assets(asset_type);
      CREATE INDEX IF NOT EXISTS idx_assets_generator
        ON assets(generator)
    SQL

    ASSET_TAGS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_tags (
        asset_id  INTEGER NOT NULL,
        tag_key   TEXT NOT NULL,
        tag_value TEXT NOT NULL,
        PRIMARY KEY (asset_id, tag_key),
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
      )
    SQL

    ASSET_TAGS_INDEX = <<-SQL
      CREATE INDEX IF NOT EXISTS idx_tags_kv
        ON asset_tags(tag_key, tag_value)
    SQL

    IMAGE_META_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS image_meta (
        asset_id      INTEGER PRIMARY KEY,
        width         INTEGER,
        height        INTEGER,
        usage_class   TEXT,
        animated      INTEGER DEFAULT 0,
        frame_count   INTEGER,
        duration_ms   INTEGER,
        compression   TEXT DEFAULT 'original',
        quality_floor INTEGER,
        max_colors    INTEGER,
        target_format TEXT,
        presentation  TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
      )
    SQL

    AUDIO_META_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS audio_meta (
        asset_id      INTEGER PRIMARY KEY,
        duration_ms   INTEGER,
        sample_rate   INTEGER,
        bitrate       INTEGER,
        channels      INTEGER DEFAULT 1,
        transcript_id INTEGER,
        compression   TEXT DEFAULT 'original',
        target_format TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE,
        FOREIGN KEY (transcript_id) REFERENCES assets(id)
      )
    SQL

    VIDEO_META_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS video_meta (
        asset_id      INTEGER PRIMARY KEY,
        width         INTEGER,
        height        INTEGER,
        duration_ms   INTEGER,
        frame_rate    REAL,
        usage_class   TEXT,
        has_audio     INTEGER DEFAULT 0,
        compression   TEXT DEFAULT 'original',
        quality_floor INTEGER,
        target_format TEXT,
        presentation  TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
      )
    SQL

    TEXT_META_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS text_meta (
        asset_id  INTEGER PRIMARY KEY,
        content   TEXT NOT NULL,
        language  TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
      )
    SQL

    private def setup_schema : Nil
      @db.exec("PRAGMA journal_mode=WAL")
      @db.exec("PRAGMA foreign_keys=ON")

      # New asset store tables
      @db.exec(ASSETS_SCHEMA)
      ASSETS_INDEXES.split(";").each { |s| @db.exec(s.strip) unless s.strip.empty? }
      @db.exec(ASSET_TAGS_SCHEMA)
      @db.exec(ASSET_TAGS_INDEX)
      @db.exec(IMAGE_META_SCHEMA)
      @db.exec(AUDIO_META_SCHEMA)
      @db.exec(VIDEO_META_SCHEMA)
      @db.exec(TEXT_META_SCHEMA)
    end

    # ── Store ──

    def store_asset(
      asset_type : String,
      media : String,
      content_type : String,
      file_path : String,
      canonical_tags : Hash(String, String),
      extra_tags : Hash(String, String) = {} of String => String,
      file_hash : String? = nil,
      pool : Bool = false,
      permanent : Bool = false,
      generator : String? = nil,
      generation : String? = nil,
      image : ImageMeta? = nil,
      audio : AudioMeta? = nil,
      video : VideoMeta? = nil,
      text : TextMeta? = nil,
    ) : Int64
      # Invariant: the sidecar payload must match the media column that
      # get_with_meta later dispatches on. Only the struct matching `media`
      # may be non-nil; a mismatch would land a row in the wrong sidecar
      # table and read back as a silent nil. Fail loud at the write instead.
      offenders = [] of String
      offenders << "image" if image && media != "image"
      offenders << "audio" if audio && media != "audio"
      offenders << "video" if video && media != "video"
      offenders << "text" if text && media != "text"
      unless offenders.empty?
        raise ArgumentError.new(
          "media is #{media.inspect} but got #{offenders.join(", ")} metadata; " \
          "the sidecar struct must match the media kind"
        )
      end

      now = Time.utc.to_s(TIME_FORMAT)
      key = DataDungeon.canonical_key(canonical_tags)

      # For non-pool assets, replace existing with same canonical key
      unless pool
        existing = @db.query_one?(
          "SELECT id FROM assets WHERE asset_type = ? AND canonical_key = ? LIMIT 1",
          asset_type, key
        ) { |rs| rs.read(Int64) }
        if existing
          delete_asset(existing)
        end
      end

      @db.exec(
        <<-SQL,
          INSERT INTO assets
          (asset_type, media, content_type, file_path, canonical_key, file_hash,
           created_at, last_used_at, use_count, permanent, pool,
           generator, generation, rating, flagged)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, NULL, 0)
        SQL
        asset_type, media, content_type, file_path, key, file_hash,
        now, now, permanent ? 1 : 0, pool ? 1 : 0,
        generator, generation
      )

      asset_id = @db.scalar("SELECT last_insert_rowid()").as(Int64)

      # Store all tags (canonical + extra)
      all_tags = canonical_tags.merge(extra_tags)
      all_tags.each do |k, v|
        @db.exec(
          "INSERT INTO asset_tags (asset_id, tag_key, tag_value) VALUES (?, ?, ?)",
          asset_id, k, v
        )
      end

      # Store media-specific metadata
      if im = image
        @db.exec(
          <<-SQL,
            INSERT INTO image_meta
            (asset_id, width, height, usage_class, animated, frame_count,
             duration_ms, compression, quality_floor, max_colors,
             target_format, presentation)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          asset_id, im.width, im.height, im.usage_class,
          im.animated ? 1 : 0, im.frame_count, im.duration_ms,
          im.compression, im.quality_floor, im.max_colors,
          im.target_format, im.presentation
        )
      end

      if am = audio
        @db.exec(
          <<-SQL,
            INSERT INTO audio_meta
            (asset_id, duration_ms, sample_rate, bitrate, channels,
             transcript_id, compression, target_format)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          asset_id, am.duration_ms, am.sample_rate, am.bitrate,
          am.channels, am.transcript_id, am.compression, am.target_format
        )
      end

      if vm = video
        @db.exec(
          <<-SQL,
            INSERT INTO video_meta
            (asset_id, width, height, duration_ms, frame_rate, usage_class,
             has_audio, compression, quality_floor, target_format, presentation)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          asset_id, vm.width, vm.height, vm.duration_ms, vm.frame_rate,
          vm.usage_class, vm.has_audio ? 1 : 0, vm.compression,
          vm.quality_floor, vm.target_format, vm.presentation
        )
      end

      if tm = text
        @db.exec(
          "INSERT INTO text_meta (asset_id, content, language) VALUES (?, ?, ?)",
          asset_id, tm.content, tm.language
        )
      end

      asset_id
    end

    # ── High-level asset management (owns hashing, policy, file write) ──

    # Store an asset end to end: apply the media compression policy, hash the
    # resulting bytes, write the file to a storage key DataDungeon derives and
    # owns, then index it. Returns the stored AssetRecord.
    #
    # Provide the source as exactly one of `source_path` or `bytes`.
    def store(
      asset_type : String,
      canonical_tags : Hash(String, String),
      *,
      source_path : String? = nil,
      bytes : Bytes? = nil,
      content_type : String,
      media : String? = nil,
      extra_tags : Hash(String, String) = {} of String => String,
      pool : Bool = false,
      permanent : Bool = false,
      generator : String? = nil,
      generation : String? = nil,
      image : ImageMeta? = nil,
      audio : AudioMeta? = nil,
      video : VideoMeta? = nil,
      text : TextMeta? = nil,
    ) : AssetRecord
      store = @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"
      unless source_path.nil? ^ bytes.nil?
        raise ArgumentError.new("provide exactly one of source_path / bytes")
      end

      data = bytes || File.open(source_path.not_nil!, "rb", &.getb_to_end)
      ct = content_type
      m = media || infer_media(ct)

      # Apply the compression policy (may change bytes and content type).
      if m == "image" && (im = image)
        data, ct = process_image(data, ct, im)
      end

      file_hash = Digest::SHA256.hexdigest(data)
      key = DataDungeon.canonical_key(canonical_tags)
      prefix = key[0, 2]
      ext = ext_for(ct)
      storage_key =
        if pool
          File.join(asset_type, prefix, key, "#{file_hash}.#{ext}")
        else
          File.join(asset_type, prefix, "#{key}.#{ext}")
        end

      # Write-skip: single-best re-store of identical bytes is a no-op.
      unless pool
        if existing = find_asset(asset_type, canonical_tags)
          if existing.file_hash == file_hash && store.exists?(existing.file_path)
            touch_asset(existing.id)
            return existing
          end
        end
      end

      store.write(storage_key, data)

      id = store_asset(
        asset_type: asset_type,
        media: m,
        content_type: ct,
        file_path: storage_key,
        canonical_tags: canonical_tags,
        extra_tags: extra_tags,
        file_hash: file_hash,
        pool: pool,
        permanent: permanent,
        generator: generator,
        generation: generation,
        image: image,
        audio: audio,
        video: video,
        text: text,
      )

      find_asset_by_id(id).not_nil!
    end

    # High-level lookup: verifies the backing file still exists (self-heals a
    # stale row to a miss), touches usage, and returns the record. Retires the
    # caller-side File.exists? cache-gate.
    def get(asset_type : String, canonical_tags : Hash(String, String), touch : Bool = true) : AssetRecord?
      rec = find_asset(asset_type, canonical_tags)
      return nil unless rec
      if store = @storage
        return nil unless store.exists?(rec.file_path)
      end
      touch_asset(rec.id) if touch
      rec
    end

    # Eager lookup: record + the media metadata appropriate to the asset's
    # media (ImageMeta / AudioMeta / VideoMeta / TextMeta), returned as the
    # polymorphic AssetMeta base, in a single query. Same self-heal + touch
    # semantics as `get`. Returns {record, meta?} or nil on miss; meta is nil
    # when the asset has no sidecar row. Callers narrow with `.as?(ImageMeta)`
    # when they need media-specific fields; `.presentation` works directly on
    # any visual medium without narrowing.
    def get_with_meta(
      asset_type : String,
      canonical_tags : Hash(String, String),
      touch : Bool = true,
    ) : {AssetRecord, AssetMeta?}?
      key = DataDungeon.canonical_key(canonical_tags)
      pair = @db.query_one?(
        <<-SQL,
          SELECT a.*,
                 im.asset_id, im.width, im.height, im.usage_class, im.animated,
                 im.frame_count, im.duration_ms, im.compression, im.quality_floor,
                 im.max_colors, im.target_format, im.presentation,
                 am.asset_id, am.duration_ms, am.sample_rate, am.bitrate,
                 am.channels, am.transcript_id, am.compression, am.target_format,
                 vm.asset_id, vm.width, vm.height, vm.duration_ms, vm.frame_rate,
                 vm.usage_class, vm.has_audio, vm.compression, vm.quality_floor,
                 vm.target_format, vm.presentation,
                 tm.asset_id, tm.content, tm.language
          FROM assets a
          LEFT JOIN image_meta im ON im.asset_id = a.id
          LEFT JOIN audio_meta am ON am.asset_id = a.id
          LEFT JOIN video_meta vm ON vm.asset_id = a.id
          LEFT JOIN text_meta  tm ON tm.asset_id = a.id
          WHERE a.asset_type = ? AND a.canonical_key = ?
          LIMIT 1
        SQL
        asset_type, key
      ) do |rs|
        rec = read_asset_record(rs)
        # Consume every sidecar block in order to keep the cursor aligned,
        # then pick the one matching this asset's media.
        im = read_image_meta_join(rs)
        am = read_audio_meta_join(rs)
        vm = read_video_meta_join(rs)
        tm = read_text_meta_join(rs)
        meta = case rec.media
               when "image" then im
               when "audio" then am
               when "video" then vm
               when "text"  then tm
               else              nil
               end
        {rec, meta.as(AssetMeta?)}
      end
      return nil unless pair

      rec, meta = pair
      if store = @storage
        return nil unless store.exists?(rec.file_path)
      end
      touch_asset(rec.id) if touch
      {rec, meta}
    end

    # Resolve a record's storage key to a usable location (local path or URL).
    def path_for(rec : AssetRecord) : String
      store = @storage || raise "DataDungeon::DB has no storage backend"
      store.resolve(rec.file_path)
    end

    # ── Media policy / processing ──

    private def process_image(data : Bytes, content_type : String, meta : ImageMeta) : {Bytes, String}
      policy = meta.compression
      return {data, content_type} if policy == "original"

      target = meta.target_format || "webp"
      return {data, content_type} unless target == "webp"   # only WebP output supported today
      return {data, content_type} if content_type.downcase == "image/webp"  # already target

      quality = case policy
                when "compress" then (meta.quality_floor || 80).to_f32
                else                 (meta.quality_floor || 90).to_f32  # normalize
                end

      case content_type.downcase
      when "image/png"
        {WebP.png_to_webp_bytes(data, quality), "image/webp"}
      else
        {data, content_type}   # unsupported input (jpg/etc.) — passthrough for now
      end
    end

    private def infer_media(content_type : String) : String
      case content_type.downcase
      when .starts_with?("image/") then "image"
      when .starts_with?("audio/") then "audio"
      when .starts_with?("video/") then "video"
      when .starts_with?("text/")  then "text"
      else                              "image"
      end
    end

    private def ext_for(content_type : String) : String
      case content_type.downcase
      when "image/webp"               then "webp"
      when "image/png"                then "png"
      when "image/jpeg", "image/jpg"  then "jpg"
      when "image/gif"                then "gif"
      when "audio/mpeg", "audio/mp3"  then "mp3"
      when "audio/ogg"                then "ogg"
      when "audio/wav", "audio/x-wav" then "wav"
      when "video/webm"               then "webm"
      when "video/mp4"                then "mp4"
      when "text/plain"               then "txt"
      when "application/json"         then "json"
      else                                 "bin"
      end
    end

    # ── Find ──

    def find_asset(asset_type : String, canonical_tags : Hash(String, String)) : AssetRecord?
      key = DataDungeon.canonical_key(canonical_tags)
      @db.query_one?(
        "SELECT * FROM assets WHERE asset_type = ? AND canonical_key = ? LIMIT 1",
        asset_type, key
      ) { |rs| read_asset_record(rs) }
    end

    def find_asset_by_id(id : Int64) : AssetRecord?
      @db.query_one?(
        "SELECT * FROM assets WHERE id = ? LIMIT 1", id
      ) { |rs| read_asset_record(rs) }
    end

    def find_assets_by_tags(asset_type : String, filter_tags : Hash(String, String)) : Array(AssetRecord)
      return [] of AssetRecord if filter_tags.empty?

      conditions = filter_tags.map { |_, _| "(t.tag_key = ? AND t.tag_value = ?)" }.join(" OR ")
      sql = <<-SQL
        SELECT a.* FROM assets a
        JOIN asset_tags t ON t.asset_id = a.id
        WHERE a.asset_type = ? AND (#{conditions})
        GROUP BY a.id
        HAVING COUNT(*) = ?
      SQL

      params = [] of ::DB::Any
      params << asset_type
      filter_tags.each do |k, v|
        params << k
        params << v
      end
      params << filter_tags.size.to_i64

      results = [] of AssetRecord
      @db.query(sql, args: params) do |rs|
        rs.each { results << read_asset_record(rs) }
      end
      results
    end

    def asset_exists?(asset_type : String, canonical_tags : Hash(String, String)) : Bool
      key = DataDungeon.canonical_key(canonical_tags)
      result = @db.scalar(
        "SELECT COUNT(*) FROM assets WHERE asset_type = ? AND canonical_key = ?",
        asset_type, key
      )
      result.as(Int64) > 0
    end

    # ── Touch ──

    def touch_asset(id : Int64) : Nil
      now = Time.utc.to_s(TIME_FORMAT)
      @db.exec(
        "UPDATE assets SET last_used_at = ?, use_count = use_count + 1 WHERE id = ?",
        now, id
      )
    end

    # ── Tags ──

    def load_tags(asset_id : Int64) : Hash(String, String)
      tags = {} of String => String
      @db.query("SELECT tag_key, tag_value FROM asset_tags WHERE asset_id = ?", asset_id) do |rs|
        rs.each { tags[rs.read(String)] = rs.read(String) }
      end
      tags
    end

    def load_tags_batch(asset_ids : Array(Int64)) : Hash(Int64, Hash(String, String))
      result = {} of Int64 => Hash(String, String)
      return result if asset_ids.empty?

      placeholders = asset_ids.map { "?" }.join(", ")
      params = asset_ids.map(&.as(::DB::Any))
      @db.query(
        "SELECT asset_id, tag_key, tag_value FROM asset_tags WHERE asset_id IN (#{placeholders})",
        args: params
      ) do |rs|
        rs.each do
          aid = rs.read(Int64)
          k = rs.read(String)
          v = rs.read(String)
          result[aid] ||= {} of String => String
          result[aid][k] = v
        end
      end
      result
    end

    # ── Media Meta ──

    def load_image_meta(asset_id : Int64) : ImageMeta?
      @db.query_one?(
        "SELECT * FROM image_meta WHERE asset_id = ?", asset_id
      ) do |rs|
        _id = rs.read(Int64) # asset_id
        ImageMeta.new(
          width: rs.read(Int32?),
          height: rs.read(Int32?),
          usage_class: rs.read(String?),
          animated: (rs.read(Int32?) || 0) != 0,
          frame_count: rs.read(Int32?),
          duration_ms: rs.read(Int32?),
          compression: rs.read(String?) || "original",
          quality_floor: rs.read(Int32?),
          max_colors: rs.read(Int32?),
          target_format: rs.read(String?),
          presentation: rs.read(String?),
        )
      end
    end

    def load_audio_meta(asset_id : Int64) : AudioMeta?
      @db.query_one?(
        "SELECT * FROM audio_meta WHERE asset_id = ?", asset_id
      ) do |rs|
        _id = rs.read(Int64)
        AudioMeta.new(
          duration_ms: rs.read(Int32?),
          sample_rate: rs.read(Int32?),
          bitrate: rs.read(Int32?),
          channels: rs.read(Int32?) || 1,
          transcript_id: rs.read(Int64?),
          compression: rs.read(String?) || "original",
          target_format: rs.read(String?),
        )
      end
    end

    def load_video_meta(asset_id : Int64) : VideoMeta?
      @db.query_one?(
        "SELECT * FROM video_meta WHERE asset_id = ?", asset_id
      ) do |rs|
        _id = rs.read(Int64)
        VideoMeta.new(
          width: rs.read(Int32?),
          height: rs.read(Int32?),
          duration_ms: rs.read(Int32?),
          frame_rate: rs.read(Float64?),
          usage_class: rs.read(String?),
          has_audio: (rs.read(Int32?) || 0) != 0,
          compression: rs.read(String?) || "original",
          quality_floor: rs.read(Int32?),
          target_format: rs.read(String?),
          presentation: rs.read(String?),
        )
      end
    end

    def load_text_meta(asset_id : Int64) : TextMeta?
      @db.query_one?(
        "SELECT * FROM text_meta WHERE asset_id = ?", asset_id
      ) do |rs|
        _id = rs.read(Int64)
        TextMeta.new(
          content: rs.read(String),
          language: rs.read(String?),
        )
      end
    end

    # ── Delete ──

    def delete_asset(id : Int64) : Nil
      # Sidecar tables cleaned up by ON DELETE CASCADE
      @db.exec("DELETE FROM assets WHERE id = ?", id)
    end

    # ── Pool helpers ──

    def count_pool_assets(asset_type : String, filter_tags : Hash(String, String)) : Int32
      return @db.scalar("SELECT COUNT(*) FROM assets WHERE asset_type = ?", asset_type).as(Int64).to_i32 if filter_tags.empty?

      conditions = filter_tags.map { |_, _| "(t.tag_key = ? AND t.tag_value = ?)" }.join(" OR ")
      sql = <<-SQL
        SELECT COUNT(*) FROM (
          SELECT a.id FROM assets a
          JOIN asset_tags t ON t.asset_id = a.id
          WHERE a.asset_type = ? AND (#{conditions})
          GROUP BY a.id
          HAVING COUNT(*) = ?
        )
      SQL

      params = [] of ::DB::Any
      params << asset_type
      filter_tags.each do |k, v|
        params << k
        params << v
      end
      params << filter_tags.size.to_i64

      @db.scalar(sql, args: params).as(Int64).to_i32
    end

    def random_pool_text(asset_type : String, filter_tags : Hash(String, String)) : String?
      if filter_tags.empty?
        return @db.query_one?(
          <<-SQL,
            SELECT tm.content FROM assets a
            JOIN text_meta tm ON tm.asset_id = a.id
            WHERE a.asset_type = ?
            ORDER BY RANDOM() LIMIT 1
          SQL
          asset_type
        ) { |rs| rs.read(String) }
      end

      conditions = filter_tags.map { |_, _| "(t.tag_key = ? AND t.tag_value = ?)" }.join(" OR ")
      sql = <<-SQL
        SELECT tm.content FROM assets a
        JOIN asset_tags t ON t.asset_id = a.id
        JOIN text_meta tm ON tm.asset_id = a.id
        WHERE a.asset_type = ? AND (#{conditions})
        GROUP BY a.id
        HAVING COUNT(DISTINCT t.tag_key) = ?
        ORDER BY RANDOM() LIMIT 1
      SQL

      params = [] of ::DB::Any
      params << asset_type
      filter_tags.each do |k, v|
        params << k
        params << v
      end
      params << filter_tags.size.to_i64

      @db.query_one?(sql, args: params) { |rs| rs.read(String) }
    end

    # ── Eviction helpers ──

    def eviction_candidates(limit : Int32 = 100) : Array(AssetRecord)
      results = [] of AssetRecord
      @db.query(
        <<-SQL,
          SELECT * FROM assets
          WHERE permanent = 0
          ORDER BY last_used_at ASC NULLS FIRST
          LIMIT ?
        SQL
        limit
      ) do |rs|
        rs.each { results << read_asset_record(rs) }
      end
      results
    end

    # ── Internal ──

    # Read image_meta columns from a joined row (columns follow assets.*).
    # Returns nil when the LEFT JOIN produced no image_meta row (asset_id NULL).
    private def read_image_meta_join(rs) : ImageMeta?
      asset_id = rs.read(Int64?)
      if asset_id.nil?
        # Consume the remaining NULL meta columns so the row cursor stays aligned.
        11.times { rs.read(::DB::Any) }
        return nil
      end
      ImageMeta.new(
        width: rs.read(Int32?),
        height: rs.read(Int32?),
        usage_class: rs.read(String?),
        animated: (rs.read(Int32?) || 0) != 0,
        frame_count: rs.read(Int32?),
        duration_ms: rs.read(Int32?),
        compression: rs.read(String?) || "original",
        quality_floor: rs.read(Int32?),
        max_colors: rs.read(Int32?),
        target_format: rs.read(String?),
        presentation: rs.read(String?),
      )
    end

    # Read audio_meta columns from a joined row (7 columns after asset_id).
    private def read_audio_meta_join(rs) : AudioMeta?
      asset_id = rs.read(Int64?)
      if asset_id.nil?
        7.times { rs.read(::DB::Any) }
        return nil
      end
      AudioMeta.new(
        duration_ms: rs.read(Int32?),
        sample_rate: rs.read(Int32?),
        bitrate: rs.read(Int32?),
        channels: rs.read(Int32?) || 1,
        transcript_id: rs.read(Int64?),
        compression: rs.read(String?) || "original",
        target_format: rs.read(String?),
      )
    end

    # Read video_meta columns from a joined row (10 columns after asset_id).
    private def read_video_meta_join(rs) : VideoMeta?
      asset_id = rs.read(Int64?)
      if asset_id.nil?
        10.times { rs.read(::DB::Any) }
        return nil
      end
      VideoMeta.new(
        width: rs.read(Int32?),
        height: rs.read(Int32?),
        duration_ms: rs.read(Int32?),
        frame_rate: rs.read(Float64?),
        usage_class: rs.read(String?),
        has_audio: (rs.read(Int32?) || 0) != 0,
        compression: rs.read(String?) || "original",
        quality_floor: rs.read(Int32?),
        target_format: rs.read(String?),
        presentation: rs.read(String?),
      )
    end

    # Read text_meta columns from a joined row (2 columns after asset_id).
    private def read_text_meta_join(rs) : TextMeta?
      asset_id = rs.read(Int64?)
      if asset_id.nil?
        2.times { rs.read(::DB::Any) }
        return nil
      end
      TextMeta.new(
        content: rs.read(String),
        language: rs.read(String?),
      )
    end

    private def read_asset_record(rs) : AssetRecord
      AssetRecord.new(
        id: rs.read(Int64),
        asset_type: rs.read(String),
        media: rs.read(String),
        content_type: rs.read(String),
        file_path: rs.read(String),
        canonical_key: rs.read(String),
        file_hash: rs.read(String?),
        created_at: rs.read(String),
        last_used_at: rs.read(String?),
        use_count: (rs.read(Int32?) || 0),
        permanent: (rs.read(Int32?) || 0) != 0,
        pool: (rs.read(Int32?) || 0) != 0,
        generator: rs.read(String?),
        generation: rs.read(String?),
        rating: rs.read(Int32?),
        flagged: (rs.read(Int32?) || 0) != 0,
      )
    end
  end
end
