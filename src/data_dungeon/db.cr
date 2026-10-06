require "sqlite3"
require "digest/sha256"
require "json"

module DataDungeon
  class DB
    TIME_FORMAT = "%F %T"

    @db : ::DB::Database
    @indexer : AssetIndexer? = nil
    getter storage : Storage?
    # Objects are content addressed, so several rows may share one. Writing an
    # object and indexing its row, or dropping a row and unlinking its object
    # once unreferenced, happen under this lock so neither interleaves with the
    # other inside this process.
    @object_lock = Mutex.new(:reentrant)
    # Registered asset types, loaded from asset_types when the DB opens.
    @types = {} of String => AssetType

    # Shared connection for extensions that keep their tables in the asset DB.
    def connection : ::DB::Database
      @db
    end

    def attach_indexer(indexer : AssetIndexer) : Nil
      raise "an asset indexer is already attached" if @indexer
      @indexer = indexer
    end

    def initialize(path : String, storage : Storage? = nil, cache_root : String? = nil)
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      # Pragmas in the URI apply to every pooled connection: deletes cascade to
      # tags and sidecars whichever connection runs them, and a write that
      # meets another connection's open transaction waits for it (up to 5 s)
      # rather than failing at once with "database is locked".
      @db = ::DB.open("sqlite3://#{path}?foreign_keys=on&busy_timeout=5000")
      @storage = storage || (cache_root ? LocalStorage.new(cache_root) : nil)
      setup_schema
    end

    def close : Nil
      @indexer.try(&.close)
      @db.close
    end

    # ── Schema ──

    ASSETS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS assets (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_type    TEXT NOT NULL,
        media         TEXT NOT NULL,
        content_type  TEXT NOT NULL,
        file_path     TEXT NOT NULL,
        pool_key      TEXT,
        file_hash     TEXT,
        created_at    TEXT NOT NULL,
        last_used_at  TEXT,
        use_count     INTEGER DEFAULT 0,
        permanent     INTEGER DEFAULT 0,
        pool          INTEGER DEFAULT 0,
        generator     TEXT,
        generation    TEXT,
        description   TEXT,
        generated     INTEGER NOT NULL DEFAULT 0,
        rating        INTEGER,
        flagged       INTEGER DEFAULT 0
      )
    SQL

    ASSETS_INDEXES = <<-SQL
      CREATE INDEX IF NOT EXISTS idx_assets_pool_key
        ON assets(pool_key);
      CREATE UNIQUE INDEX IF NOT EXISTS idx_assets_single_key
        ON assets(asset_type, pool_key)
        WHERE pool_key IS NOT NULL AND pool = 0;
      CREATE INDEX IF NOT EXISTS idx_assets_type
        ON assets(asset_type);
      CREATE INDEX IF NOT EXISTS idx_assets_file_path
        ON assets(file_path);
      CREATE INDEX IF NOT EXISTS idx_assets_generator
        ON assets(generator)
    SQL

    ASSET_TAGS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_tags (
        asset_id  INTEGER NOT NULL,
        tag_key   TEXT NOT NULL,
        tag_value TEXT NOT NULL,
        custom    INTEGER NOT NULL DEFAULT 0,
        asset_type TEXT NOT NULL,
        PRIMARY KEY (asset_id, tag_key),
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
      )
    SQL

    # Tag ranges are per type, so a lookup never walks other types' tags.
    ASSET_TAGS_INDEX = <<-SQL
      CREATE INDEX IF NOT EXISTS idx_tags_type_kv
        ON asset_tags(asset_type, tag_key, tag_value)
    SQL

    # One row per registered asset type. Trait lists are JSON arrays in
    # registration order and labels a JSON object;
    # key_scheme records the TraitKey format the stored keys were made with.
    ASSET_TYPES_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_types (
        asset_type   TEXT PRIMARY KEY,
        pool_traits  TEXT NOT NULL,
        group_traits TEXT NOT NULL,
        labels       TEXT NOT NULL DEFAULT '{}',
        pool         INTEGER NOT NULL,
        key_scheme   INTEGER NOT NULL
      )
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

      # New asset store tables
      @db.exec(ASSETS_SCHEMA)
      migrate_assets_schema
      ASSETS_INDEXES.split(";").each { |s| @db.exec(s.strip) unless s.strip.empty? }
      @db.exec("DROP INDEX IF EXISTS idx_assets_lookup") # keys now name their type
      @db.exec(ASSET_TAGS_SCHEMA)
      unless table_columns("asset_tags").has_key?("custom")
        @db.exec("ALTER TABLE asset_tags ADD COLUMN custom INTEGER NOT NULL DEFAULT 0")
      end
      migrate_tag_types
      @db.exec(ASSET_TAGS_INDEX)
      @db.exec("DROP INDEX IF EXISTS idx_tags_kv") # superseded by idx_tags_type_kv
      @db.exec(ASSET_TYPES_SCHEMA)
      @db.exec(IMAGE_META_SCHEMA)
      @db.exec(AUDIO_META_SCHEMA)
      @db.exec(VIDEO_META_SCHEMA)
      @db.exec(TEXT_META_SCHEMA)
      load_types
    end

    # Column name => NOT NULL flag for a table.
    private def table_columns(table : String) : Hash(String, Int32)
      columns = {} of String => Int32
      @db.query("PRAGMA table_info(#{table})") do |rs|
        rs.each do
          rs.read(Int32)
          name = rs.read(String)
          rs.read(String)
          columns[name] = rs.read(Int32)
          rs.read(::DB::Any)
          rs.read(Int32)
        end
      end
      columns
    end

    # Older tag tables lacked asset_type. Copy it from each tag's asset, after
    # dropping tags whose asset is gone (unreachable; a delete made on a
    # connection without foreign keys could leave them).
    private def migrate_tag_types : Nil
      return if table_columns("asset_tags").has_key?("asset_type")
      @db.transaction do |tx|
        conn = tx.connection
        conn.exec("DELETE FROM asset_tags WHERE asset_id NOT IN (SELECT id FROM assets)")
        conn.exec("ALTER TABLE asset_tags ADD COLUMN asset_type TEXT NOT NULL DEFAULT ''")
        conn.exec("UPDATE asset_tags SET asset_type = (SELECT a.asset_type FROM assets a WHERE a.id = asset_tags.asset_id)")
      end
    end

    # Older databases called the pool key canonical_key (and once required
    # it), lacked the group key or description fields, or required a unique
    # file_path (objects are now shared by content). Rebuild only that table;
    # its child tables retain their asset_id references.
    private def migrate_assets_schema : Nil
      columns = table_columns("assets")
      return if columns["pool_key"]? == 0 && columns.has_key?("description") &&
                columns.has_key?("generated") && !unique_file_path?

      pool_key = columns.has_key?("pool_key") ? "pool_key" : (columns.has_key?("canonical_key") ? "canonical_key" : "NULL")
      description = columns.has_key?("description") ? "description" : "NULL"
      generated = columns.has_key?("generated") ? "generated" : "CASE WHEN generator IS NULL THEN 0 ELSE 1 END"

      # foreign_keys is per connection, and dropping the old table with it on
      # would cascade-delete every tag and sidecar row. Keep the pragma and the
      # rebuild on one connection.
      @db.using_connection do |conn|
        conn.exec("PRAGMA foreign_keys=OFF")
        begin
          conn.transaction do |tx|
            tc = tx.connection
            tc.exec(ASSETS_SCHEMA.sub("IF NOT EXISTS assets", "assets_migrated"))
            tc.exec(<<-SQL)
              INSERT INTO assets_migrated
              (id, asset_type, media, content_type, file_path, pool_key, file_hash,
               created_at, last_used_at, use_count, permanent, pool, generator,
               generation, description, generated, rating, flagged)
              SELECT id, asset_type, media, content_type, file_path, #{pool_key}, file_hash,
                     created_at, last_used_at, use_count, permanent, pool, generator,
                     generation, #{description}, #{generated}, rating, flagged
              FROM assets
            SQL
            tc.exec("DROP TABLE assets")
            tc.exec("ALTER TABLE assets_migrated RENAME TO assets")
          end
        ensure
          conn.exec("PRAGMA foreign_keys=ON")
        end
        violations = conn.query_all("PRAGMA foreign_key_check") { |rs| rs.read(::DB::Any) }
        raise "asset schema migration left invalid references" unless violations.empty?
      end
    end

    # Whether the assets table still carries a UNIQUE constraint on file_path.
    private def unique_file_path? : Bool
      constraint_indexes = [] of String
      @db.query("PRAGMA index_list(assets)") do |rs|
        rs.each do
          rs.read(Int32) # seq
          name = rs.read(String)
          unique = rs.read(Int32)
          origin = rs.read(String)
          rs.read(Int32) # partial
          constraint_indexes << name if unique == 1 && origin == "u"
        end
      end
      constraint_indexes.any? do |name|
        @db.query_all(%(PRAGMA index_info("#{name}"))) { |rs|
          rs.read(Int32)
          rs.read(Int32)
          rs.read(String?)
        }.includes?("file_path")
      end
    end

    # ── Store ──

    # Index a file whose path the caller owns. For a registered type,
    # DataDungeon normalizes the trait tags and derives pool_key
    # from them, so `pool_key` and `pool` must not be given. An unregistered
    # type may pass an explicit `pool_key`. `custom` names the tags whose
    # values are not among the application's standard choices; they are keyed
    # like any other value and can later be promoted.
    def store_asset(
      asset_type : String,
      media : String,
      content_type : String,
      file_path : String,
      tags : Hash(String, String) = {} of String => String,
      pool_key : String? = nil,
      file_hash : String? = nil,
      pool : Bool? = nil,
      permanent : Bool = false,
      generator : String? = nil,
      generation : String? = nil,
      description : String? = nil,
      generated : Bool = false,
      image : ImageMeta? = nil,
      audio : AudioMeta? = nil,
      video : VideoMeta? = nil,
      text : TextMeta? = nil,
      custom : Array(String) = [] of String,
      canonical_key : String? = nil, # deprecated: use pool_key
    ) : Int64
      pool_key ||= canonical_key
      validate_store(asset_type, media, tags, pool_key, pool, custom, image, audio, video, text)
      pooled = pool || false
      if type = @types[asset_type]?
        tags = normalize_traits(type, tags)
        pool_key = type.key(tags)
        pooled = type.pool
      end

      now = Time.utc.to_s(TIME_FORMAT)
      old_path : String? = nil
      asset_id = 0_i64

      @object_lock.synchronize do
        @db.transaction do |tx|
          conn = tx.connection
          existing = if pool_key && !pooled
                       conn.query_one?(
                         "SELECT id, file_path FROM assets WHERE asset_type = ? AND pool_key = ? AND pool = 0 LIMIT 1",
                         asset_type, pool_key
                       ) { |rs| {rs.read(Int64), rs.read(String)} }
                     end

          if existing
            asset_id, old_path = existing
            conn.exec(
              <<-SQL,
              UPDATE assets SET media = ?, content_type = ?, file_path = ?, file_hash = ?,
                last_used_at = ?, permanent = ?, generator = ?, generation = ?,
                description = ?, generated = ? WHERE id = ?
            SQL
              media, content_type, file_path, file_hash, now, permanent ? 1 : 0,
              generator, generation, description, generated ? 1 : 0, asset_id
            )
            conn.exec("DELETE FROM asset_tags WHERE asset_id = ?", asset_id)
            conn.exec("DELETE FROM image_meta WHERE asset_id = ?", asset_id)
            conn.exec("DELETE FROM audio_meta WHERE asset_id = ?", asset_id)
            conn.exec("DELETE FROM video_meta WHERE asset_id = ?", asset_id)
            conn.exec("DELETE FROM text_meta WHERE asset_id = ?", asset_id)
          else
            conn.exec(
              <<-SQL,
              INSERT INTO assets
              (asset_type, media, content_type, file_path, pool_key, file_hash,
               created_at, last_used_at, use_count, permanent, pool,
               generator, generation, description, generated, rating, flagged)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, NULL, 0)
            SQL
              asset_type, media, content_type, file_path, pool_key, file_hash,
              now, now, permanent ? 1 : 0, pooled ? 1 : 0,
              generator, generation, description, generated ? 1 : 0
            )
            asset_id = conn.scalar("SELECT last_insert_rowid()").as(Int64)
          end

          tags.each do |k, v|
            conn.exec(
              "INSERT INTO asset_tags (asset_id, asset_type, tag_key, tag_value, custom) VALUES (?, ?, ?, ?, ?)",
              asset_id, asset_type, k, v, custom.includes?(k) ? 1 : 0
            )
          end

          # Store media-specific metadata
          if im = image
            conn.exec(
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
            conn.exec(
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
            conn.exec(
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
            conn.exec(
              "INSERT INTO text_meta (asset_id, content, language) VALUES (?, ?, ?)",
              asset_id, tm.content, tm.language
            )
          end
        end
        if (superseded = old_path) && superseded != file_path
          release_object(superseded)
        end
      end
      @indexer.try(&.enqueue_asset(asset_id))
      asset_id
    end

    private def validate_store(
      asset_type : String, media : String, tags : Hash(String, String),
      pool_key : String?, pool : Bool?, custom : Array(String),
      image : ImageMeta?, audio : AudioMeta?, video : VideoMeta?, text : TextMeta?,
    ) : Nil
      if @types.has_key?(asset_type)
        if pool_key
          raise ArgumentError.new("#{asset_type} is registered: DataDungeon derives its pool_key from its traits")
        end
        unless pool.nil?
          raise ArgumentError.new("#{asset_type} is registered: whether it pools comes from its registration")
        end
      end
      unless (unknown = custom - tags.keys).empty?
        raise ArgumentError.new("custom names #{unknown.join(", ")}, which have no tag")
      end

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
    end

    # ── High-level asset management (owns media policy and file write) ──

    # Store an asset end to end: apply the media compression policy, hash the
    # resulting bytes, write them to their content-addressed key
    # (`<first two hex chars>/<sha256>.<ext>`), then index the row. Identical
    # bytes share one object. Returns the stored AssetRecord.
    #
    # Provide the source as exactly one of `source_path` or `bytes`.
    def store(
      asset_type : String,
      tags : Hash(String, String) = {} of String => String,
      *,
      pool_key : String? = nil,
      source_path : String? = nil,
      bytes : Bytes? = nil,
      content_type : String,
      media : String? = nil,
      pool : Bool? = nil,
      permanent : Bool = false,
      generator : String? = nil,
      generation : String? = nil,
      description : String? = nil,
      generated : Bool = false,
      image : ImageMeta? = nil,
      audio : AudioMeta? = nil,
      video : VideoMeta? = nil,
      text : TextMeta? = nil,
      custom : Array(String) = [] of String,
      canonical_key : String? = nil, # deprecated: use pool_key
    ) : AssetRecord
      store = @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"
      unless source_path.nil? ^ bytes.nil?
        raise ArgumentError.new("provide exactly one of source_path / bytes")
      end
      pool_key ||= canonical_key
      ct = content_type
      m = media || infer_media(ct)
      # Reject bad arguments before writing, so a refused store leaves no object.
      validate_store(asset_type, m, tags, pool_key, pool, custom, image, audio, video, text)

      data = bytes || File.open(source_path.not_nil!, "rb", &.getb_to_end)

      # Apply the compression policy (may change bytes and content type).
      if m == "image" && (im = image)
        data, ct = process_image(data, ct, im)
      end

      file_hash = Digest::SHA256.hexdigest(data)
      storage_key = object_key(file_hash, ct)

      id = @object_lock.synchronize do
        store.write(storage_key, data) unless store.exists?(storage_key)
        store_asset(
          asset_type: asset_type,
          media: m,
          content_type: ct,
          file_path: storage_key,
          tags: tags,
          pool_key: pool_key,
          file_hash: file_hash,
          pool: pool,
          custom: custom,
          permanent: permanent,
          generator: generator,
          generation: generation,
          description: description,
          generated: generated,
          image: image,
          audio: audio,
          video: video,
          text: text,
        )
      end

      find_asset_by_id(id).not_nil!
    end

    # High-level lookup: verifies the backing file still exists (self-heals a
    # stale row to a miss), touches usage, and returns the record. Retires the
    # caller-side File.exists? cache-gate. Single-best assets only; a pool's
    # members come from find_pool.
    def get(asset_type : String, pool_key : String, touch : Bool = true) : AssetRecord?
      rec = find_asset(asset_type, pool_key)
      return nil unless rec
      if store = @storage
        return nil unless store.exists?(rec.file_path)
      end
      touch_asset(rec.id) if touch
      rec
    end

    # `get` for a registered type, by its traits.
    def get(asset_type : String, traits : Hash(String, String), touch : Bool = true) : AssetRecord?
      get(pool_key_for(asset_type, traits), touch)
    end

    # `get` by a registered type's key alone; the key names its type.
    def get(pool_key : String, touch : Bool = true) : AssetRecord?
      rec = @db.query_one?(
        "SELECT * FROM assets WHERE pool_key = ? AND pool = 0 LIMIT 1", pool_key
      ) { |rs| read_asset_record(rs) }
      return nil unless rec
      if store = @storage
        return nil unless store.exists?(rec.file_path)
      end
      touch_asset(rec.id) if touch
      rec
    end

    # Assets without a pool key are addressed by their database ID.
    def get_by_id(id : Int64, touch : Bool = true) : AssetRecord?
      rec = find_asset_by_id(id)
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
      pool_key : String,
      touch : Bool = true,
    ) : {AssetRecord, AssetMeta?}?
      lookup_with_meta(
        "a.asset_type = ? AND a.pool_key = ? AND a.pool = 0",
        [asset_type, pool_key] of ::DB::Any,
        touch
      )
    end

    # `get_with_meta` for a registered type, by its traits.
    def get_with_meta(
      asset_type : String,
      traits : Hash(String, String),
      touch : Bool = true,
    ) : {AssetRecord, AssetMeta?}?
      get_with_meta(pool_key_for(asset_type, traits), touch)
    end

    # `get_with_meta` by a registered type's key alone.
    def get_with_meta(pool_key : String, touch : Bool = true) : {AssetRecord, AssetMeta?}?
      lookup_with_meta("a.pool_key = ? AND a.pool = 0", [pool_key] of ::DB::Any, touch)
    end

    def get_with_meta_by_id(id : Int64, touch : Bool = true) : {AssetRecord, AssetMeta?}?
      lookup_with_meta("a.id = ?", [id] of ::DB::Any, touch)
    end

    private def lookup_with_meta(where_clause : String, args : Array(::DB::Any), touch : Bool) : {AssetRecord, AssetMeta?}?
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
          WHERE #{where_clause}
          LIMIT 1
        SQL


        args: args
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
      return {data, content_type} unless target == "webp"                  # only WebP output supported today
      return {data, content_type} if content_type.downcase == "image/webp" # already target

      quality = case policy
                when "compress" then (meta.quality_floor || 80).to_f32
                else                 (meta.quality_floor || 90).to_f32 # normalize
                end

      case content_type.downcase
      when "image/png"
        {WebP.png_to_webp_bytes(data, quality), "image/webp"}
      else
        {data, content_type} # unsupported input (jpg/etc.) — passthrough for now
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

    # ── Objects ──

    # Content-addressed storage key: the SHA-256 of the stored bytes, under a
    # directory named for its first two hex characters, with an extension from
    # the content type so files served or opened by path keep their type.
    private def object_key(file_hash : String, content_type : String) : String
      "#{file_hash[0, 2]}/#{file_hash}.#{ext_for(content_type)}"
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

    # Unlink an object once no row references it. Callers hold @object_lock.
    private def release_object(key : String) : Nil
      store = @storage
      return unless store
      referenced = @db.query_one?("SELECT 1 FROM assets WHERE file_path = ? LIMIT 1", key, as: Int64)
      store.delete(key) unless referenced
    end

    # ── Find ──

    def find_asset(asset_type : String, pool_key : String) : AssetRecord?
      @db.query_one?(
        "SELECT * FROM assets WHERE asset_type = ? AND pool_key = ? AND pool = 0 LIMIT 1",
        asset_type, pool_key
      ) { |rs| read_asset_record(rs) }
    end

    def find_asset_by_id(id : Int64) : AssetRecord?
      @db.query_one?(
        "SELECT * FROM assets WHERE id = ? LIMIT 1", id
      ) { |rs| read_asset_record(rs) }
    end

    # Assets of a type carrying every one of these tags (and possibly others).
    def find_assets_by_tags(asset_type : String, filter_tags : Hash(String, String)) : Array(AssetRecord)
      filter_tags = normalize_tags(asset_type, filter_tags)
      return [] of AssetRecord if filter_tags.empty?
      from, where, args = tag_filter(asset_type, filter_tags) || return [] of AssetRecord

      results = [] of AssetRecord
      @db.query("SELECT a.* FROM #{from} WHERE #{where} ORDER BY a.id", args: args) do |rs|
        rs.each { results << read_asset_record(rs) }
      end
      results
    end

    def asset_exists?(asset_type : String, pool_key : String) : Bool
      result = @db.scalar(
        "SELECT COUNT(*) FROM assets WHERE asset_type = ? AND pool_key = ?",
        asset_type, pool_key
      )
      result.as(Int64) > 0
    end

    # ── Registry ──

    TRAIT_NAME = /\A[a-z][a-z0-9_]*\z/
    TYPE_NAME  = /\A[a-z0-9]+(?:[_-][a-z0-9]+)*\z/
    LABEL      = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    # Declare how an asset type is keyed. From then on DataDungeon derives each
    # asset's pool_key from its `pool_traits` tags, so applications stop
    # building keys. List the traits most important first: the key is their
    # normalized values in that order (see TraitKey), so a lookup on leading
    # traits is a prefix match. `group_traits` names the leading traits that
    # make up the type's group, and `labels` suffixes for traits whose values
    # alone would read ambiguously in a key (`{"skin" => "skin"}` gives
    # `tan-skin`). Trait tags are stored normalized, as the key holds them.
    # With `pool: true` many interchangeable assets share a pool key;
    # otherwise storing under a pool key replaces the asset there.
    #
    # The registration is stored in the database. Registering a type again
    # with the same definition changes nothing; a different definition,
    # including a new order, re-derives the keys of its assets from their tags.
    def register_type(
      asset_type : String,
      *,
      pool_traits : Array(String),
      group_traits : Array(String) = [] of String,
      pool : Bool = false,
      labels : Hash(String, String) = {} of String => String,
    ) : AssetType
      definition = AssetType.new(asset_type, pool_traits, group_traits, pool, labels)
      validate_type(definition)
      changed = [] of Int64
      @object_lock.synchronize do
        unless stored_type(asset_type) == {definition, TraitKey::SCHEME}
          @db.transaction do |tx|
            conn = tx.connection
            conn.exec(
              <<-SQL,
              INSERT INTO asset_types
              (asset_type, pool_traits, group_traits, labels, pool, key_scheme)
              VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(asset_type) DO UPDATE SET pool_traits = excluded.pool_traits,
                group_traits = excluded.group_traits, labels = excluded.labels,
                pool = excluded.pool, key_scheme = excluded.key_scheme
            SQL
              asset_type, definition.pool_traits.to_json, definition.group_traits.to_json,
              definition.labels.to_json, pool ? 1 : 0, TraitKey::SCHEME
            )
            changed = rekey(conn, definition)
          end
        end
        @types[asset_type] = definition
      end
      changed.each { |id| @indexer.try(&.enqueue_asset(id)) }
      definition
    end

    # The registration of an asset type, or nil when it has none.
    def registration(asset_type : String) : AssetType?
      @types[asset_type]?
    end

    # The pool key a registered type gives these traits. Traits left out are
    # absent (an empty segment); names that aren't the type's traits raise.
    def pool_key_for(asset_type : String, traits : Hash(String, String)) : String
      type = registered(asset_type)
      type.key(query_traits(type, traits))
    end

    # The key prefix shared by assets whose first `size` traits (by default,
    # the group traits) equal these. Later traits are ignored.
    def group_key_for(asset_type : String, traits : Hash(String, String), size : Int32? = nil) : String
      type = registered(asset_type)
      type.prefix(query_traits(type, traits), leading_size(type, size))
    end

    # Trait values normalized as a registered type stores them (blank trait
    # values dropped); other tags, and any tags of an unregistered type, as given.
    def normalize_tags(asset_type : String, tags : Hash(String, String)) : Hash(String, String)
      (type = @types[asset_type]?) ? normalize_traits(type, tags) : tags
    end

    # Assets whose traits all equal these: a pool's members, or the one asset
    # of a single-best type. Traits named in `custom` may differ, leaving the
    # caller to rank them (e.g. semantically); every other trait matches
    # exactly, and a trait absent from `traits` must be absent on the asset.
    # Without `custom` this is one key lookup. With it, the traits before the
    # first custom one narrow the candidates by key prefix, and the rest are
    # checked against each candidate's tags, so it's fastest when the custom
    # traits come late in the type's order.
    def find_pool(
      asset_type : String,
      traits : Hash(String, String),
      custom : Array(String) = [] of String,
    ) : Array(AssetRecord)
      type = registered(asset_type)
      values = query_traits(type, traits)
      return find_pool(type.key(values)) if custom.empty?
      unless (unknown = custom - type.pool_traits).empty?
        raise ArgumentError.new("#{unknown.join(", ")} are not traits of #{asset_type}")
      end

      lead = custom.min_of { |trait| type.pool_traits.index!(trait) }
      clauses = [] of String
      args = [] of ::DB::Any
      key_prefix(clauses, args, type.prefix(values, lead))
      (type.pool_traits[lead..] - custom).each do |trait|
        if value = values[trait]?
          clauses << "EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = ? AND t.tag_value = ?)"
          args << trait << value
        else
          clauses << "NOT EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = ?)"
          args << trait
        end
      end
      query_assets(clauses.join(" AND "), args)
    end

    # Every asset with this key: a pool's members, or the one asset of a
    # single-best key. A registered type's key names its type, so the key
    # alone is enough.
    def find_pool(pool_key : String) : Array(AssetRecord)
      query_assets("a.pool_key = ?", [pool_key] of ::DB::Any)
    end

    # Every asset of an unregistered type with this explicitly given key.
    def find_pool(asset_type : String, pool_key : String) : Array(AssetRecord)
      query_assets("+a.asset_type = ? AND a.pool_key = ?", [asset_type, pool_key] of ::DB::Any)
    end

    # Every asset whose first `size` traits (by default, the group traits)
    # equal these: one key-prefix range lookup. Later traits are ignored.
    def find_group(asset_type : String, traits : Hash(String, String), size : Int32? = nil) : Array(AssetRecord)
      type = registered(asset_type)
      size = leading_size(type, size)
      values = query_traits(type, traits)
      return find_pool(type.key(values)) if size == type.pool_traits.size
      find_group(type.prefix(values, size))
    end

    # Every asset whose key starts with this prefix, which must end at a
    # separator (as group_key_for's do); `portrait.` is the whole type.
    def find_group(prefix : String) : Array(AssetRecord)
      unless prefix.ends_with?(TraitKey::SEPARATOR)
        raise ArgumentError.new("a key prefix must end with #{TraitKey::SEPARATOR.inspect}")
      end
      clauses = [] of String
      args = [] of ::DB::Any
      key_prefix(clauses, args, prefix)
      query_assets(clauses.join(" AND "), args)
    end

    # Both lookups at once: `pool` as find_pool (with `custom`), and `group`
    # the rest of the group, for ranking or as a fallback. A type without
    # group traits has an empty `group`.
    def find(
      asset_type : String,
      traits : Hash(String, String),
      custom : Array(String) = [] of String,
    ) : Matches
      pool = find_pool(asset_type, traits, custom)
      return Matches.new(pool, [] of AssetRecord) if registered(asset_type).group_traits.empty?
      in_pool = pool.map(&.id).to_set
      Matches.new(pool, find_group(asset_type, traits).reject { |rec| in_pool.includes?(rec.id) })
    end

    # A prefix as an index range: keys from `prefix` up to, not including,
    # the prefix with its final separator raised by one ('.' to '/').
    private def key_prefix(clauses : Array(String), args : Array(::DB::Any), prefix : String) : Nil
      clauses << "a.pool_key >= ? AND a.pool_key < ?"
      args << prefix << prefix.rchop + TraitKey::SEPARATOR.succ
    end

    private def leading_size(type : AssetType, size : Int32?) : Int32
      unless size
        raise ArgumentError.new("#{type.name} has no group traits") if type.group_traits.empty?
        return type.group_traits.size
      end
      unless 0 <= size <= type.pool_traits.size
        raise ArgumentError.new("#{type.name} has #{type.pool_traits.size} traits, not #{size}")
      end
      size
    end

    private def query_assets(where : String, args : Array(::DB::Any)) : Array(AssetRecord)
      results = [] of AssetRecord
      @db.query("SELECT a.* FROM assets a WHERE #{where} ORDER BY a.id", args: args) do |rs|
        rs.each { results << read_asset_record(rs) }
      end
      results
    end

    # How often each custom value of a trait occurs among assets of a type,
    # most frequent first: candidates for becoming standard choices.
    def custom_values(asset_type : String, trait : String) : Hash(String, Int32)
      counts = {} of String => Int32
      @db.query(<<-SQL, asset_type, trait) do |rs|
        SELECT tag_value, COUNT(*) FROM asset_tags
        WHERE asset_type = ? AND tag_key = ? AND custom = 1
        GROUP BY tag_value ORDER BY COUNT(*) DESC, tag_value
      SQL
        rs.each { counts[rs.read(String)] = rs.read(Int64).to_i32 }
      end
      counts
    end

    # The tags of an asset whose values are custom.
    def custom_traits(asset_id : Int64) : Array(String)
      @db.query_all(
        "SELECT tag_key FROM asset_tags WHERE asset_id = ? AND custom = 1 ORDER BY tag_key",
        asset_id, as: String
      )
    end

    # Treat a custom value as a standard choice from now on. Keys include
    # custom values like any other, so no key changes. Returns the number of
    # tags updated.
    def promote(asset_type : String, trait : String, value : String) : Int64
      if (type = @types[asset_type]?) && type.trait?(trait)
        value = TraitKey.normalize(value) || value
      end
      @db.exec(<<-SQL, asset_type, trait, value).rows_affected
        UPDATE asset_tags SET custom = 0
        WHERE asset_type = ? AND tag_key = ? AND tag_value = ? AND custom = 1
      SQL
    end

    private def registered(asset_type : String) : AssetType
      @types[asset_type]? || raise ArgumentError.new("#{asset_type} is not a registered asset type")
    end

    private def validate_type(type : AssetType) : Nil
      name = type.name
      unless name.matches?(TYPE_NAME)
        raise ArgumentError.new("asset type #{name.inspect} must be lowercase letters and digits, joined by '_' or '-'")
      end
      raise ArgumentError.new("#{name}: pool_traits must not be empty") if type.pool_traits.empty?
      (type.pool_traits + type.group_traits).each do |trait|
        unless trait.matches?(TRAIT_NAME)
          raise ArgumentError.new("#{name}: trait #{trait.inspect} must be lowercase letters, digits and underscores")
        end
      end
      if type.pool_traits.uniq.size != type.pool_traits.size || type.group_traits.uniq.size != type.group_traits.size
        raise ArgumentError.new("#{name}: a trait is listed twice")
      end
      unless type.pool_traits[0, type.group_traits.size] == type.group_traits
        raise ArgumentError.new("#{name}: group traits must be the first pool traits, in the same order")
      end
      type.labels.each do |trait, label|
        raise ArgumentError.new("#{name}: #{trait} is labelled but is not a pool trait") unless type.trait?(trait)
        unless label.matches?(LABEL)
          raise ArgumentError.new("#{name}: label #{label.inspect} must be lowercase words joined by '-'")
        end
      end
    end

    # Normalized lookup values; raises on names that aren't the type's traits.
    private def query_traits(type : AssetType, traits : Hash(String, String)) : Hash(String, String)
      unless (unknown = traits.keys - type.pool_traits).empty?
        raise ArgumentError.new("#{unknown.join(", ")} are not traits of #{type.name}")
      end
      normalize_traits(type, traits)
    end

    private def normalize_traits(type : AssetType, tags : Hash(String, String)) : Hash(String, String)
      normalized = {} of String => String
      tags.each do |key, value|
        if !type.trait?(key)
          normalized[key] = value
        elsif normal = TraitKey.normalize(value)
          normalized[key] = normal
        end
      end
      normalized
    end

    private def stored_type(asset_type : String) : {AssetType, Int32}?
      @db.query_one?(
        "SELECT asset_type, pool_traits, group_traits, labels, pool, key_scheme FROM asset_types WHERE asset_type = ?",
        asset_type
      ) { |rs| read_type(rs) }
    end

    private def read_type(rs) : {AssetType, Int32}
      name = rs.read(String)
      pool_traits = Array(String).from_json(rs.read(String))
      group_traits = Array(String).from_json(rs.read(String))
      labels = Hash(String, String).from_json(rs.read(String))
      pool = rs.read(Int32) != 0
      {AssetType.new(name, pool_traits, group_traits, pool, labels), rs.read(Int32)}
    end

    # Registrations made with an older key encoding are re-keyed on open.
    private def load_types : Nil
      rows = @db.query_all(
        "SELECT asset_type, pool_traits, group_traits, labels, pool, key_scheme FROM asset_types"
      ) { |rs| read_type(rs) }
      rows.each do |type, scheme|
        unless scheme == TraitKey::SCHEME
          @db.transaction do |tx|
            rekey(tx.connection, type)
            tx.connection.exec("UPDATE asset_types SET key_scheme = ? WHERE asset_type = ?", TraitKey::SCHEME, type.name)
          end
        end
        @types[type.name] = type
      end
    end

    # Re-derive both keys of every asset of a type from its tags, normalizing
    # the stored trait values on the way. In a single-best type, assets that
    # now share a pool key can't all keep it: the most recently used keeps it,
    # and the others keep their rows and tags but no pool key. Returns the
    # assets whose tags changed.
    private def rekey(conn, type : AssetType) : Array(Int64)
      ids = conn.query_all(
        "SELECT id FROM assets WHERE asset_type = ? ORDER BY last_used_at DESC, id DESC",
        type.name, as: Int64
      )
      conn.exec(
        "UPDATE assets SET pool_key = NULL, pool = ? WHERE asset_type = ?",
        type.pool ? 1 : 0, type.name
      )
      claimed = Set(String).new
      changed = [] of Int64
      ids.each_slice(500) do |batch|
        stored = tags_batch(conn, batch)
        batch.each do |id|
          tags = stored[id]? || {} of String => String
          normalized = normalize_traits(type, tags)
          tags.each do |key, value|
            next unless type.trait?(key)
            normal = normalized[key]?
            next if normal == value
            if normal
              conn.exec("UPDATE asset_tags SET tag_value = ? WHERE asset_id = ? AND tag_key = ?", normal, id, key)
            else
              conn.exec("DELETE FROM asset_tags WHERE asset_id = ? AND tag_key = ?", id, key)
            end
            changed << id unless changed.last? == id
          end
          pool_key = type.key(normalized)
          pool_key = nil unless type.pool || claimed.add?(pool_key)
          conn.exec("UPDATE assets SET pool_key = ? WHERE id = ?", pool_key, id)
        end
      end
      changed
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
      tags_batch(@db, asset_ids)
    end

    # `db` is the database or, inside a transaction, its connection.
    private def tags_batch(db, asset_ids : Array(Int64)) : Hash(Int64, Hash(String, String))
      result = {} of Int64 => Hash(String, String)
      return result if asset_ids.empty?

      placeholders = asset_ids.map { "?" }.join(", ")
      params = asset_ids.map(&.as(::DB::Any))
      db.query(
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

    # Public delete: removes the row *and*, once no other row shares it, the
    # backing object. DataDungeon owns the write path, so it owns the unlink
    # too — callers must not reach around to File.delete the blob (that breaks
    # for non-local backends and for objects other assets still use). The
    # object key is read before the row is removed; Storage#delete is a no-op
    # if the object is already gone.
    def delete_asset(id : Int64) : Nil
      @object_lock.synchronize do
        path = @db.query_one?(
          "SELECT file_path FROM assets WHERE id = ? LIMIT 1", id
        ) { |rs| rs.read(String) }
        delete_asset_row(id)
        release_object(path) if path
      end
    end

    # Row-only delete (sidecars fall via ON DELETE CASCADE). Used by
    # delete_asset, which then releases the object, and by vacuum for rows
    # whose object is already gone.
    private def delete_asset_row(id : Int64) : Nil
      @indexer.try(&.delete_asset(id))
      @db.exec("DELETE FROM assets WHERE id = ?", id)
    end

    # ── Consistency sweep (fsck / vacuum) ──

    # Report-only reconciliation of the index against the storage backend.
    # Walks both directions of divergence: rows whose object is missing, and
    # stored objects with no owning row (leaked blobs — e.g. from deletes made
    # before v0.3.4, when delete_asset didn't unlink). Changes nothing.
    def check_consistency : ConsistencyReport
      store = @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"

      indexed = Set(String).new
      missing_ids = [] of Int64
      # Collect first; don't issue nested queries while this cursor is open.
      @db.query("SELECT id, file_path FROM assets") do |rs|
        rs.each do
          id = rs.read(Int64)
          path = rs.read(String)
          indexed << path
          missing_ids << id unless store.exists?(path)
        end
      end

      missing = missing_ids.compact_map { |id| find_asset_by_id(id) }
      orphans = store.list_keys.reject { |key| indexed.includes?(key) }
      ConsistencyReport.new(missing, orphans)
    end

    # Reconcile the index and the backend. Off by default (behaves like
    # check_consistency); pass the flags to actually delete. Returns the report
    # of what was found — and, per the flags, acted on.
    #
    # - delete_missing_rows: drop rows whose backing object is gone.
    # - delete_orphan_objects: unlink stored objects with no owning row.
    def vacuum(
      delete_missing_rows : Bool = false,
      delete_orphan_objects : Bool = false,
    ) : ConsistencyReport
      @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"
      report = check_consistency

      if delete_missing_rows
        # Object already confirmed gone — drop the row only (no unlink needed).
        report.missing_objects.each { |rec| delete_asset_row(rec.id) }
      end

      if delete_orphan_objects
        # Re-check each under the lock: a concurrent store may have just
        # indexed a row for an object the sweep saw as unowned.
        @object_lock.synchronize do
          report.orphan_objects.each { |key| release_object(key) }
        end
      end

      report
    end

    # ── Pool helpers ──

    def count_pool_assets(asset_type : String, filter_tags : Hash(String, String)) : Int32
      filter_tags = normalize_tags(asset_type, filter_tags)
      return @db.scalar("SELECT COUNT(*) FROM assets WHERE asset_type = ?", asset_type).as(Int64).to_i32 if filter_tags.empty?
      from, where, args = tag_filter(asset_type, filter_tags) || return 0

      @db.scalar("SELECT COUNT(*) FROM #{from} WHERE #{where}", args: args).as(Int64).to_i32
    end

    def random_pool_text(asset_type : String, filter_tags : Hash(String, String)) : String?
      filter_tags = normalize_tags(asset_type, filter_tags)
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
      from, where, args = tag_filter(asset_type, filter_tags) || return nil

      @db.query_one?(
        "SELECT tm.content FROM #{from} JOIN text_meta tm ON tm.asset_id = a.id WHERE #{where} ORDER BY RANDOM() LIMIT 1",
        args: args
      ) { |rs| rs.read(String) }
    end

    # How many index entries to count per filter tag when choosing the rarest
    # one to start from; beyond this a tag is simply common.
    RAREST_PROBE = 1000

    # FROM and WHERE (alias `a`) for "assets of this type carrying every one
    # of these normalized tags", or nil when some tag matches nothing. Rather
    # than collect every tag row matching any of the tags, it starts from the
    # narrowest index range it can find and checks each remaining tag on each
    # candidate by primary key:
    #
    # - a registered type whose leading traits are all in the filter starts
    #   from its pool-key prefix, unless some of its assets have no key;
    # - otherwise it starts from the tag with the fewest matches.
    private def tag_filter(asset_type : String, filter : Hash(String, String)) : {String, String, Array(::DB::Any)}?
      clauses = [] of String
      args = [] of ::DB::Any
      checks = filter
      id = "a.id"

      if leading = key_prefix_for_filter(asset_type, filter)
        key, covered = leading
        from = "assets a" # the key names the type
        if key.ends_with?(TraitKey::SEPARATOR)
          key_prefix(clauses, args, key)
        else # every trait given: the whole key
          clauses << "a.pool_key = ?"
          args << key
        end
        checks = filter.reject(covered) # the key already matches these
      else
        counts = tag_counts(asset_type, filter, RAREST_PROBE)
        # Every tag is common: count them fully to find the rarest.
        counts = tag_counts(asset_type, filter, nil) if counts.all? { |count| count[2] == RAREST_PROBE }
        anchor_key, anchor_value, count = counts.min_by(&.[2])
        return nil if count == 0
        # CROSS JOIN keeps SQLite from reordering: the anchor tag's range drives.
        from = "asset_tags x CROSS JOIN assets a"
        clauses << "x.asset_type = ? AND x.tag_key = ? AND x.tag_value = ? AND a.id = x.asset_id"
        args << asset_type << anchor_key << anchor_value
        checks = filter.reject(anchor_key)
        id = "x.asset_id" # checked from the tag row, before reading the asset
      end

      checks.each do |key, value|
        clauses << "EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = #{id} AND t.tag_key = ? AND t.tag_value = ?)"
        args << key << value
      end
      {from, clauses.join(" AND "), args}
    end

    # Each tag's number of matches among the type's assets, counted up to `cap`.
    private def tag_counts(asset_type : String, filter : Hash(String, String), cap : Int32?) : Array({String, String, Int64})
      filter.map do |key, value|
        count = if cap
                  @db.scalar(
                    "SELECT COUNT(*) FROM (SELECT 1 FROM asset_tags WHERE asset_type = ? AND tag_key = ? AND tag_value = ? LIMIT ?)",
                    asset_type, key, value, cap
                  ).as(Int64)
                else
                  @db.scalar(
                    "SELECT COUNT(*) FROM asset_tags WHERE asset_type = ? AND tag_key = ? AND tag_value = ?",
                    asset_type, key, value
                  ).as(Int64)
                end
        {key, value, count}
      end
    end

    # The pool-key prefix covering a filter's leading traits (the whole key
    # when it gives them all), and those traits, when the type is registered,
    # the filter includes at least its first trait, and every one of its
    # assets has a key (a key-less asset would be missed by a range).
    private def key_prefix_for_filter(asset_type : String, filter : Hash(String, String)) : {String, Array(String)}?
      type = @types[asset_type]? || return nil
      lead = type.pool_traits.take_while { |trait| filter.has_key?(trait) }.size
      return nil if lead == 0
      return nil if @db.query_one?(
                      "SELECT 1 FROM assets WHERE asset_type = ? AND pool_key IS NULL LIMIT 1",
                      asset_type, as: Int64
                    )
      key = lead == type.pool_traits.size ? type.key(filter) : type.prefix(filter, lead)
      {key, type.pool_traits[0, lead]}
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
        pool_key: rs.read(String?),
        file_hash: rs.read(String?),
        created_at: rs.read(String),
        last_used_at: rs.read(String?),
        use_count: (rs.read(Int32?) || 0),
        permanent: (rs.read(Int32?) || 0) != 0,
        pool: (rs.read(Int32?) || 0) != 0,
        generator: rs.read(String?),
        generation: rs.read(String?),
        description: rs.read(String?),
        generated: (rs.read(Int32?) || 0) != 0,
        rating: rs.read(Int32?),
        flagged: (rs.read(Int32?) || 0) != 0,
      )
    end
  end
end
