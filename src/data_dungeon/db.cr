require "sqlite3"
require "digest/sha256"
require "json"

module DataDungeon
  # Raised by a write to a DB opened with `read_only: true`, and by a
  # read-only open of a database that needs upgrading first.
  class ReadOnlyError < Exception
  end

  # Raised by `store` for a file its type already holds: an asset is its
  # bytes, so change its traits with `update_asset`, or bring a retired one
  # back with `reinstate`.
  class AlreadyStored < Exception
    getter asset_id : Int64
    getter? retired : Bool

    def initialize(@asset_id : Int64, @retired : Bool)
      super("Already stored as asset #{@asset_id}#{" (retired)" if @retired}: " \
            "change its traits with update_asset#{", or bring it back with reinstate" if @retired}")
    end
  end

  class DB
    TIME_FORMAT = "%F %T"
    # How long a write waits for another connection's write lock.
    BUSY_TIMEOUT_MS = 5000
    # Uses counted in memory are written once there are this many
    # (touch_asset).
    USAGE_WRITE_AT = 100

    @db : ::DB::Database
    @indexer : AssetIndexer? = nil
    getter storage : Storage?
    # Objects are content addressed, so several rows may share one. Writing an
    # object and indexing its row, or dropping a row and unlinking its object
    # once unreferenced, happen under this lock so neither interleaves with the
    # other inside this process.
    @object_lock = Mutex.new(:reentrant)
    # Uses counted since they were last written: asset id => {uses, last
    # use}. See touch_asset.
    @usage = {} of Int64 => {Int32, Time}
    @usage_lock = Mutex.new
    @usage_count = 0
    @usage_try_at = USAGE_WRITE_AT
    # Registered asset types, loaded from asset_types when the DB opens.
    @types = {} of String => AssetType
    getter? read_only = false
    # The database file.
    getter path : String
    # Who is using the store (`"cattacula"`), which says whose indexes
    # `register_index` creates and changes.
    getter consumer : String?

    # Shared connection for extensions that keep their tables in the asset DB.
    def connection : ::DB::Database
      @db
    end

    def attach_indexer(indexer : AssetIndexer) : Nil
      raise "an asset indexer is already attached" if @indexer
      @indexer = indexer
    end

    # With `read_only: true` the database is only read: nothing is created,
    # upgraded or re-keyed, every connection refuses writes (PRAGMA
    # query_only), and the methods that write raise ReadOnlyError. A database
    # an older DataDungeon wrote must be opened read-write once first.
    # `consumer` names the application, for its own indexes (register_index).
    def initialize(@path : String, storage : Storage? = nil, cache_root : String? = nil, *, read_only : Bool = false,
                   @consumer : String? = nil)
      if (name = @consumer) && !name.matches?(LABEL)
        raise ArgumentError.new("consumer #{name.inspect} must be lowercase words joined by '-'")
      end
      @read_only = read_only
      if read_only
        raise ReadOnlyError.new("No database at #{path}") unless File.file?(path)
      else
        dir = File.dirname(path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)
      end
      # Pragmas in the URI apply to every pooled connection: deletes cascade to
      # tags and sidecars whichever connection runs them, and a write that
      # meets another connection's open transaction waits for it (up to 5 s)
      # rather than failing at once with "database is locked".
      @db = ::DB.open("sqlite3://#{path}?foreign_keys=on&busy_timeout=#{BUSY_TIMEOUT_MS}")
      @storage = storage || (cache_root ? LocalStorage.new(cache_root) : nil)
      if read_only
        @db.setup_connection { |conn| conn.exec("PRAGMA query_only = ON"); nil }
        begin
          check_schema
          load_types
        rescue ex
          @db.close
          raise ex
        end
      else
        setup_schema
        DB.opened(self)
      end
    end

    # Writes the uses not yet written (touch_asset), then closes.
    def close : Nil
      @indexer.try(&.close)
      begin
        flush_usage
      rescue
        # closing matters more than a usage count
      end
      DB.closed(self)
      @db.close
    end

    # Read-write DBs not yet closed, whose uses are written when the process
    # exits (`exit`, the end of the program, or a server's shutdown: Kemal
    # calls `exit` on SIGINT and SIGTERM). A process killed outright loses them.
    @@open = [] of DB
    @@open_lock = Mutex.new
    @@at_exit = false

    protected def self.opened(db : DB) : Nil
      @@open_lock.synchronize do
        @@open << db
        unless @@at_exit
          @@at_exit = true
          at_exit { flush_open_usage }
        end
      end
    end

    protected def self.closed(db : DB) : Nil
      @@open_lock.synchronize { @@open.delete(db) }
    end

    # Writes the uses waiting in every open DB, as at exit. :nodoc:
    def self.flush_open_usage : Nil
      @@open_lock.synchronize { @@open.dup }.each do |db|
        db.flush_usage
      rescue
        # a usage count isn't worth failing an exit over
      end
    end

    # ── Schema ──

    ASSETS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS assets (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_type    TEXT NOT NULL,
        media         TEXT NOT NULL,
        content_type  TEXT NOT NULL,
        file_path     TEXT NOT NULL,
        file_hash     TEXT,
        created_at    TEXT NOT NULL,
        last_used_at  TEXT,
        use_count     INTEGER DEFAULT 0,
        permanent     INTEGER DEFAULT 0,
        generator     TEXT,
        description_id INTEGER REFERENCES texts(id),
        generated     INTEGER NOT NULL DEFAULT 0,
        rating        INTEGER,
        flagged       INTEGER DEFAULT 0,
        made_at       TEXT,
        retired_at    TEXT
      )
    SQL

    # An asset's keys are in asset_keys, its type's own index among them.
    ASSETS_INDEXES = <<-SQL
      CREATE INDEX IF NOT EXISTS idx_assets_type
        ON assets(asset_type);
      CREATE INDEX IF NOT EXISTS idx_assets_retired
        ON assets(asset_type, id) WHERE retired_at IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_assets_file_path
        ON assets(file_path);
      CREATE INDEX IF NOT EXISTS idx_assets_file_hash
        ON assets(file_hash);
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

    # Tag filters across all types.
    ASSET_TAGS_KV_INDEX = <<-SQL
      CREATE INDEX IF NOT EXISTS idx_tags_key_value
        ON asset_tags(tag_key, tag_value)
    SQL

    # One row per registered asset type. Trait lists are JSON arrays in
    # registration order, labels and facets JSON objects, sets a JSON array;
    # key_scheme records the TraitKey format the stored keys were made with.
    # Relations from an asset to another asset (`derived-from`, `supersedes`)
    # or to a name (`used-by` "boardwalk"). Exactly one target is set; links
    # go when either asset is deleted.
    ASSET_LINKS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_links (
        from_id    INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        rel        TEXT NOT NULL,
        to_id      INTEGER REFERENCES assets(id) ON DELETE CASCADE,
        to_name    TEXT,
        created_at TEXT NOT NULL,
        data       TEXT,
        CHECK ((to_id IS NULL) <> (to_name IS NULL))
      )
    SQL

    # Each way round: an asset's links (and linking twice changing nothing),
    # what links to an asset, and the assets linked to a name.
    ASSET_LINKS_INDEXES = <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_links_from
        ON asset_links(from_id, rel, ifnull(to_id, 0), ifnull(to_name, ''));
      CREATE INDEX IF NOT EXISTS idx_links_to_asset
        ON asset_links(to_id, rel);
      CREATE INDEX IF NOT EXISTS idx_links_to_name
        ON asset_links(rel, to_name, from_id)
    SQL

    # How many assets of a type carry each tag value, current and retired,
    # and (under the empty tag) how many assets the type has: for browsing
    # counts, and for planning a lookup by tags. Triggers keep them, so
    # every write keeps them right. An empty tag name is refused for that.
    ASSET_TAG_COUNTS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_tag_counts (
        asset_type TEXT NOT NULL,
        tag_key    TEXT NOT NULL,
        tag_value  TEXT NOT NULL,
        current    INTEGER NOT NULL DEFAULT 0,
        retired    INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (asset_type, tag_key, tag_value)
      ) WITHOUT ROWID
    SQL

    # The counts as the tables have them, for checking the triggers kept them.
    COUNT_TAGS = [<<-SQL, <<-SQL, <<-SQL]
      INSERT INTO asset_tag_counts (asset_type, tag_key, tag_value, current, retired)
      SELECT t.asset_type, t.tag_key, t.tag_value, SUM(a.retired_at IS NULL), SUM(a.retired_at IS NOT NULL)
      FROM asset_tags t JOIN assets a ON a.id = t.asset_id
      GROUP BY t.asset_type, t.tag_key, t.tag_value
    SQL
      INSERT INTO asset_tag_counts (asset_type, tag_key, tag_value, current, retired)
      SELECT asset_type, '', '', SUM(retired_at IS NULL), SUM(retired_at IS NOT NULL)
      FROM assets GROUP BY asset_type
    SQL
      INSERT INTO asset_tag_counts (asset_type, tag_key, tag_value, current, retired)
      SELECT asset_type, '@view', word, SUM(retired_at IS NULL), SUM(retired_at IS NOT NULL) FROM (
        SELECT a.asset_type, a.retired_at, CASE WHEN instr(im.view_name, ' ') > 0
          THEN substr(im.view_name, 1, instr(im.view_name, ' ') - 1) ELSE im.view_name END AS word
        FROM image_meta im JOIN assets a ON a.id = im.asset_id WHERE im.view_name IS NOT NULL
        UNION ALL
        SELECT a.asset_type, a.retired_at, substr(im.view_name, instr(im.view_name, ' ') + 1)
        FROM image_meta im JOIN assets a ON a.id = im.asset_id WHERE instr(im.view_name, ' ') > 0
      ) GROUP BY asset_type, word
    SQL

    # The words of a view's name (`back-left from-above`), one or two, as a
    # subquery giving `word`; none for no name.
    private def self.view_words(name : String) : String
      "SELECT word FROM (SELECT CASE WHEN instr(#{name}, ' ') > 0 THEN substr(#{name}, 1, instr(#{name}, ' ') - 1) " \
      "ELSE #{name} END AS word UNION ALL SELECT substr(#{name}, instr(#{name}, ' ') + 1) WHERE instr(#{name}, ' ') > 0) " \
      "WHERE word IS NOT NULL"
    end

    # Trigger SQL adding a view's words to its type's `@view` counts, or with
    # `taking` taking them away.
    private def self.view_count_sql(name : String, type : String, current : String, retired : String,
                                    taking = false) : String
      words = view_words(name)
      return "INSERT INTO asset_tag_counts (asset_type, tag_key, tag_value, current, retired) " \
             "SELECT #{type}, '@view', word, #{current}, #{retired} FROM (#{words}) WHERE #{type} IS NOT NULL " \
             "ON CONFLICT DO UPDATE SET current = current + excluded.current, retired = retired + excluded.retired;" unless taking
      "UPDATE asset_tag_counts SET current = current - (#{current}), retired = retired - (#{retired}) " \
      "WHERE asset_type = #{type} AND tag_key = '@view' AND tag_value IN (#{words}); " \
      "DELETE FROM asset_tag_counts WHERE asset_type = #{type} AND tag_key = '@view' AND current = 0 AND retired = 0;"
    end

    # Trigger SQL adding `current` and `retired` (each 1 or 0) to a count,
    # or with `taking` taking them away and dropping the count at 0.
    private def self.count_sql(type : String, key : String, value : String, current : String, retired : String,
                               taking = false) : String
      return "INSERT INTO asset_tag_counts (asset_type, tag_key, tag_value, current, retired) " \
             "VALUES (#{type}, #{key}, #{value}, #{current}, #{retired}) " \
             "ON CONFLICT DO UPDATE SET current = current + excluded.current, retired = retired + excluded.retired;" unless taking
      "UPDATE asset_tag_counts SET current = current - (#{current}), retired = retired - (#{retired}) " \
      "WHERE asset_type = #{type} AND tag_key = #{key} AND tag_value = #{value}; " \
      "DELETE FROM asset_tag_counts WHERE asset_type = #{type} AND tag_key = #{key} " \
      "AND tag_value = #{value} AND current = 0 AND retired = 0;"
    end

    # A tag counts as its asset does, current or retired. An asset's tags go
    # before the asset itself, while it still says which they counted as.
    # A picture's view counts too, under the tag `@view`, once for each word
    # of its name (`back-left`, `from-above`). setup_schema recreates the
    # triggers on every read-write open, so a database has these ones.
    TAG_COUNT_TRIGGERS = [
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS asset_tags_counted AFTER INSERT ON asset_tags BEGIN
          #{count_sql("new.asset_type", "new.tag_key", "new.tag_value",
              "ifnull((SELECT retired_at IS NULL FROM assets WHERE id = new.asset_id), 1)",
              "ifnull((SELECT retired_at IS NOT NULL FROM assets WHERE id = new.asset_id), 0)")}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS asset_tags_uncounted AFTER DELETE ON asset_tags BEGIN
          #{count_sql("old.asset_type", "old.tag_key", "old.tag_value",
              "ifnull((SELECT retired_at IS NULL FROM assets WHERE id = old.asset_id), 1)",
              "ifnull((SELECT retired_at IS NOT NULL FROM assets WHERE id = old.asset_id), 0)", taking: true)}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS asset_tags_recounted AFTER UPDATE OF asset_type, tag_key, tag_value ON asset_tags BEGIN
          #{count_sql("old.asset_type", "old.tag_key", "old.tag_value",
              "ifnull((SELECT retired_at IS NULL FROM assets WHERE id = old.asset_id), 1)",
              "ifnull((SELECT retired_at IS NOT NULL FROM assets WHERE id = old.asset_id), 0)", taking: true)}
          #{count_sql("new.asset_type", "new.tag_key", "new.tag_value",
              "ifnull((SELECT retired_at IS NULL FROM assets WHERE id = new.asset_id), 1)",
              "ifnull((SELECT retired_at IS NOT NULL FROM assets WHERE id = new.asset_id), 0)")}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS assets_counted AFTER INSERT ON assets BEGIN
          #{count_sql("new.asset_type", "''", "''", "new.retired_at IS NULL", "new.retired_at IS NOT NULL")}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS assets_uncounted BEFORE DELETE ON assets BEGIN
          DELETE FROM asset_tags WHERE asset_id = old.id;
          DELETE FROM image_meta WHERE asset_id = old.id;
          #{count_sql("old.asset_type", "''", "''", "old.retired_at IS NULL", "old.retired_at IS NOT NULL", taking: true)}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS assets_type_recounted AFTER UPDATE OF asset_type ON assets
        WHEN old.asset_type <> new.asset_type BEGIN
          #{count_sql("old.asset_type", "''", "''", "old.retired_at IS NULL", "old.retired_at IS NOT NULL", taking: true)}
          #{count_sql("new.asset_type", "''", "''", "new.retired_at IS NULL", "new.retired_at IS NOT NULL")}
          #{view_count_sql("(SELECT view_name FROM image_meta WHERE asset_id = new.id)", "old.asset_type",
              "old.retired_at IS NULL", "old.retired_at IS NOT NULL", taking: true)}
          #{view_count_sql("(SELECT view_name FROM image_meta WHERE asset_id = new.id)", "new.asset_type",
              "new.retired_at IS NULL", "new.retired_at IS NOT NULL")}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS assets_retired_recounted AFTER UPDATE OF retired_at ON assets
        WHEN (old.retired_at IS NULL) <> (new.retired_at IS NULL) BEGIN
          UPDATE asset_tag_counts
          SET current = current + iif(new.retired_at IS NULL, 1, -1),
              retired = retired - iif(new.retired_at IS NULL, 1, -1)
          FROM (SELECT asset_type, tag_key, tag_value FROM asset_tags WHERE asset_id = new.id
                UNION ALL SELECT new.asset_type, '', ''
                UNION ALL SELECT new.asset_type, '@view', word
                  FROM (#{view_words("(SELECT view_name FROM image_meta WHERE asset_id = new.id)")})) AS t
          WHERE asset_tag_counts.asset_type = t.asset_type AND asset_tag_counts.tag_key = t.tag_key
            AND asset_tag_counts.tag_value = t.tag_value;
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS image_view_counted AFTER INSERT ON image_meta
        WHEN new.view_name IS NOT NULL BEGIN
          #{view_count_sql("new.view_name", "(SELECT asset_type FROM assets WHERE id = new.asset_id)",
              "(SELECT retired_at IS NULL FROM assets WHERE id = new.asset_id)",
              "(SELECT retired_at IS NOT NULL FROM assets WHERE id = new.asset_id)")}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS image_view_recounted AFTER UPDATE OF view_name ON image_meta
        WHEN old.view_name IS NOT new.view_name BEGIN
          #{view_count_sql("old.view_name", "(SELECT asset_type FROM assets WHERE id = old.asset_id)",
              "(SELECT retired_at IS NULL FROM assets WHERE id = old.asset_id)",
              "(SELECT retired_at IS NOT NULL FROM assets WHERE id = old.asset_id)", taking: true)}
          #{view_count_sql("new.view_name", "(SELECT asset_type FROM assets WHERE id = new.asset_id)",
              "(SELECT retired_at IS NULL FROM assets WHERE id = new.asset_id)",
              "(SELECT retired_at IS NOT NULL FROM assets WHERE id = new.asset_id)")}
        END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS image_view_uncounted AFTER DELETE ON image_meta
        WHEN old.view_name IS NOT NULL BEGIN
          #{view_count_sql("old.view_name", "(SELECT asset_type FROM assets WHERE id = old.asset_id)",
              "(SELECT retired_at IS NULL FROM assets WHERE id = old.asset_id)",
              "(SELECT retired_at IS NOT NULL FROM assets WHERE id = old.asset_id)", taking: true)}
        END
      SQL
    ]

    # The triggers' names, for recreating them.
    TAG_COUNT_TRIGGER_NAMES = TAG_COUNT_TRIGGERS.map { |sql| sql[/TRIGGER IF NOT EXISTS (\w+)/, 1] }

    # The indexes kept on types, and each asset's key in every index of its
    # type, so a lookup by an index's leading traits is one range scan. A
    # type's own index (the order it was registered with) has the empty
    # consumer and name; the rest are consumers' (register_index), each its
    # consumer's own: the consumer is part of its name.
    ASSET_INDEXES_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_indexes (
        id         INTEGER PRIMARY KEY,
        asset_type TEXT NOT NULL,
        consumer   TEXT NOT NULL,
        name       TEXT NOT NULL,
        traits     TEXT NOT NULL,
        UNIQUE (asset_type, consumer, name)
      )
    SQL

    ASSET_KEYS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_keys (
        asset_id INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        index_id INTEGER NOT NULL REFERENCES asset_indexes(id) ON DELETE CASCADE,
        key      TEXT NOT NULL,
        PRIMARY KEY (asset_id, index_id)
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS idx_asset_keys_key
        ON asset_keys(index_id, key)
    SQL

    # An assets row (alias `a`) as read_asset_record reads it, with its key
    # in its type's own index.
    ASSET_COLUMNS = <<-SQL
      a.id, a.asset_type, a.media, a.content_type, a.file_path,
      (SELECT k.key FROM asset_indexes i JOIN asset_keys k ON k.index_id = i.id AND k.asset_id = a.id
       WHERE i.asset_type = a.asset_type AND i.consumer = '' AND i.name = '') AS key,
      a.file_hash, a.created_at, a.last_used_at, a.use_count, a.permanent, a.generator,
      (SELECT generation FROM recipe_legacy WHERE asset_id = a.id) AS generation,
      (SELECT text FROM texts WHERE id = a.description_id) AS description,
      (SELECT hash FROM texts WHERE id = a.description_id) AS description_hash,
      a.generated, a.rating, a.flagged, a.made_at, a.retired_at,
      EXISTS (SELECT 1 FROM recipes WHERE asset_id = a.id) AS has_recipe
    SQL

    # The id of a type's own index, for a query taking the type as an argument.
    OWN_INDEX = "(SELECT id FROM asset_indexes WHERE asset_type = ? AND consumer = '' AND name = '')"

    # Each asset's type and tag values as words, for `list_assets(q:)`:
    # lowercase, with dashes and underscores inside a word (`red-hair`) and a
    # word's parts listed too, so `house` finds `west-of-house`. Diacritics
    # are kept, so the index and a walk through the words match alike.
    ASSET_SEARCH_SCHEMA = <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS asset_search
        USING fts5(words, tokenize = "unicode61 tokenchars '-_' remove_diacritics 0")
    SQL

    # How many assets have each word, kept with the index so a search can
    # tell a common word from a rare one without reading its matches. The
    # empty word counts every indexed asset.
    ASSET_SEARCH_TERMS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_search_terms (
        term TEXT PRIMARY KEY,
        docs INTEGER NOT NULL
      ) WITHOUT ROWID
    SQL

    ASSET_TYPES_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_types (
        asset_type   TEXT PRIMARY KEY,
        pool_traits  TEXT NOT NULL,
        group_traits TEXT NOT NULL,
        labels       TEXT NOT NULL DEFAULT '{}',
        sets         TEXT NOT NULL DEFAULT '[]',
        facets       TEXT NOT NULL DEFAULT '{}',
        key_scheme   INTEGER NOT NULL,
        scales       TEXT NOT NULL DEFAULT '{}',
        colors       TEXT NOT NULL DEFAULT '[]',
        weights      TEXT NOT NULL DEFAULT '{}',
        cycles       TEXT NOT NULL DEFAULT '{}',
        match_fields TEXT NOT NULL DEFAULT '[]'
      )
    SQL

    # Every change to an asset's tags or type, and every deletion, in order:
    # what a MatchIndex in another process catches up from. Only the latest
    # CHANGES_KEPT are kept; an index further behind rebuilds.
    ASSET_CHANGES_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_changes (
        seq      INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id INTEGER NOT NULL
      )
    SQL

    CHANGES_KEPT = 100_000

    # Image fields (see ImageMeta): what DataDungeon measures from the bytes,
    # with `measured` once it has read them, and what the application sets.
    # For an animation they describe its first frame.
    IMAGE_META_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS image_meta (
        asset_id       INTEGER PRIMARY KEY,
        width          INTEGER,
        height         INTEGER,
        usage_class    TEXT,
        compression    TEXT DEFAULT 'original',
        quality_floor  INTEGER,
        max_colors     INTEGER,
        target_format  TEXT,
        presentation   TEXT,
        transparent    INTEGER,
        dominant_color INTEGER,
        content_x      INTEGER,
        content_y      INTEGER,
        content_w      INTEGER,
        content_h      INTEGER,
        measured       INTEGER,
        view_x         REAL,
        view_y         REAL,
        view_z         REAL,
        view_roll      REAL,
        light_x        REAL,
        light_y        REAL,
        light_z        REAL,
        anchor_x       REAL,
        anchor_y       REAL,
        world_width    REAL,
        world_height   REAL,
        world_depth    REAL,
        view_name      TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
      )
    SQL

    # The image_meta columns in table order, after asset_id, with their types.
    # (`view_name`, last, is the view's Direction#name, kept by DataDungeon
    # so its words can be counted: see view_counts.)
    IMAGE_COLUMNS = {
      "width" => "INTEGER", "height" => "INTEGER", "usage_class" => "TEXT", "compression" => "TEXT",
      "quality_floor" => "INTEGER", "max_colors" => "INTEGER", "target_format" => "TEXT", "presentation" => "TEXT",
      "transparent" => "INTEGER", "dominant_color" => "INTEGER", "content_x" => "INTEGER", "content_y" => "INTEGER",
      "content_w" => "INTEGER", "content_h" => "INTEGER", "measured" => "INTEGER",
      "view_x" => "REAL", "view_y" => "REAL", "view_z" => "REAL", "view_roll" => "REAL",
      "light_x" => "REAL", "light_y" => "REAL", "light_z" => "REAL", "anchor_x" => "REAL", "anchor_y" => "REAL",
      "world_width" => "REAL", "world_height" => "REAL", "world_depth" => "REAL",
    }

    # Nearly every image has these, and filters ask for ranges of them.
    IMAGE_INDEXED = %w[width height content_w content_h view_x view_y view_z light_x light_y light_z
      anchor_x anchor_y world_width world_height world_depth]

    # An animated picture's frames (ImageAnimation); a still one has no row.
    IMAGE_ANIMATION_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS image_animation (
        asset_id    INTEGER PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
        frame_count INTEGER,
        duration_ms INTEGER,
        loop_count  INTEGER,
        frame_w     INTEGER,
        frame_h     INTEGER,
        columns     INTEGER
      )
    SQL

    ANIMATION_COLUMNS = %w[frame_count duration_ms loop_count frame_w frame_h columns]

    # An animation's checkpoints after its first frame (ImageKeyframe): only
    # the fields that change.
    IMAGE_KEYFRAMES_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS image_keyframes (
        asset_id  INTEGER NOT NULL REFERENCES image_animation(asset_id) ON DELETE CASCADE,
        at_ms     INTEGER NOT NULL,
        held      INTEGER NOT NULL DEFAULT 0,
        view_x    REAL,
        view_y    REAL,
        view_z    REAL,
        view_roll REAL,
        light_x   REAL,
        light_y   REAL,
        light_z   REAL,
        anchor_x  REAL,
        anchor_y  REAL,
        content_x INTEGER,
        content_y INTEGER,
        content_w INTEGER,
        content_h INTEGER,
        PRIMARY KEY (asset_id, at_ms)
      ) WITHOUT ROWID
    SQL

    # The fields an animation's checkpoints can change.
    KEYFRAME_FIELDS = %w[view_x view_y view_z view_roll light_x light_y light_z anchor_x anchor_y
      content_x content_y content_w content_h]

    # The image fields, then the animation's, as read_image_meta_join reads them.
    IMAGE_SELECT = (["im.asset_id"] + IMAGE_COLUMNS.keys.map { |column| "im.#{column}" } +
                    ["ia.asset_id"] + ANIMATION_COLUMNS.map { |column| "ia.#{column}" }).join(", ")

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

      # Schema changes run on one connection in one write transaction, so
      # processes opening the database together take turns, each seeing the
      # schema the previous one left. foreign_keys is off meanwhile because
      # rebuilding the assets table would otherwise cascade-delete every tag
      # and sidecar row; the pragma only changes outside a transaction.
      rebuilt = false
      @db.using_connection do |conn|
        conn.exec("PRAGMA foreign_keys=OFF")
        begin
          immediate(conn) do
            raise BEFORE_012 if before_012?(conn)
            conn.exec(ASSETS_SCHEMA)
            conn.exec(TEXTS_SCHEMA)
            RECIPE_SCHEMAS.split(";").each { |sql| conn.exec(sql.strip) unless sql.strip.empty? }
            migrate_recipes(conn)
            rebuilt = migrate_prompts(conn) || rebuilt
            rebuilt = migrate_wordings(conn) || rebuilt # 0.14's purposes
            conn.exec("DROP TABLE IF EXISTS recipe_fields") # 0.13's prompt fields, kept read-only by 0.14
            WORDING_TRIGGERS.each { |sql| conn.exec(sql) }
            seed_vocabulary(conn)
            ASSETS_INDEXES.split(";").each { |sql| conn.exec(sql.strip) unless sql.strip.empty? }
            conn.exec(ASSET_TAGS_SCHEMA)
            conn.exec(ASSET_TAGS_INDEX)
            conn.exec(ASSET_TYPES_SCHEMA)
            conn.exec(ASSET_CHANGES_SCHEMA)
            conn.exec(IMAGE_META_SCHEMA)
            conn.exec(IMAGE_ANIMATION_SCHEMA)
            conn.exec(IMAGE_KEYFRAMES_SCHEMA)
            image_indexes(conn)
            conn.exec(AUDIO_META_SCHEMA)
            conn.exec(VIDEO_META_SCHEMA)
            conn.exec(TEXT_META_SCHEMA)
            conn.exec(ASSET_TRACKS_SCHEMA)
            conn.exec(ASSET_TAGS_KV_INDEX)
            conn.exec(ASSET_LINKS_SCHEMA)
            ASSET_LINKS_INDEXES.split(";").each { |sql| conn.exec(sql.strip) unless sql.strip.empty? }
            conn.exec(ASSET_TAG_COUNTS_SCHEMA)
            TAG_COUNT_TRIGGER_NAMES.each { |name| conn.exec("DROP TRIGGER IF EXISTS #{name}") }
            TAG_COUNT_TRIGGERS.each { |sql| conn.exec(sql) }
            conn.exec(ASSET_INDEXES_SCHEMA)
            ASSET_KEYS_SCHEMA.split(";").each { |sql| conn.exec(sql.strip) unless sql.strip.empty? }
            conn.exec(ASSET_SEARCH_SCHEMA)
            conn.exec(ASSET_SEARCH_TERMS_SCHEMA)
          end
        ensure
          conn.exec("PRAGMA foreign_keys=ON")
        end
        if rebuilt
          violations = conn.query_all("PRAGMA foreign_key_check") { |rs| rs.read(::DB::Any) }
          raise "asset schema migration left invalid references" unless violations.empty?
        end
      end
      load_types
    end

    # 0.15 dropped the conversions from before 0.12 (Thomas, 2026-10-17):
    # a store last opened by an older DataDungeon, whose keys were still a
    # column of its assets, is opened once by 0.14 first.
    BEFORE_012 = "This store was last opened by a DataDungeon older than 0.12, which this one no longer converts: " \
                 "open it read-write once with DataDungeon 0.14, then with this one"

    private def before_012?(conn : ::DB::Connection) : Bool
      assets = table_columns(conn, "assets")
      !assets.empty? && (assets.has_key?("pool_key") || table_columns(conn, "asset_keys").empty?)
    end

    # A read-only open uses the schema as it is, so it must be the one
    # setup_schema leaves.
    private def check_schema : Nil
      @db.using_connection do |conn|
        raise BEFORE_012 if before_012?(conn)
        assets = table_columns(conn, "assets")
        named = table_columns(conn, "named_texts")
        current = assets.has_key?("description_id") && !assets.has_key?("generation") &&
                  named.has_key?("kind") && !named.has_key?("purpose") &&
                  table_columns(conn, "recipes").has_key?("prompt_id") &&
                  table_columns(conn, "recipe_fields").empty? &&
                  %w[image_meta image_animation image_keyframes audio_meta video_meta text_meta asset_links asset_search asset_search_terms asset_changes
                    asset_indexes asset_keys asset_tag_counts texts recipe_settings named_texts recipes recipe_wordings
                    recipe_legacy vocabulary_tags vocabulary_values].none? { |table| table_columns(conn, table).empty? }
        raise ReadOnlyError.new("The database needs upgrading: open it read-write once first") unless current
        # Added in 0.15.3, so a store not yet opened by it reads as having no tracks.
        @tracks_kept = !table_columns(conn, "asset_tracks").empty?
      end
    end

    private def writable! : Nil
      raise ReadOnlyError.new("This DataDungeon::DB is read-only") if @read_only
    end

    # Run the block in a transaction that takes SQLite's write lock up front
    # (BEGIN IMMEDIATE). A plain BEGIN reads first and asks for the lock at
    # its first write, and SQLite can't wait there: if another process wrote
    # in between, it fails at once with "database is locked". Asking first
    # means a busy database makes it wait (busy_timeout) instead.
    private def write_transaction(&)
      @db.using_connection { |conn| immediate(conn) { yield conn } }
    end

    private def immediate(conn : ::DB::Connection, &)
      conn.exec("BEGIN IMMEDIATE")
      begin
        result = yield
        conn.exec("COMMIT")
        result
      rescue ex
        begin
          conn.exec("ROLLBACK")
        rescue
          # the transaction may already be gone; the original error matters
        end
        raise ex
      end
    end

    # Column name => NOT NULL flag for a table.
    private def table_columns(conn : ::DB::Connection, table : String) : Hash(String, Int32)
      columns = {} of String => Int32
      conn.query("PRAGMA table_info(#{table})") do |rs|
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

    # The partial indexes over image fields, and the image_views view.
    private def image_indexes(conn : ::DB::Connection) : Nil
      IMAGE_INDEXED.each do |column|
        conn.exec("CREATE INDEX IF NOT EXISTS idx_image_#{column} ON image_meta(#{column}) WHERE #{column} IS NOT NULL")
        next unless KEYFRAME_FIELDS.includes?(column) # and alike on the checkpoints
        conn.exec("CREATE INDEX IF NOT EXISTS idx_keyframe_#{column} ON image_keyframes(#{column}) WHERE #{column} IS NOT NULL")
      end
      # Views read plainly at the sqlite3 prompt, where SQLite has its math
      # functions (not every build does).
      math = begin
        conn.scalar("SELECT asin(0.5)")
        true
      rescue SQLite3::Exception
        false
      end
      conn.exec(IMAGE_VIEWS) if math
    end

    # Each image's view in readable form (Direction), for people.
    IMAGE_VIEWS = <<-SQL
      CREATE VIEW IF NOT EXISTS image_views AS
      SELECT asset_id,
             CASE WHEN view_z >= 0 THEN 'front' ELSE 'back' END AS side,
             round(degrees(asin(max(-1.0, min(1.0, view_x / cos(asin(view_y)))))) / 90, 4) AS yaw,
             round(degrees(asin(view_y)) / 90, 4) AS pitch,
             view_roll AS roll
      FROM image_meta WHERE view_x IS NOT NULL
    SQL

    # ── Store ──

    # Index a file whose path the caller owns. The type must be registered:
    # DataDungeon normalizes the trait tags and derives the asset's keys from
    # them. `custom` names the tags whose values are not among the
    # application's standard choices; they are keyed like any other value
    # and can later be promoted.
    def store_asset(
      asset_type : String,
      media : String,
      content_type : String,
      file_path : String,
      tags : Hash(String, String) = {} of String => String,
      file_hash : String? = nil,
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
      made_at : Time? = nil,
      supersedes : Int64? = nil,
      recipe : Recipe? = nil,
    ) : Int64
      writable!
      validate_store(asset_type, media, tags, custom, image, audio, video, text)
      if recipe
        recipe.check
        check_wordings(recipe)
      end
      tags = normalize_traits(registered(asset_type), tags)

      now = Time.utc.to_s(TIME_FORMAT)
      asset_id = 0_i64

      @object_lock.synchronize do
        write_transaction do |conn|
          conn.exec(
            <<-SQL,
            INSERT INTO assets
            (asset_type, media, content_type, file_path, file_hash,
             created_at, last_used_at, use_count, permanent,
             generator, description_id, generated, rating, flagged, made_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, NULL, 0, ?)
          SQL
            asset_type, media, content_type, file_path, file_hash,
            now, now, permanent ? 1 : 0,
            generator, description.presence.try { |words| put_text(conn, words) }, generated ? 1 : 0,
            made_at.try(&.to_s(TIME_FORMAT)) || now
          )
          asset_id = conn.scalar("SELECT last_insert_rowid()").as(Int64)
          if old = generation
            conn.exec("INSERT INTO recipe_legacy (asset_id, generation) VALUES (?, ?)", asset_id, old)
          end
          recipe.try { |made| write_recipe(conn, asset_id, made) }

          tags.each do |k, v|
            conn.exec(
              "INSERT INTO asset_tags (asset_id, asset_type, tag_key, tag_value, custom) VALUES (?, ?, ?, ?, ?)",
              asset_id, asset_type, k, v, custom.includes?(k) ? 1 : 0
            )
          end

          # Store media-specific metadata
          if im = image
            values = image_values(im)
            conn.exec("INSERT INTO image_meta (asset_id, #{values.keys.join(", ")}) " \
                      "VALUES (?#{", ?" * values.size})", args: [asset_id.as(::DB::Any)] + values.values)
            im.animation.try { |animation| put_animation(conn, asset_id, animation) }
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
          reindex(conn, [asset_id]) # its keys; after the image fields, since a view is a search word
        end
      end
      supersede(asset_id, supersedes) if supersedes
      @indexer.try(&.enqueue_asset(asset_id))
      asset_id
    end

    private def validate_store(
      asset_type : String, media : String, tags : Hash(String, String), custom : Array(String),
      image : ImageMeta?, audio : AudioMeta?, video : VideoMeta?, text : TextMeta?,
    ) : Nil
      registered(asset_type)
      unless (unknown = custom - tags.keys).empty?
        raise ArgumentError.new("custom names #{unknown.join(", ")}, which have no tag")
      end
      check_tag_names(tags)

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
    # Every store adds an asset. `supersedes` names a take this one replaces
    # (see `supersede`), and `made_at` when the content was made, if not
    # now. Bytes the type already holds raise AlreadyStored, unless storing
    # them is an exact repeat (the same traits, the asset current), which
    # returns that asset.
    #
    # The type must be registered (register_type). Provide the source as
    # exactly one of `source_path` or `bytes`.
    def store(
      asset_type : String,
      tags : Hash(String, String) = {} of String => String,
      *,
      source_path : String? = nil,
      bytes : Bytes? = nil,
      content_type : String,
      media : String? = nil,
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
      made_at : Time? = nil,
      supersedes : Int64? = nil,
      recipe : Recipe? = nil,
    ) : AssetRecord
      writable!
      store = @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"
      unless source_path.nil? ^ bytes.nil?
        raise ArgumentError.new("provide exactly one of source_path / bytes")
      end
      ct = content_type
      m = media || DB.media_of(ct)
      # Reject bad arguments before writing, so a refused store leaves no object.
      validate_store(asset_type, m, tags, custom, image, audio, video, text)
      if recipe
        recipe.check
        check_wordings(recipe)
      end

      data = bytes || File.open(source_path.not_nil!, "rb", &.getb_to_end)

      # Apply the compression policy (may change bytes and content type),
      # then measure what's stored.
      if m == "image"
        if im = image
          data, ct = process_image(data, ct, im)
        end
        # Only a picture: an unknown content type's media is "image" too.
        image = measure_image(image || ImageMeta.new, data, ct) if ct.downcase.starts_with?("image/")
      end

      file_hash = Digest::SHA256.hexdigest(data)
      storage_key = object_key(file_hash, ct)
      if held = held_asset(asset_type, file_hash, tags)
        return held
      end

      id = @object_lock.synchronize do
        wrote = store.shared? || !store.exists?(storage_key)
        store.write(storage_key, data, ct) if wrote
        begin
          store_asset(
            asset_type: asset_type,
            media: m,
            content_type: ct,
            file_path: storage_key,
            tags: tags,
            file_hash: file_hash,
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
            made_at: made_at,
            supersedes: supersedes,
            recipe: recipe,
          )
        rescue ex
          release_object(storage_key) if wrote # no row will own it
          raise ex
        end
      end

      find_asset_by_id(id).not_nil!
    end

    # The image_meta values of these fields, by column, checked: an anchor
    # 0 to 1, a real size positive, a view or light made a unit vector.
    private def image_values(im : ImageMeta) : Hash(String, ::DB::Any)
      {im.anchor_x, im.anchor_y}.each do |anchor|
        raise ArgumentError.new("an anchor is 0 to 1 across or down") if anchor && !(0.0 <= anchor <= 1.0)
      end
      {im.world_width, im.world_height, im.world_depth}.each do |size|
        raise ArgumentError.new("a real size is in metres, more than 0") if size && !(size > 0 && size.finite?)
      end
      if (roll = im.view_roll) && !(-2.0 <= roll <= 2.0)
        raise ArgumentError.new("view_roll is -2 to 2 quarter turns")
      end
      view = unit_or_nil("view", im.view_x, im.view_y, im.view_z)
      light = unit_or_nil("light", im.light_x, im.light_y, im.light_z)
      {
        "width" => im.width, "height" => im.height, "usage_class" => im.usage_class, "compression" => im.compression,
        "quality_floor" => im.quality_floor, "max_colors" => im.max_colors, "target_format" => im.target_format,
        "presentation" => im.presentation, "transparent" => im.transparent.try { |t| t ? 1 : 0 },
        "dominant_color" => im.dominant_color, "content_x" => im.content_x, "content_y" => im.content_y,
        "content_w" => im.content_w, "content_h" => im.content_h, "measured" => im.measured? ? 1 : nil,
        "view_x" => view.try(&.[0]), "view_y" => view.try(&.[1]), "view_z" => view.try(&.[2]),
        "view_roll" => im.view_roll, "light_x" => light.try(&.[0]), "light_y" => light.try(&.[1]),
        "light_z" => light.try(&.[2]), "anchor_x" => im.anchor_x, "anchor_y" => im.anchor_y,
        "world_width" => im.world_width, "world_height" => im.world_height, "world_depth" => im.world_depth,
        "view_name" => view.try { |(x, y, z)| Direction.name(x, y, z) },
      } of String => ::DB::Any
    end

    # A vector given whole, as unit length; none given, nil.
    private def unit_or_nil(name : String, x : Float64?, y : Float64?, z : Float64?) : {Float64, Float64, Float64}?
      given = {x, y, z}.count(&.nil?.!)
      return nil if given == 0
      raise ArgumentError.new("a #{name} needs all of #{name}_x, #{name}_y and #{name}_z") if given < 3
      Direction.unit(x.not_nil!, y.not_nil!, z.not_nil!)
    end

    private def put_animation(conn, asset_id : Int64, animation : ImageAnimation) : Nil
      conn.exec(<<-SQL, asset_id, animation.frame_count, animation.duration_ms, animation.loop_count,
        INSERT INTO image_animation (asset_id, frame_count, duration_ms, loop_count, frame_w, frame_h, columns)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (asset_id) DO UPDATE SET frame_count = excluded.frame_count, duration_ms = excluded.duration_ms,
          loop_count = excluded.loop_count, frame_w = excluded.frame_w, frame_h = excluded.frame_h,
          columns = excluded.columns
      SQL
        animation.frame_w, animation.frame_h, animation.columns)
    end

    # The asset of this type already holding these bytes, when storing them
    # again is an exact repeat (the same traits, the asset current), so a
    # retry is safe; any other holder raises AlreadyStored.
    private def held_asset(asset_type : String, file_hash : String, tags : Hash(String, String)) : AssetRecord?
      held = @db.query_one?("SELECT #{ASSET_COLUMNS} FROM assets a WHERE a.file_hash = ? AND +a.asset_type = ? ORDER BY a.id LIMIT 1",
        file_hash, asset_type) { |rs| read_asset_record(rs) }
      return nil unless held
      repeat = !held.retired? && load_tags(held.id) == normalize_tags(asset_type, tags)
      repeat ? held : raise AlreadyStored.new(held.id, held.retired?)
    end

    # ── Retiring ──

    # `new_id` replaces `old_id`: the old take is retired (kept, but out of
    # get, listings, best match and search), `new_id supersedes old_id` is
    # linked as its history, and the old take's other links are copied to
    # the new one, placement data and all.
    def supersede(new_id : Int64, old_id : Int64) : Nil
      writable!
      raise ArgumentError.new("An asset can't supersede itself") if new_id == old_id
      new_rec = find_asset_by_id(new_id) || raise ArgumentError.new("No asset #{new_id}")
      old_rec = find_asset_by_id(old_id) || raise ArgumentError.new("No asset #{old_id}")
      unless new_rec.asset_type == old_rec.asset_type
        raise ArgumentError.new("Asset #{new_id} is a #{new_rec.asset_type}, #{old_id} a #{old_rec.asset_type}")
      end
      write_transaction do |conn|
        now = Time.utc.to_s(TIME_FORMAT)
        conn.exec("UPDATE assets SET retired_at = ? WHERE id = ? AND retired_at IS NULL", now, old_id)
        conn.exec(<<-SQL, new_id, old_id)
          INSERT OR IGNORE INTO asset_links (from_id, rel, to_id, to_name, created_at, data)
          SELECT ?, rel, to_id, to_name, created_at, data FROM asset_links WHERE from_id = ? AND rel <> 'supersedes'
          ORDER BY rowid
        SQL
        conn.exec("INSERT OR IGNORE INTO asset_links (from_id, rel, to_id, created_at) VALUES (?, 'supersedes', ?, ?)",
          new_id, old_id, now)
        log_change(conn, old_id)
        log_change(conn, new_id)
      end
      @indexer.try(&.enqueue_asset(old_id))
    end

    # Retire an asset with nothing replacing it: a soft, reversible delete.
    # Returns whether it was current.
    def retire(id : Int64) : Bool
      writable!
      retired = write_transaction do |conn|
        changed = conn.exec("UPDATE assets SET retired_at = ? WHERE id = ? AND retired_at IS NULL",
          Time.utc.to_s(TIME_FORMAT), id).rows_affected > 0
        log_change(conn, id) if changed
        changed
      end
      @indexer.try(&.enqueue_asset(id)) if retired
      retired
    end

    # Make a retired asset current again. If takes superseded it, it
    # supersedes in turn the current take they led to (directly, or down a
    # chain of takes): that take is retired, and the links superseding this
    # one go. Returns whether it was retired; a current asset is left as it is.
    def reinstate(id : Int64) : Bool
      writable!
      successors = [] of Int64
      was_retired = write_transaction do |conn|
        now = Time.utc.to_s(TIME_FORMAT)
        next false if conn.exec("UPDATE assets SET retired_at = NULL WHERE id = ? AND retired_at IS NOT NULL", id)
                        .rows_affected == 0
        successors = conn.query_all(<<-SQL, id, as: Int64)
          WITH RECURSIVE later(id) AS (
            SELECT from_id FROM asset_links WHERE rel = 'supersedes' AND to_id = ?
            UNION
            SELECT l.from_id FROM asset_links l JOIN later ON l.to_id = later.id WHERE l.rel = 'supersedes'
          )
          SELECT a.id FROM later JOIN assets a ON a.id = later.id WHERE a.retired_at IS NULL
        SQL
        conn.exec("DELETE FROM asset_links WHERE rel = 'supersedes' AND to_id = ?", id)
        successors.each do |successor|
          conn.exec("UPDATE assets SET retired_at = ? WHERE id = ?", now, successor)
          conn.exec("INSERT OR IGNORE INTO asset_links (from_id, rel, to_id, created_at) VALUES (?, 'supersedes', ?, ?)",
            id, successor, now)
          log_change(conn, successor)
        end
        log_change(conn, id)
        true
      end
      ([id] + successors).each { |changed| @indexer.try(&.enqueue_asset(changed)) } if was_retired
      was_retired
    end

    # Delete a type's retired assets: all, or keeping each key's (in the
    # type's own index) `keep_last` most recently retired, and only those
    # retired before `retired_before`. When to prune is the application's
    # call. Returns how many were deleted.
    def prune(asset_type : String, keep_last : Int32 = 0, retired_before : Time? = nil) : Int32
      writable!
      ids = @db.query_all(<<-SQL, asset_type, keep_last, retired_before.try(&.to_s(TIME_FORMAT)), as: Int64)
        SELECT id FROM (
          SELECT a.id, a.retired_at,
                 ROW_NUMBER() OVER (PARTITION BY ifnull(k.key, a.id) ORDER BY a.retired_at DESC, a.id DESC) AS rank
          FROM assets a
          LEFT JOIN asset_keys k ON k.asset_id = a.id AND k.index_id = #{OWN_INDEX.sub("?", "?1")}
          WHERE a.asset_type = ?1 AND a.retired_at IS NOT NULL
        ) WHERE rank > ?2 AND (?3 IS NULL OR retired_at < ?3)
      SQL
      ids.each { |id| delete_asset(id) }
      ids.size
    end

    # The assets holding these bytes, by their SHA-256, oldest first.
    # Identical bytes share one object, so several assets can hold it.
    def find_by_hash(file_hash : String) : Array(AssetRecord)
      query_assets("a.file_hash = ?", [file_hash] of ::DB::Any, retired: true)
    end

    # The rows that index a file outside the store: those `store_asset`
    # recorded by an absolute path the caller owns. `adopt` moves them in.
    def outside_store : Array(AssetRecord)
      query_assets("a.file_path LIKE '/%'", [] of ::DB::Any, retired: true)
    end

    # Move a row from `outside_store` into the store: copy its file's bytes
    # to their content-addressed key, as `store` would, and point the row at
    # that object. The row keeps its id, type, tags and metadata, and the
    # original file is left where it is. A row already in the store comes
    # back unchanged. Raises File::NotFoundError if the file is gone.
    def adopt(rec : AssetRecord) : AssetRecord
      writable!
      store = @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"
      return rec unless Path[rec.file_path].absolute?

      data = File.open(rec.file_path, "rb", &.getb_to_end)
      file_hash = Digest::SHA256.hexdigest(data)
      storage_key = object_key(file_hash, rec.content_type)

      @object_lock.synchronize do
        wrote = store.shared? || !store.exists?(storage_key)
        store.write(storage_key, data, rec.content_type) if wrote
        begin
          updated = write_transaction do |conn|
            conn.exec("UPDATE assets SET file_path = ?, file_hash = ? WHERE id = ?",
              storage_key, file_hash, rec.id).rows_affected
          end
          raise ArgumentError.new("No asset #{rec.id}") if updated == 0
        rescue ex
          release_object(storage_key) if wrote # no row will own it
          raise ex
        end
      end

      find_asset_by_id(rec.id).not_nil!
    end

    # Edit an asset in place, without storing its bytes again: replace its
    # tags, or change its description, flag, rating or `permanent`, or the image fields
    # the application sets (ImageMeta::SET_FIELDS, and an animation's frames
    # for a sprite sheet). Arguments left nil stay as they are. A registered
    # type's traits are normalized and its keys derived again. A tag stays
    # custom while its value is unchanged. A `rating` and `flagged` decide
    # which of several candidates `get` and best matches prefer.
    #
    # A blank description clears it. Assets can share one description (the
    # same `description_hash`); a new one is this asset's alone unless
    # `everywhere: true`, which gives it to every asset in the store that
    # shared this one's, as when fixing a typo. The old wording stays in the
    # store either way: a recipe may record it as what a provider was sent.
    def update_asset(id : Int64, *, tags : Hash(String, String)? = nil, description : String? = nil,
                     everywhere : Bool = false, flagged : Bool? = nil, rating : Int32? = nil,
                     image : ImageMeta? = nil, permanent : Bool? = nil) : AssetRecord
      writable!
      raise ArgumentError.new("everywhere: true changes a description, and none was given") if everywhere && description.nil?
      rec = find_asset_by_id(id) || raise ArgumentError.new("No asset #{id}")
      if image && rec.media != "image"
        raise ArgumentError.new("Asset #{id} is #{rec.media}, so it has no image fields")
      end
      changed = [id]
      @object_lock.synchronize do
        write_transaction do |conn|
          if words = description
            text_id = words.presence.try { |text| put_text(conn, text) }
            old = conn.query_one("SELECT description_id FROM assets WHERE id = ?", id, as: Int64?)
            if everywhere && old
              changed = conn.query_all("SELECT id FROM assets WHERE description_id = ?", old, as: Int64)
              conn.exec("UPDATE assets SET description_id = ? WHERE description_id = ?", text_id, old)
            else
              conn.exec("UPDATE assets SET description_id = ? WHERE id = ?", text_id, id)
            end
          end
          conn.exec("UPDATE assets SET permanent = ? WHERE id = ?", permanent ? 1 : 0, id) unless permanent.nil?
          conn.exec("UPDATE assets SET flagged = ? WHERE id = ?", flagged ? 1 : 0, id) unless flagged.nil?
          conn.exec("UPDATE assets SET rating = ? WHERE id = ?", rating, id) unless rating.nil?
          replace_tags(conn, rec, tags) if tags
          if im = image
            values = image_values(im).select(ImageMeta::SET_FIELDS + ["view_name"]).reject { |_, value| value.nil? }
            conn.exec("INSERT OR IGNORE INTO image_meta (asset_id) VALUES (?)", id)
            unless values.empty?
              conn.exec("UPDATE image_meta SET #{values.keys.map { |column| "#{column} = ?" }.join(", ")} WHERE asset_id = ?",
                args: values.values + [id.as(::DB::Any)])
            end
            im.animation.try { |animation| put_animation(conn, id, animation) }
          end
          reindex(conn, [id]) if tags || image
        end
      end
      changed.each { |changed_id| @indexer.try(&.enqueue_asset(changed_id)) }
      find_asset_by_id(id).not_nil!
    end

    # Tag names are the application's, except the empty one and those
    # starting with `@`, which DataDungeon keeps for counts of its own.
    private def check_tag_names(tags : Hash(String, String)) : Nil
      raise ArgumentError.new("a tag's name must not be empty") if tags.has_key?("")
      if reserved = tags.keys.find(&.starts_with?('@'))
        raise ArgumentError.new("tag #{reserved.inspect}: names starting with @ are DataDungeon's")
      end
    end

    private def replace_tags(conn, rec : AssetRecord, tags : Hash(String, String)) : Nil
      check_tag_names(tags)
      tags = normalize_tags(rec.asset_type, tags)
      custom = {} of String => String
      conn.query("SELECT tag_key, tag_value FROM asset_tags WHERE asset_id = ? AND custom = 1", rec.id) do |rs|
        rs.each { custom[rs.read(String)] = rs.read(String) }
      end
      conn.exec("DELETE FROM asset_tags WHERE asset_id = ?", rec.id)
      tags.each do |key, value|
        conn.exec("INSERT INTO asset_tags (asset_id, asset_type, tag_key, tag_value, custom) VALUES (?, ?, ?, ?, ?)",
          rec.id, rec.asset_type, key, value, custom[key]? == value ? 1 : 0)
      end
    end

    # High-level lookup: of the current, unflagged assets with these traits,
    # the preferred (PREFERRED: highest rating, then newest made); verifies
    # the backing file still exists (self-heals a stale row to a miss),
    # touches usage, and returns the record. Every current asset with the
    # traits comes from find_pool.
    def get(asset_type : String, traits : Hash(String, String), touch : Bool = true) : AssetRecord?
      get(key_for(asset_type, traits), touch)
    end

    # `get` by a key in a type's own index; the key names its type.
    def get(key : String, touch : Bool = true) : AssetRecord?
      rec = find_asset(key)
      return nil unless rec
      if (store = @storage) && store.local?
        return nil unless store.exists?(rec.file_path)
      end
      touch_asset(rec.id) if touch
      rec
    end

    # One asset by its id, retired or flagged too.
    def get_by_id(id : Int64, touch : Bool = true) : AssetRecord?
      rec = find_asset_by_id(id)
      return nil unless rec
      if (store = @storage) && store.local?
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
      traits : Hash(String, String),
      touch : Bool = true,
    ) : {AssetRecord, AssetMeta?}?
      get_with_meta(key_for(asset_type, traits), touch)
    end

    # `get_with_meta` by a key in a type's own index.
    def get_with_meta(key : String, touch : Bool = true) : {AssetRecord, AssetMeta?}?
      clause, args = key_clause(TraitKey.type_of(key), key)
      lookup_with_meta("#{clause} AND #{CANDIDATE}", args, touch)
    end

    def get_with_meta_by_id(id : Int64, touch : Bool = true) : {AssetRecord, AssetMeta?}?
      lookup_with_meta("a.id = ?", [id] of ::DB::Any, touch)
    end

    private def lookup_with_meta(where_clause : String, args : Array(::DB::Any), touch : Bool) : {AssetRecord, AssetMeta?}?
      pair = @db.query_one?(
        <<-SQL,
          SELECT #{ASSET_COLUMNS},
                 #{IMAGE_SELECT},
                 am.asset_id, am.duration_ms, am.sample_rate, am.bitrate,
                 am.channels, am.transcript_id, am.compression, am.target_format,
                 vm.asset_id, vm.width, vm.height, vm.duration_ms, vm.frame_rate,
                 vm.usage_class, vm.has_audio, vm.compression, vm.quality_floor,
                 vm.target_format, vm.presentation,
                 tm.asset_id, tm.content, tm.language
          FROM assets a
          LEFT JOIN image_meta im ON im.asset_id = a.id
          LEFT JOIN image_animation ia ON ia.asset_id = a.id
          LEFT JOIN audio_meta am ON am.asset_id = a.id
          LEFT JOIN video_meta vm ON vm.asset_id = a.id
          LEFT JOIN text_meta  tm ON tm.asset_id = a.id
          WHERE #{where_clause}
          #{PREFERRED}
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
      if (store = @storage) && store.local?
        return nil unless store.exists?(rec.file_path)
      end
      touch_asset(rec.id) if touch
      {rec, meta}
    end

    # The record's object, read through whichever storage is configured (a
    # local file or a remote bucket). Prefer it to opening path_for yourself,
    # which only works for local storage.
    def read(rec : AssetRecord) : Bytes
      store = @storage || raise "DataDungeon::DB has no storage backend"
      store.read(rec.file_path)
    end

    # Stream the record's object: the block gets an IO over its bytes, from
    # whichever storage is configured, without loading it all into memory.
    def open(rec : AssetRecord, & : IO ->) : Nil
      store = @storage || raise "DataDungeon::DB has no storage backend"
      store.open(rec.file_path) { |io| yield io }
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

    # These fields with what DataDungeon reads from the bytes in place of the
    # application's own, and marked measured, read or not.
    private def measure_image(image : ImageMeta, data : Bytes, content_type : String) : ImageMeta
      if found = ImageProbe.measure(data, content_type)
        image.measured(found)
      else
        image.tried
      end
    end

    # Application types that are text to read.
    STRUCTURED_TEXT = %w[application/json application/xml application/yaml application/x-yaml application/toml]

    # A content type's medium, when the caller gives none: its top-level
    # type (image, audio, video, text, model, font), with JSON, XML and YAML
    # counted as text, and any other type (a PDF, raw bytes) "data".
    def self.media_of(content_type : String) : String
      type = content_type.downcase.split(';').first.strip
      top, _, sub = type.partition('/')
      case top
      when "image", "audio", "video", "text", "model", "font"
        top
      when "application"
        STRUCTURED_TEXT.includes?(type) || sub.ends_with?("+json") || sub.ends_with?("+xml") ? "text" : "data"
      else
        "data"
      end
    end

    # ── Objects ──

    # Content-addressed storage key: the SHA-256 of the stored bytes, under a
    # directory named for its first two hex characters, with an extension from
    # the content type so files served or opened by path keep their type.
    private def object_key(file_hash : String, content_type : String) : String
      "#{file_hash[0, 2]}/#{file_hash}.#{ext_for(content_type)}"
    end

    # The extension for a content type, ignoring parameters such as
    # `; charset=utf-8`
    private def ext_for(content_type : String) : String
      case content_type.split(';').first.strip.downcase
      when "image/webp"               then "webp"
      when "image/png"                then "png"
      when "image/jpeg", "image/jpg"  then "jpg"
      when "image/gif"                then "gif"
      when "image/svg+xml"            then "svg"
      when "audio/mpeg", "audio/mp3"  then "mp3"
      when "audio/ogg"                then "ogg"
      when "audio/opus"               then "opus"
      when "audio/wav", "audio/x-wav" then "wav"
      when "video/webm"               then "webm"
      when "video/mp4"                then "mp4"
      when "text/plain"               then "txt"
      when "application/json"         then "json"
      when "application/pdf"          then "pdf"
      else                                 "bin"
      end
    end

    # Unlink an object once no row references it, unless other stores share
    # the storage (Storage#shared?). Callers hold @object_lock.
    private def release_object(key : String) : Nil
      store = @storage
      return unless store
      return if store.shared?
      referenced = @db.query_one?("SELECT 1 FROM assets WHERE file_path = ? LIMIT 1", key, as: Int64)
      store.delete(key) unless referenced
    end

    # ── Find ──

    # Of the current, unflagged assets with this key in its type's own
    # index, the preferred (PREFERRED), without get's file check or touch.
    def find_asset(key : String) : AssetRecord?
      clause, args = key_clause(TraitKey.type_of(key), key)
      @db.query_one?("SELECT #{ASSET_COLUMNS} FROM assets a WHERE #{clause} AND #{CANDIDATE} #{PREFERRED} LIMIT 1",
        args: args) { |rs| read_asset_record(rs) }
    end

    # Which assets `get` and best matches choose among: current ones nobody
    # has flagged (a report takes an asset out of play; listings still show
    # it).
    CANDIDATE = "a.retired_at IS NULL AND ifnull(a.flagged, 0) = 0"

    # Which of several candidates to prefer: the highest rating (none counts
    # as 0), then the newest made, then the newest filed.
    PREFERRED = "ORDER BY ifnull(a.rating, 0) DESC, a.made_at DESC, a.id DESC"

    def find_asset_by_id(id : Int64) : AssetRecord?
      @db.query_one?(
        "SELECT #{ASSET_COLUMNS} FROM assets a WHERE a.id = ? LIMIT 1", id
      ) { |rs| read_asset_record(rs) }
    end

    # Assets of a type carrying every one of these tags (and possibly others).
    def find_assets_by_tags(asset_type : String, filter_tags : Hash(String, String)) : Array(AssetRecord)
      filter_tags = normalize_tags(asset_type, filter_tags)
      return [] of AssetRecord if filter_tags.empty?
      from, where, args = tag_filter(asset_type, filter_tags) || return [] of AssetRecord

      results = [] of AssetRecord
      @db.query("SELECT #{ASSET_COLUMNS} FROM #{from} WHERE #{where} AND a.retired_at IS NULL ORDER BY a.id", args: args) do |rs|
        rs.each { results << read_asset_record(rs) }
      end
      results
    end

    # ── Browse ──

    # Every asset type with how many current assets it has (with
    # `retired: true`, how many retired ones), by name. Registered types
    # are listed even with none.
    def asset_types(retired : Bool = false) : Hash(String, Int32)
      counts = {} of String => Int32
      @types.each_key { |name| counts[name] = 0 }
      @db.query("SELECT asset_type, #{retired ? "retired" : "current"} FROM asset_tag_counts " \
                "WHERE tag_key = '' AND tag_value = ''") do |rs|
        rs.each { counts[rs.read(String)] = rs.read(Int64).to_i32 }
      end
      counts.to_a.sort_by!(&.[0]).to_h
    end

    # A type's tag names, each with how many of its current assets (or,
    # with `retired`, as list_assets takes it, others) carry it.
    def tag_keys(asset_type : String, retired : Bool? = false) : Hash(String, Int32)
      counts = {} of String => Int32
      @db.query(<<-SQL, asset_type) do |rs|
        SELECT tag_key, SUM(#{counted(retired)}) FROM asset_tag_counts
        WHERE asset_type = ? AND tag_key <> '' AND tag_key NOT LIKE '@%'
        GROUP BY tag_key HAVING SUM(#{counted(retired)}) > 0 ORDER BY tag_key
      SQL
        rs.each { counts[rs.read(String)] = rs.read(Int64).to_i32 }
      end
      counts
    end

    # The values one tag takes across a type's current assets (or, with
    # `retired`, others), most frequent first, each with how many carry it.
    def tag_values(asset_type : String, tag_key : String, limit : Int32 = 100,
                   retired : Bool? = false) : Hash(String, Int32)
      counts = {} of String => Int32
      @db.query(<<-SQL, asset_type, tag_key, limit) do |rs|
        SELECT tag_value, #{counted(retired)} AS n FROM asset_tag_counts
        WHERE asset_type = ? AND tag_key = ? AND n > 0 ORDER BY n DESC, tag_value LIMIT ?
      SQL
        rs.each { counts[rs.read(String)] = rs.read(Int64).to_i32 }
      end
      counts
    end

    # How many of a type's current pictures (or, with `retired`, others) are
    # seen from each named direction, most first. Each word of a view's name
    # counts (`back-left`, `from-above`), as the `view=` filter takes them.
    def view_counts(asset_type : String, retired : Bool? = false) : Hash(String, Int32)
      counts = {} of String => Int32
      @db.query(<<-SQL, asset_type) do |rs|
        SELECT tag_value, #{counted(retired)} AS n FROM asset_tag_counts
        WHERE asset_type = ? AND tag_key = '@view' AND n > 0 ORDER BY n DESC, tag_value
      SQL
        rs.each { counts[rs.read(String)] = rs.read(Int64).to_i32 }
      end
      counts
    end

    # The kept count a listing's `retired` takes.
    private def counted(retired : Bool?) : String
      case retired
      in false then "current"
      in true  then "retired"
      in nil   then "current + retired"
      end
    end

    # Which assets a listing takes: current ones (`false`, the default),
    # retired ones (`true`), or both (`nil`).
    private def retired_clause(retired : Bool?) : String
      case retired
      in false then "a.retired_at IS NULL"
      in true  then "a.retired_at IS NOT NULL"
      in nil   then "1 = 1"
      end
    end

    # A page of current assets (with `retired: true` retired ones, with
    # `nil` both), newest filed first: of one type or of all, carrying every
    # one of `tags` (normalized for a registered type), matching every word
    # of `q`, linked by each relation in `links` to a name (or a pattern:
    # `boardwalk.*`, `boardwalk*`, see `links_to`), with no `unlinked` link,
    # with the file `file_hash` (to follow a recipe's reference), the
    # description `description_hash` (every asset sharing one), and using
    # each named text in `texts` (prompt field => `owner:name`, any wording,
    # or `owner:name@version`). Each word of `q` is the type or a tag value (or a part
    # of one), in any order, as in a search box: `cattacula night` finds
    # `front.boardwalk.cattacula.night`; `catt*` matches the start of a
    # word; and `red-hair` matches only a labelled trait spelled that way. Skip `offset` assets for a numbered
    # page (it costs a little per asset skipped: about 2 ms for 100,000), or,
    # to walk through them all, pass the last asset's id as `before` for the
    # next page. `count_assets` counts them all.
    def list_assets(asset_type : String? = nil, tags : Hash(String, String) = {} of String => String, *,
                    q : String? = nil, links : Hash(String, String) = {} of String => String,
                    unlinked : String? = nil, limit : Int32 = 50, offset : Int32 = 0,
                    before : Int64? = nil, retired : Bool? = false, image : ImageFilter? = nil,
                    file_hash : String? = nil, description_hash : String? = nil,
                    texts : Hash(String, String) = {} of String => String) : Array(AssetRecord)
      from, where, args, order = asset_filter(asset_type, tags, q, links, unlinked, retired, image, limit + offset,
        file_hash, description_hash, texts) || return [] of AssetRecord
      if before
        where += " AND #{order} < ?"
        args << before
      end
      results = [] of AssetRecord
      @db.query("SELECT #{ASSET_COLUMNS} FROM #{from} WHERE #{where} ORDER BY #{order} DESC LIMIT ? OFFSET ?",
        args: args + [limit, offset] of ::DB::Any) do |rs|
        rs.each { results << read_asset_record(rs) }
      end
      results
    end

    # How many assets `list_assets` would list with these filters, on every
    # page. It reads every match, so ask only when the total is wanted.
    def count_assets(asset_type : String? = nil, tags : Hash(String, String) = {} of String => String, *,
                     q : String? = nil, links : Hash(String, String) = {} of String => String,
                     unlinked : String? = nil, retired : Bool? = false, image : ImageFilter? = nil,
                     file_hash : String? = nil, description_hash : String? = nil,
                     texts : Hash(String, String) = {} of String => String) : Int64
      from, where, args, _ = asset_filter(asset_type, tags, q, links, unlinked, retired, image, nil,
        file_hash, description_hash, texts) || return 0_i64
      @db.scalar("SELECT COUNT(*) FROM #{from} WHERE #{where}", args: args).as(Int64)
    end

    # The FROM, WHERE, arguments and ordering column for list_assets, which
    # wants `reach` assets (its limit and offset), or count_assets (nil).
    #
    # Search words are found whichever of three ways costs least, judged by
    # how many assets have each word:
    # - the full-text index finds every asset with each word, so its cost
    #   grows with how many have them (about 22 ns each);
    # - the index finds only the rarest word, and the others are checked on
    #   those assets (about 0.46 us each), for a rare word among common ones;
    # - walking the newest assets and checking their words stops once the
    #   page is full, so its cost grows with how rare the words are together
    #   (about 0.44 us an asset), not with the store: for common words.
    # Counting every match never walks.
    private def asset_filter(asset_type : String?, tags : Hash(String, String), q : String?,
                             links : Hash(String, String), unlinked : String?, retired : Bool?,
                             image : ImageFilter?, reach : Int32?, file_hash : String? = nil,
                             description_hash : String? = nil,
                             texts : Hash(String, String) = {} of String => String) : {String, String, Array(::DB::Any), String}?
      tags = normalize_tags(asset_type, tags) if asset_type
      clauses = [retired_clause(retired)]
      args = [] of ::DB::Any
      from, order, id = "assets a", "a.id", "a.id"
      words = search_terms(q)
      unless words.empty?
        route, rarest = search_route(words, reach)
        if route.walk?
          from = "assets a CROSS JOIN asset_search s"
          clauses << "s.rowid = a.id"
        else
          from, order = "asset_search s CROSS JOIN assets a", "s.rowid"
          clauses << "asset_search MATCH ? AND a.id = s.rowid"
          found = route.rarest? ? [rarest] : words
          args << found.map { |word| %("#{word.text}"#{"*" if word.prefix}) }.join(" ")
        end
        checked = case route
                  in .walk?   then words
                  in .rarest? then words - [rarest]
                  in .index?  then [] of SearchWord
                  end
        checked.each do |word|
          clauses << "(' ' || s.words || ' ') LIKE ? ESCAPE '\\'"
          escaped = word.text.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
          args << "% #{escaped}#{word.prefix ? "%" : " %"}"
        end
      end
      if asset_type && !tags.empty? && words.empty?
        tag_from, tag_where, tag_args = tag_filter(asset_type, tags, reach) || return nil
        from = tag_from
        clauses << tag_where
        args.concat(tag_args)
      else
        if asset_type
          clauses << "a.asset_type = ?"
          args << asset_type
        end
        tags.each do |key, value|
          clauses << "EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = #{id} AND t.tag_key = ? AND t.tag_value = ?)"
          args << key << value
        end
      end
      links.each do |rel, name|
        match, match_args = name_match("to_name", name)
        clauses << "#{id} IN (SELECT from_id FROM asset_links WHERE rel = ? AND #{match})"
        args << rel
        args.concat(match_args)
      end
      if rel = unlinked
        clauses << "NOT EXISTS (SELECT 1 FROM asset_links l WHERE l.from_id = #{id} AND l.rel = ?)"
        args << rel
      end
      if hash = file_hash
        clauses << "a.file_hash = ?"
        args << hash
      end
      if hash = description_hash
        clauses << "a.description_id = (SELECT id FROM texts WHERE hash = ?)"
        args << hash
      end
      texts.each do |kind, name|
        sql, text_args = using_text(kind, name)
        clauses << "#{id} IN (#{sql})"
        args.concat(text_args)
      end
      image.try { |filter| image_clause(filter, id, clauses, args) }
      {from, clauses.join(" AND "), args, order}
    end

    # Image fields a listing can ask for by range.
    RANGE_FIELDS = %w[width height content_x content_y content_w content_h view_x view_y view_z view_roll
      light_x light_y light_z anchor_x anchor_y world_width world_height world_depth]

    # The picture's fields as an ImageFilter asks, checked on each asset.
    # A field an animation's checkpoints can change matches at its first
    # frame or at any checkpoint ("does it ever show the back?"); each
    # condition on its own.
    private def image_clause(filter : ImageFilter, id : String, clauses : Array(String), args : Array(::DB::Any)) : Nil
      conditions = [] of String
      # Each condition is SQL over `{t}` (the image_meta or keyframe row),
      # its arguments, and whether checkpoints can change it.
      add = ->(sql : String, values : Array(::DB::Any), fields : Array(String)) do
        if fields.all? { |field| KEYFRAME_FIELDS.includes?(field) }
          conditions << "(#{sql.gsub("{t}", "im")} OR EXISTS (SELECT 1 FROM image_keyframes k " \
                        "WHERE k.asset_id = im.asset_id AND #{sql.gsub("{t}", "k")}))"
          args.concat(values + values)
        else
          conditions << sql.gsub("{t}", "im")
          args.concat(values)
        end
      end
      filter.ranges.each do |field, (low, high)|
        raise ArgumentError.new("#{field} isn't an image field to filter by") unless RANGE_FIELDS.includes?(field)
        sql = "{t}.#{field} IS NOT NULL"
        values = [] of ::DB::Any
        if low
          sql += " AND {t}.#{field} >= ?"
          values << low
        end
        if high
          sql += " AND {t}.#{field} <= ?"
          values << high
        end
        add.call(sql, values, [field])
      end
      {"view" => {filter.view, filter.view_within}, "light" => {filter.light, filter.light_within}}.each do |name, (direction, within)|
        next unless direction
        x, y, z = direction.vector
        # Within an angle of it: one dot product of unit vectors.
        add.call("{t}.#{name}_x * ? + {t}.#{name}_y * ? + {t}.#{name}_z * ? >= ?",
          [x, y, z, Math.cos(within * Math::PI / 180)] of ::DB::Any, %w[x y z].map { |axis| "#{name}_#{axis}" })
      end
      filter.direction.try &.split.each do |word|
        values = [] of ::DB::Any
        add.call(named_direction(word, values), values, %w[view_x view_y view_z])
      end
      return if conditions.empty?
      clauses << "EXISTS (SELECT 1 FROM image_meta im WHERE im.asset_id = #{id} AND #{conditions.join(" AND ")})"
    end

    SIN_22 = Math.sin(22.5 * Math::PI / 180)
    SIN_67 = Math.sin(67.5 * Math::PI / 180)

    # A view's named direction (Direction#name) as a condition on its
    # vector, in plain arithmetic: around the thing, the horizontal part
    # within 22.5 degrees of the name's (squared, so no square root), short
    # of the poles; above or below, by the vector's height.
    private def named_direction(word : String, args : Array(::DB::Any)) : String
      case word
      when "top-down"   then "{t}.view_y >= #{SIN_67}"
      when "bottom-up"  then "{t}.view_y <= -#{SIN_67}"
      when "from-above" then "{t}.view_y >= #{SIN_22} AND {t}.view_y < #{SIN_67}"
      when "from-below" then "{t}.view_y <= -#{SIN_22} AND {t}.view_y > -#{SIN_67}"
      else
        sector = Direction::AROUND.index(word) || raise ArgumentError.new(
          "#{word.inspect} isn't a named view: #{(Direction::AROUND + %w[from-above from-below top-down bottom-up]).join(", ")}")
        angle = sector * Math::PI / 4
        dx, dz = Math.sin(angle).round(12), Math.cos(angle).round(12)
        3.times { args << dx << dz } # one pair for each `view_x * ? + view_z * ?`
        "abs({t}.view_y) < #{SIN_67} AND {t}.view_x * ? + {t}.view_z * ? >= 0 AND " \
        "({t}.view_x * ? + {t}.view_z * ?) * ({t}.view_x * ? + {t}.view_z * ?) >= " \
        "#{Math.cos(Math::PI / 8) ** 2} * ({t}.view_x * {t}.view_x + {t}.view_z * {t}.view_z)"
      end
    end

    WALK_COST  =  0.44 # microseconds to check one asset's words on a walk
    INDEX_COST = 0.022 # microseconds per match the full-text index reads

    # A search-box word: a whole word to find, or with `prefix` (typed as
    # `catt*`) the start of one.
    record SearchWord, text : String, prefix : Bool

    # Search-box words, as the index holds them: lowercase, and split at
    # anything but letters, digits, dashes and underscores (so at spaces,
    # dots and quotes). A word ending in `*` matches the start of a word.
    private def search_terms(q : String?) : Array(SearchWord)
      words = (q || "").split(/[\s.]+/, remove_empty: true).flat_map do |typed|
        parts = search_text(typed).split(' ', remove_empty: true)
        parts.map_with_index { |part, i| SearchWord.new(part, typed.ends_with?('*') && i == parts.size - 1) }
      end
      words.uniq
    end

    private def search_text(text : String) : String
      text.downcase.gsub { |char| char.alphanumeric? || char == '-' || char == '_' ? char : ' ' }
    end

    CHECK_COST = 0.46 # microseconds to read and check an asset found by its rarest word

    enum SearchRoute
      Index  # every word from the full-text index
      Rarest # the rarest word from the index, the others checked
      Walk   # the newest assets, checked
    end

    # The cheapest route to `reach` matches (nil: all of them) for these
    # words, and the rarest word, from how many assets have each word
    # (taken as independent; the start of a word counts every word it starts).
    private def search_route(words : Array(SearchWord), reach : Int32?) : {SearchRoute, SearchWord}
      total = @db.query_one?("SELECT docs FROM asset_search_terms WHERE term = ''", as: Int64) || 0_i64
      counts = words.map do |word|
        docs = if word.prefix
                 @db.scalar("SELECT ifnull(sum(docs), 0) FROM asset_search_terms WHERE term >= ? AND term < ?",
                   word.text, word.text.rchop + word.text[-1].succ).as(Int64)
               else
                 @db.query_one?("SELECT docs FROM asset_search_terms WHERE term = ?", word.text, as: Int64) || 0_i64
               end
        {word, docs}
      end
      rarest, fewest = counts.min_by(&.[1])
      costs = {SearchRoute::Index => counts.sum(&.[1]) * INDEX_COST}
      costs[SearchRoute::Rarest] = fewest * (INDEX_COST + CHECK_COST) if words.size > 1
      if reach && total > 0
        share = counts.product(1.0) { |(_, docs)| Math.min(1.0, docs / total) }
        costs[SearchRoute::Walk] = reach / share * WALK_COST if share > 0
      end
      {costs.min_by(&.[1])[0], rarest}
    end

    # Refresh what is derived from these assets' tags, or drop it for assets
    # gone: their search words (and the counts of their words) and their
    # keys in every index of their type, its own among them. Run inside the
    # write that changed them. The indexes and labels are read here, not
    # remembered, so an index another process registered since this one
    # opened is kept too, and a registration saved earlier in this
    # transaction counts.
    private def reindex(conn, ids : Array(Int64)) : Nil
      indexes = query_indexes(conn, "1 = 1", [] of ::DB::Any).group_by(&.asset_type)
      labels = {} of String => Hash(String, String)
      ids.each_slice(500) do |batch|
        types = {} of Int64 => String
        # Placeholders, not the ids: each distinct SQL text stays cached as a
        # prepared statement for the connection's life.
        conn.query("SELECT id, asset_type FROM assets WHERE id IN (#{Array.new(batch.size, "?").join(", ")})",
          args: batch.map(&.as(::DB::Any))) do |rs|
          rs.each { types[rs.read(Int64)] = rs.read(String) }
        end
        tags = tags_batch(conn, batch)
        views = {} of Int64 => String
        conn.query("SELECT asset_id, view_x, view_y, view_z FROM image_meta " \
                   "WHERE asset_id IN (#{Array.new(batch.size, "?").join(", ")}) AND view_x IS NOT NULL",
          args: batch.map(&.as(::DB::Any))) do |rs|
          rs.each { views[rs.read(Int64)] = Direction.name(rs.read(Float64), rs.read(Float64), rs.read(Float64)) }
        end
        batch.each do |id|
          unindex_search(conn, id)
          log_change(conn, id)
          next unless type = types[id]?
          asset_tags = tags[id]? || {} of String => String
          type_labels = labels[type] ||= stored_labels(conn, type)
          words = search_words(asset_tags, type, type_labels, views[id]?)
          conn.exec("INSERT INTO asset_search (rowid, words) VALUES (?, ?)", id, words)
          count_terms(conn, words, 1)
          indexes[type]?.try &.each { |index| put_key(conn, index, id, asset_tags, type_labels) }
        end
      end
    end

    # An asset's key in an index (TraitKey, over the index's traits).
    private def put_key(conn, index : AssetIndex, asset_id : Int64, tags : Hash(String, String),
                        labels : Hash(String, String)) : Nil
      conn.exec(<<-SQL, asset_id, index.id, TraitKey.key(index.asset_type, index.traits, tags, labels))
        INSERT INTO asset_keys (asset_id, index_id, key) VALUES (?, ?, ?)
        ON CONFLICT (asset_id, index_id) DO UPDATE SET key = excluded.key
      SQL
    end

    # A type's labels as the database holds them (none for an unregistered
    # type).
    private def stored_labels(conn, asset_type : String) : Hash(String, String)
      conn.query_one?("SELECT labels FROM asset_types WHERE asset_type = ?", asset_type) do |rs|
        Hash(String, String).from_json(rs.read(String))
      end || {} of String => String
    end

    private def unindex_search(conn, id : Int64) : Nil
      words = conn.query_one?("SELECT words FROM asset_search WHERE rowid = ?", id, as: String)
      return unless words
      conn.exec("DELETE FROM asset_search WHERE rowid = ?", id)
      count_terms(conn, words, -1)
    end

    # Add `by` to the count of each of these words, and of every asset ('').
    private def count_terms(conn, words : String, by : Int32) : Nil
      ([""] + words.split(' ', remove_empty: true).uniq).each do |term|
        conn.exec("INSERT INTO asset_search_terms (term, docs) VALUES (?, ?) " \
                  "ON CONFLICT(term) DO UPDATE SET docs = docs + excluded.docs", term, by)
      end
      conn.exec("DELETE FROM asset_search_terms WHERE docs <= 0 AND term <> ''") if by < 0
    end

    private def reindex_type(conn, asset_type : String) : Nil
      reindex(conn, conn.query_all("SELECT id FROM assets WHERE asset_type = ?", asset_type, as: Int64))
    end

    # The type and every tag value, each with its parts, a labelled trait
    # also as keys spell it (`red-hair`), and a picture's named view
    # (`back-left from-above`).
    private def search_words(tags : Hash(String, String), asset_type : String, labels : Hash(String, String),
                             view : String? = nil) : String
      words = word_and_parts(asset_type)
      tags.each do |key, value|
        words.concat(word_and_parts(value))
        labels[key]?.try { |label| words << "#{value}-#{label}" }
      end
      view.try &.split(' ').each { |word| words.concat(word_and_parts(word)) }
      search_text(words.join(" ")).split(' ', remove_empty: true).uniq.join(" ")
    end

    private def word_and_parts(text : String) : Array(String)
      parts = text.split(/[-_]/, remove_empty: true)
      parts.size > 1 ? [text] + parts : [text]
    end

    # Whether a current asset has this key in its type's own index.
    def asset_exists?(key : String) : Bool
      clause, args = key_clause(TraitKey.type_of(key), key)
      !@db.query_one?("SELECT 1 FROM assets a WHERE #{clause} AND a.retired_at IS NULL LIMIT 1",
        args: args, as: Int64).nil?
    end

    # ── Links ──

    # Relate an asset to another asset (`derived-from`) or to a name
    # (`used-by` "boardwalk.holidayland": a name nests under its user with
    # dots, so filters can take a user and everything under it). Relations
    # are lowercase words joined by '-'. `data` is JSON kept with the link,
    # such as how the asset is placed in that use; linking again replaces it
    # when given, and otherwise changes nothing. Links go when either asset
    # does. A `supersedes` link is made by `supersede`, which also retires
    # the old take.
    def link(from_id : Int64, rel : String, to : Int64 | String, data : String? = nil) : Nil
      writable!
      raise ArgumentError.new("relation #{rel.inspect} must be lowercase words joined by '-'") unless rel.matches?(LABEL)
      if rel == "supersedes"
        raise ArgumentError.new("an asset supersedes another asset, not a name") unless to.is_a?(Int64)
        raise ArgumentError.new("a supersedes link carries no data") if data
        return supersede(from_id, to)
      end
      raise ArgumentError.new("No asset #{from_id}") unless find_asset_by_id(from_id)
      case to
      in Int64
        raise ArgumentError.new("No asset #{to}") unless find_asset_by_id(to)
      in String
        raise ArgumentError.new("a link's name must not be empty") if to.strip.empty?
        raise ArgumentError.new("a link's name can't hold '*', which filters read as a prefix") if to.includes?('*')
      end
      if data
        begin
          JSON.parse(data)
        rescue ex : JSON::ParseException
          raise ArgumentError.new("a link's data must be JSON: #{ex.message}")
        end
      end
      write_transaction do |conn|
        conn.exec(<<-SQL, from_id, rel, to.as?(Int64), to.as?(String), Time.utc.to_s(TIME_FORMAT), data)
          INSERT INTO asset_links (from_id, rel, to_id, to_name, created_at, data) VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT (from_id, rel, ifnull(to_id, 0), ifnull(to_name, '')) DO UPDATE SET data = ifnull(excluded.data, data)
        SQL
      end
    end

    # Remove a link; returns whether there was one. Removing a `supersedes`
    # link leaves the old take retired: `reinstate` brings it back.
    def unlink(from_id : Int64, rel : String, to : Int64 | String) : Bool
      writable!
      write_transaction do |conn|
        conn.exec(<<-SQL, from_id, rel, to.as?(Int64) || 0_i64, to.as?(String) || "").rows_affected > 0
          DELETE FROM asset_links
          WHERE from_id = ? AND rel = ? AND ifnull(to_id, 0) = ? AND ifnull(to_name, '') = ?
        SQL
      end
    end

    # An asset's links, of one relation or of all.
    def links_from(id : Int64, rel : String? = nil) : Array(Link)
      query_links("from_id = ?#{" AND rel = ?" if rel}", rel ? [id, rel] of ::DB::Any : [id] of ::DB::Any)
    end

    # The links to an asset, or to names (a pattern, as `name_match` takes
    # it), of one relation or of all.
    def links_to(to : Int64 | String, rel : String? = nil) : Array(Link)
      where, args = to.is_a?(Int64) ? {"to_id = ?", [to] of ::DB::Any} : name_match("to_name", to)
      if rel
        where = "rel = ? AND #{where}"
        args = [rel] of ::DB::Any + args
      end
      query_links(where, args)
    end

    # SQL matching a link's name to a pattern: `boardwalk.holidayland`
    # exactly; `boardwalk.*` that name and every name under it, but not
    # `boardwalk-annex`; `boardwalk*` every name starting so. Each reads
    # only its range of the name index.
    private def name_match(column : String, pattern : String) : {String, Array(::DB::Any)}
      if base = pattern.rchop?(".*")
        raise ArgumentError.new("#{pattern.inspect} needs a name before .*") if base.empty?
        {"(#{column} = ? OR (#{column} >= ? AND #{column} < ?))", [base, "#{base}.", "#{base}/"] of ::DB::Any}
      elsif start = pattern.rchop?('*')
        raise ArgumentError.new("#{pattern.inspect} needs a start before *") if start.empty?
        {"#{column} >= ? AND #{column} < ?", [start, start.rchop + start[-1].succ] of ::DB::Any}
      else
        {"#{column} = ?", [pattern] of ::DB::Any}
      end
    end

    private def query_links(where : String, args : Array(::DB::Any)) : Array(Link)
      @db.query_all("SELECT from_id, rel, to_id, to_name, created_at, data FROM asset_links WHERE #{where} ORDER BY created_at, rowid",
        args: args) do |rs|
        Link.new(rs.read(Int64), rs.read(String), rs.read(Int64?), rs.read(String?), rs.read(String),
          rs.read(String?).try { |data| JSON.parse(data) })
      end
    end

    # ── Registry ──

    TRAIT_NAME = /\A[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*\z/
    TYPE_NAME  = /\A[a-z0-9]+(?:[_-][a-z0-9]+)*\z/
    LABEL      = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    # Declare an asset type, which storing requires. DataDungeon derives each
    # asset's key in the type's own index from its `pool_traits` tags, so
    # applications never build keys. List the traits most important first: the key is their
    # normalized values in that order (see TraitKey), so a lookup on leading
    # traits is a prefix match. `group_traits` names the leading traits that
    # make up the type's group, and `labels` suffixes for traits whose values
    # alone would read ambiguously in a key (`{"skin" => "skin"}` gives
    # `tan-skin`). `sets` names traits whose value is a set, given as
    # comma-separated members in any order (`"sword, Lantern"` is stored and
    # keyed as `lantern,sword`); a set matches only the same set. Trait tags
    # are stored normalized, as the key holds them. `facets` names groups of
    # tags that SemanticIndex embeds separately, so a search can rank one
    # part of an asset (its hair, say) without the rest diluting it.
    # `scales`, `colors` and `weights` shape best matches (MatchIndex) and
    # change no keys: `scales` lists an ordered trait's values low to high
    # (`{"rating" => %w[g pg r x]}`), so near values count as close; `colors`
    # names traits whose values are colors (CSS names or hex codes),
    # compared by appearance; `cycles` lists values that go round a circle
    # (`{"time" => %w[dawn day dusk night]}`), so night's nearest are dusk
    # and dawn; `match_fields` names image fields matched on beside the
    # traits (AssetType::MATCH_FIELDS); `weights` gives traits (and match
    # fields) a default weight other than 1. A key is an index, not a name:
    # several current assets can share one, and every store adds an asset.
    #
    # The registration is stored in the database. Registering a type again
    # with the same definition changes nothing, and one that changes only
    # what keys don't hold (facets, scales, colors, cycles, weights, match
    # fields) is saved as it is. Other traits, a new order, group, labels or
    # sets raise unless `rekey: true`: changing them re-derives the keys of
    # every asset of the type, so a process holding a stale definition fails
    # loudly instead of re-keying every asset.
    def register_type(
      asset_type : String,
      *,
      pool_traits : Array(String),
      group_traits : Array(String) = [] of String,
      labels : Hash(String, String) = {} of String => String,
      sets : Array(String) = [] of String,
      facets : Hash(String, Array(String)) = {} of String => Array(String),
      scales : Hash(String, Array(String)) = {} of String => Array(String),
      colors : Array(String) = [] of String,
      weights : Hash(String, Float64) = {} of String => Float64,
      cycles : Hash(String, Array(String)) = {} of String => Array(String),
      match_fields : Array(String) = [] of String,
      rekey : Bool = false,
    ) : AssetType
      writable!
      scales = scales.transform_values { |values| values.compact_map { |value| TraitKey.normalize(value) } }
      cycles = cycles.transform_values { |values| values.compact_map { |value| TraitKey.normalize(value) } }
      definition = AssetType.new(asset_type, pool_traits, group_traits, labels, sets, facets,
        scales, colors, weights, cycles, match_fields)
      validate_type(definition)
      changed = [] of Int64
      @object_lock.synchronize do
        stored = stored_type(asset_type)
        if stored && stored[0].keyed_differently?(definition) && !rekey
          raise ArgumentError.new("#{asset_type} is registered differently: pass rekey: true to change it and re-key its assets")
        end
        unless stored == {definition, TraitKey::SCHEME} && own_index?(asset_type)
          write_transaction do |conn|
            save_type(conn, definition)
            changed = rekey(conn, definition)
            reindex_type(conn, asset_type) # labels may have changed
          end
        end
        @types[asset_type] = definition
      end
      changed.each { |id| @indexer.try(&.enqueue_asset(id)) }
      definition
    end

    # Keep an index on a registered type for this consumer's common lookups:
    # `traits` in the order it usually asks by. Apps just ask with traits:
    # a lookup fixing the leading traits of any index on the type (the
    # type's own, or any consumer's) can start from that range, and
    # DataDungeon starts from the narrowest (see `tag_filter`). Each consumer
    # names and changes only its own indexes, so open the store with
    # `consumer:`. Registering an index again changes nothing; other traits
    # raise unless `rekey: true`, which re-keys the type's assets in it.
    def register_index(asset_type : String, name : String, *, traits : Array(String),
                       rekey : Bool = false) : AssetIndex
      writable!
      consumer = own_consumer
      type = registered(asset_type)
      raise ArgumentError.new("index name #{name.inspect} must be lowercase words joined by '-'") unless name.matches?(LABEL)
      raise ArgumentError.new("#{name}: traits must not be empty") if traits.empty?
      raise ArgumentError.new("#{name}: a trait is listed twice") if traits.uniq.size != traits.size
      unless (unknown = traits.reject { |trait| type.trait?(trait) }).empty?
        raise ArgumentError.new("#{name}: #{unknown.join(", ")} are not traits of #{asset_type}")
      end
      @object_lock.synchronize do
        write_transaction do |conn|
          where, args = "asset_type = ? AND consumer = ? AND name = ?", [asset_type, consumer, name] of ::DB::Any
          if existing = query_indexes(conn, where, args).first?
            next existing if existing.traits == traits
            unless rekey
              raise ArgumentError.new("#{consumer}'s index #{name} on #{asset_type} is #{existing.traits.join(" ")}: " \
                                      "pass rekey: true to change it and re-key its assets")
            end
          end
          conn.exec(<<-SQL, asset_type, consumer, name, traits.to_json)
            INSERT INTO asset_indexes (asset_type, consumer, name, traits) VALUES (?, ?, ?, ?)
            ON CONFLICT (asset_type, consumer, name) DO UPDATE SET traits = excluded.traits
          SQL
          index = query_indexes(conn, where, args).first
          conn.exec("DELETE FROM asset_keys WHERE index_id = ?", index.id)
          ids = conn.query_all("SELECT id FROM assets WHERE asset_type = ?", asset_type, as: Int64)
          ids.each_slice(500) do |batch|
            tags = tags_batch(conn, batch)
            batch.each { |id| put_key(conn, index, id, tags[id]? || {} of String => String, type.labels) }
          end
          index
        end
      end
    end

    # Drop one of this consumer's indexes, and its keys. Returns whether
    # there was one.
    def unregister_index(asset_type : String, name : String) : Bool
      writable!
      consumer = own_consumer
      write_transaction do |conn|
        conn.exec("DELETE FROM asset_indexes WHERE asset_type = ? AND consumer = ? AND name = ?",
          asset_type, consumer, name).rows_affected > 0
      end
    end

    # Every consumer's indexes on a type (not the type's own).
    def indexes(asset_type : String) : Array(AssetIndex)
      query_indexes(@db, "asset_type = ? AND consumer <> ''", [asset_type] of ::DB::Any)
    end

    # Whether a type has its own index.
    private def own_index?(asset_type : String) : Bool
      !@db.query_one?("SELECT 1 FROM asset_indexes WHERE asset_type = ? AND consumer = '' AND name = ''",
        asset_type, as: Int64).nil?
    end

    private def query_indexes(db, where : String, args : Array(::DB::Any)) : Array(AssetIndex)
      db.query_all("SELECT id, asset_type, consumer, name, traits FROM asset_indexes WHERE #{where} ORDER BY id",
        args: args) do |rs|
        AssetIndex.new(rs.read(Int64), rs.read(String), rs.read(String), rs.read(String),
          Array(String).from_json(rs.read(String)))
      end
    end

    private def own_consumer : String
      @consumer || raise ArgumentError.new("Say which consumer this is: open the store with DB.new(path, consumer: \"...\")")
    end

    # The registration of an asset type, or nil when it has none.
    def registration(asset_type : String) : AssetType?
      @types[asset_type]?
    end

    # Rename an asset type: its assets, their tags and its registration move
    # to `to`. If `to` already has assets, these join them, under `to`'s
    # registration if it has one. A registered type's keys begin with its
    # name, so they're derived again. Returns the number of assets moved.
    # Once nothing of `from` is left, it changes nothing, so an app can keep
    # the call in its start-up (`@pirateship`).
    def rename_type(from : String, to : String) : Int32
      writable!
      return 0 if from == to
      unless to.matches?(TYPE_NAME)
        raise ArgumentError.new("asset type #{to.inspect} must be lowercase letters and digits, joined by '_' or '-'")
      end
      moved = [] of Int64
      rekeyed = [] of Int64
      @object_lock.synchronize do
        target = @types[to]? || @types[from]?.try { |type| type.renamed(to) }
        write_transaction do |conn|
          moved = conn.query_all("SELECT id FROM assets WHERE asset_type = ?", from, as: Int64)
          next if moved.empty? && %w[asset_types asset_indexes asset_tags].none? { |table|
                    conn.query_one?("SELECT 1 FROM #{table} WHERE asset_type = ? LIMIT 1", from, as: Int64)
                  }
          conn.exec("UPDATE assets SET asset_type = ? WHERE asset_type = ?", to, from)
          conn.exec("UPDATE asset_tags SET asset_type = ? WHERE asset_type = ?", to, from)
          conn.exec("DELETE FROM asset_types WHERE asset_type = ?", from)
          # Indexes move too, except where `to` has one of the same consumer and name.
          conn.exec("UPDATE OR IGNORE asset_indexes SET asset_type = ? WHERE asset_type = ?", to, from)
          conn.exec("DELETE FROM asset_indexes WHERE asset_type = ?", from)
          if target
            save_type(conn, target)
            rekeyed = rekey(conn, target)
          end
          reindex_type(conn, to)
        end
        @types.delete(from)
        @types[to] = target if target
      end
      (moved + rekeyed).uniq!.each { |id| @indexer.try(&.enqueue_asset(id)) }
      moved.size
    end

    # Rename a tag on every asset of a type, and in the type's registration
    # if it names it (a trait or a facet's tag). A registered type's keys are
    # derived again: they hold trait values, not names, so they normally stay
    # the same, but a type registered under the new name first gets its keys
    # right. Raises if an asset already has a tag named `to`. Returns the
    # number of assets whose tag was renamed.
    def rename_tag(asset_type : String, from : String, to : String) : Int32
      writable!
      return 0 if from == to
      check_tag_names({to => ""})
      renamed = [] of Int64
      rekeyed = [] of Int64
      @object_lock.synchronize do
        type = @types[asset_type]?
        updated = type.try(&.with_tag_renamed(from, to))
        updated.try { |definition| validate_type(definition) }
        write_transaction do |conn|
          clashes = conn.scalar(<<-SQL, asset_type, from, to).as(Int64)
            SELECT COUNT(*) FROM asset_tags a JOIN asset_tags b ON b.asset_id = a.asset_id
            WHERE a.asset_type = ? AND a.tag_key = ? AND b.tag_key = ?
          SQL
          raise ArgumentError.new("#{clashes} #{asset_type} assets already have a #{to} tag") if clashes > 0
          renamed = conn.query_all("SELECT asset_id FROM asset_tags WHERE asset_type = ? AND tag_key = ?",
            asset_type, from, as: Int64)
          conn.exec("UPDATE asset_tags SET tag_key = ? WHERE asset_type = ? AND tag_key = ?", to, asset_type, from)
          query_indexes(conn, "asset_type = ?", [asset_type] of ::DB::Any).each do |index|
            next unless index.traits.includes?(from)
            conn.exec("UPDATE asset_indexes SET traits = ? WHERE id = ?",
              index.traits.map { |trait| trait == from ? to : trait }.to_json, index.id)
          end
          if updated
            save_type(conn, updated) if updated != type
            rekeyed = rekey(conn, updated)
            reindex(conn, rekeyed)
          end
        end
        @types[asset_type] = updated if updated
      end
      (renamed + rekeyed).uniq!.each { |id| @indexer.try(&.enqueue_asset(id)) }
      renamed.size
    end

    # The key a registered type's own index gives these traits. Traits left
    # out are absent (an empty segment); names that aren't the type's traits
    # raise.
    def key_for(asset_type : String, traits : Hash(String, String)) : String
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
    # values dropped); other tags, and any tags of an unregistered type (one
    # stored before 0.12 required registering), as given.
    def normalize_tags(asset_type : String, tags : Hash(String, String)) : Hash(String, String)
      (type = @types[asset_type]?) ? normalize_traits(type, tags) : tags
    end

    # The current assets whose traits all equal these. Traits named in
    # `custom` may differ, leaving the
    # caller to rank them (e.g. semantically); every other trait matches
    # exactly, and a trait absent from `traits` must be absent on the asset.
    # Without `custom` this is one key lookup in the type's own index. With
    # it, the traits before the first custom one narrow the candidates by key
    # prefix, and the rest are
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
      clause, args = key_clause(type.name, type.prefix(values, lead), prefix: true)
      clauses = [clause]
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

    # Every current asset with this key in its type's own index. A key names
    # its type, so the key alone is enough.
    def find_pool(key : String) : Array(AssetRecord)
      clause, args = key_clause(TraitKey.type_of(key), key)
      query_assets(clause, args)
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

    # Every asset whose key in its type's own index starts with this prefix,
    # which must end at a separator (as group_key_for's do); `portrait.` is
    # the whole type.
    def find_group(prefix : String) : Array(AssetRecord)
      unless prefix.ends_with?(TraitKey::SEPARATOR)
        raise ArgumentError.new("a key prefix must end with #{TraitKey::SEPARATOR.inspect}")
      end
      clause, args = key_clause(TraitKey.type_of(prefix), prefix, prefix: true)
      query_assets(clause, args)
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

    # A clause (alias `a`) for the assets with this key in their type's own
    # index, or with a key starting with this prefix: one range of
    # asset_keys, from `prefix` up to, not including, the prefix with its
    # final separator raised by one ('.' to '/').
    # :nodoc:
    def key_clause(asset_type : String, key : String, *, prefix : Bool = false) : {String, Array(::DB::Any)}
      args = [asset_type] of ::DB::Any
      range = if prefix
                args << key << key.rchop + TraitKey::SEPARATOR.succ
                "k.key >= ? AND k.key < ?"
              else
                args << key
                "k.key = ?"
              end
      {"a.id IN (SELECT k.asset_id FROM asset_keys k WHERE k.index_id = #{OWN_INDEX} AND #{range})", args}
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

    private def query_assets(where : String, args : Array(::DB::Any), retired : Bool = false) : Array(AssetRecord)
      where = "(#{where}) AND a.retired_at IS NULL" unless retired
      results = [] of AssetRecord
      @db.query("SELECT #{ASSET_COLUMNS} FROM assets a WHERE #{where} ORDER BY a.id", args: args) do |rs|
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
      writable!
      if type = @types[asset_type]?
        value = normalize_traits(type, {trait => value})[trait]? || value
      end
      @db.exec(<<-SQL, asset_type, trait, value).rows_affected
        UPDATE asset_tags SET custom = 0
        WHERE asset_type = ? AND tag_key = ? AND tag_value = ? AND custom = 1
      SQL
    end

    # A type's registration, also when another process registered it since
    # this one opened; raises for a type that has none.
    private def registered(asset_type : String) : AssetType
      @types[asset_type]? || stored_type(asset_type).try { |(type, _)| @types[asset_type] = type } ||
        raise ArgumentError.new("#{asset_type} is not a registered asset type (see register_type)")
    end

    private def validate_type(type : AssetType) : Nil
      name = type.name
      unless name.matches?(TYPE_NAME)
        raise ArgumentError.new("asset type #{name.inspect} must be lowercase letters and digits, joined by '_' or '-'")
      end
      raise ArgumentError.new("#{name}: pool_traits must not be empty") if type.pool_traits.empty?
      (type.pool_traits + type.group_traits).each do |trait|
        unless trait.matches?(TRAIT_NAME)
          raise ArgumentError.new("#{name}: trait #{trait.inspect} must be lowercase letters and digits, joined by '_' or '-'")
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
        raise ArgumentError.new("#{name}: #{trait} is a set, which can't be labelled") if type.set?(trait)
      end
      type.sets.each do |trait|
        raise ArgumentError.new("#{name}: set #{trait} is not a pool trait") unless type.trait?(trait)
      end
      raise ArgumentError.new("#{name}: a set is listed twice") if type.sets.uniq.size != type.sets.size
      type.facets.each do |facet, tags|
        unless facet.matches?(LABEL)
          raise ArgumentError.new("#{name}: facet #{facet.inspect} must be lowercase words joined by '-'")
        end
        raise ArgumentError.new("#{name}: facet #{facet} names no tags") if tags.empty?
        raise ArgumentError.new("#{name}: facet #{facet} lists a tag twice") if tags.uniq.size != tags.size
        tags.each do |tag|
          unless tag.matches?(TRAIT_NAME)
            raise ArgumentError.new("#{name}: facet #{facet} tag #{tag.inspect} must be lowercase letters and digits, joined by '_' or '-'")
          end
        end
      end
      type.scales.each do |trait, values|
        raise ArgumentError.new("#{name}: scale #{trait} is not a pool trait") unless type.trait?(trait)
        raise ArgumentError.new("#{name}: #{trait} is a set, which can't be a scale") if type.set?(trait)
        raise ArgumentError.new("#{name}: scale #{trait} needs at least two values") if values.size < 2
        raise ArgumentError.new("#{name}: scale #{trait} lists a value twice") if values.uniq.size != values.size
      end
      type.colors.each do |trait|
        raise ArgumentError.new("#{name}: color #{trait} is not a pool trait") unless type.trait?(trait)
        raise ArgumentError.new("#{name}: #{trait} is a set or a scale, which can't be a color") if type.set?(trait) || type.scales.has_key?(trait)
      end
      raise ArgumentError.new("#{name}: a color is listed twice") if type.colors.uniq.size != type.colors.size
      type.cycles.each do |trait, values|
        raise ArgumentError.new("#{name}: cycle #{trait} is not a pool trait") unless type.trait?(trait)
        if type.set?(trait) || type.scales.has_key?(trait) || type.colors.includes?(trait)
          raise ArgumentError.new("#{name}: #{trait} is a set, a scale or a color, which can't be a cycle")
        end
        raise ArgumentError.new("#{name}: cycle #{trait} needs at least three values") if values.size < 3
        raise ArgumentError.new("#{name}: cycle #{trait} lists a value twice") if values.uniq.size != values.size
      end
      unless (unknown = type.match_fields - AssetType::MATCH_FIELDS).empty?
        raise ArgumentError.new("#{name}: #{unknown.join(", ")} can't be matched on: #{AssetType::MATCH_FIELDS.join(", ")} can")
      end
      raise ArgumentError.new("#{name}: a match field is listed twice") if type.match_fields.uniq.size != type.match_fields.size
      type.weights.each do |trait, weight|
        unless type.trait?(trait) || type.match_fields.includes?(trait)
          raise ArgumentError.new("#{name}: weight #{trait} is not a pool trait or a match field")
        end
        raise ArgumentError.new("#{name}: weight #{trait} must be positive") unless weight > 0 && weight.finite?
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
        elsif normal = (type.set?(key) ? TraitKey.normalize_set(value) : TraitKey.normalize(value))
          normalized[key] = normal
        end
      end
      normalized
    end

    private def save_type(conn, type : AssetType) : Nil
      conn.exec(
        <<-SQL,
        INSERT INTO asset_types
        (asset_type, pool_traits, group_traits, labels, sets, facets, key_scheme, scales, colors, weights,
         cycles, match_fields)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(asset_type) DO UPDATE SET pool_traits = excluded.pool_traits,
          group_traits = excluded.group_traits, labels = excluded.labels,
          sets = excluded.sets, facets = excluded.facets, key_scheme = excluded.key_scheme,
          scales = excluded.scales, colors = excluded.colors, weights = excluded.weights,
          cycles = excluded.cycles, match_fields = excluded.match_fields
      SQL
        type.name, type.pool_traits.to_json, type.group_traits.to_json,
        type.labels.to_json, type.sets.to_json, type.facets.to_json, TraitKey::SCHEME, type.scales.to_json, type.colors.to_json, type.weights.to_json,
        type.cycles.to_json, type.match_fields.to_json
      )
    end

    private def stored_type(asset_type : String) : {AssetType, Int32}?
      @db.query_one?(
        "SELECT asset_type, pool_traits, group_traits, labels, sets, facets, key_scheme, scales, colors, weights, cycles, match_fields FROM asset_types WHERE asset_type = ?",
        asset_type
      ) { |rs| read_type(rs) }
    end

    private def read_type(rs) : {AssetType, Int32}
      name = rs.read(String)
      pool_traits = Array(String).from_json(rs.read(String))
      group_traits = Array(String).from_json(rs.read(String))
      labels = Hash(String, String).from_json(rs.read(String))
      sets = Array(String).from_json(rs.read(String))
      facets = Hash(String, Array(String)).from_json(rs.read(String))
      scheme = rs.read(Int32)
      scales = Hash(String, Array(String)).from_json(rs.read(String))
      colors = Array(String).from_json(rs.read(String))
      weights = Hash(String, Float64).from_json(rs.read(String))
      cycles = Hash(String, Array(String)).from_json(rs.read(String))
      match_fields = Array(String).from_json(rs.read(String))
      {AssetType.new(name, pool_traits, group_traits, labels, sets, facets, scales, colors, weights,
        cycles, match_fields), scheme}
    end

    # Registrations made with an older key encoding, or lacking their own
    # index, are re-keyed on open.
    private def load_types : Nil
      rows = @db.query_all(
        "SELECT asset_type, pool_traits, group_traits, labels, sets, facets, key_scheme, scales, colors, weights, cycles, match_fields FROM asset_types"
      ) { |rs| read_type(rs) }
      rows.each do |type, scheme|
        @types[type.name] = type
        unless scheme == TraitKey::SCHEME && own_index?(type.name)
          raise ReadOnlyError.new("#{type.name}'s keys need re-keying: open the database read-write once first") if @read_only
          write_transaction do |conn|
            reindex(conn, rekey(conn, type))
            conn.exec("UPDATE asset_types SET key_scheme = ? WHERE asset_type = ?", TraitKey::SCHEME, type.name)
          end
        end
      end
    end

    # Re-derive every asset of a type's key in the type's own index (made
    # or changed to the registration's order) from its tags, normalizing the
    # stored trait values on the way. Returns the assets whose tags changed.
    private def rekey(conn, type : AssetType) : Array(Int64)
      ids = conn.query_all("SELECT id FROM assets WHERE asset_type = ? ORDER BY id", type.name, as: Int64)
      conn.exec(<<-SQL, type.name, type.pool_traits.to_json)
        INSERT INTO asset_indexes (asset_type, consumer, name, traits) VALUES (?, '', '', ?)
        ON CONFLICT (asset_type, consumer, name) DO UPDATE SET traits = excluded.traits
      SQL
      index = query_indexes(conn, "asset_type = ? AND consumer = '' AND name = ''", [type.name] of ::DB::Any).first
      conn.exec("DELETE FROM asset_keys WHERE index_id = ?", index.id)
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
          conn.exec("INSERT INTO asset_keys (asset_id, index_id, key) VALUES (?, ?, ?)", id, index.id, type.key(normalized))
        end
      end
      changed
    end

    # ── Touch ──

    # Counts a use of the asset (`last_used_at`, `use_count`), as `get` does
    # unless told `touch: false`. The count is kept in memory, so a read
    # doesn't wait on a disk sync. Every USAGE_WRITE_AT uses are written in
    # one transaction, if the write lock is free (if not, ten uses later),
    # and the rest at close, when the process exits, or by flush_usage.
    # Until then a record shows the counts as last written, and a process
    # killed outright loses those not yet written: they're a hint for
    # eviction, not a record of plays.
    def touch_asset(id : Int64) : Nil
      return if @read_only
      now = Time.utc
      full = @usage_lock.synchronize do
        uses = @usage[id]?.try(&.[0]) || 0
        @usage[id] = {uses + 1, now}
        (@usage_count += 1) >= @usage_try_at
      end
      flush_usage(wait: false) if full
    end

    # Writes the uses counted since the last write (touch_asset). With
    # `wait: false`, gives up at once if another connection holds the write
    # lock, keeping the counts for later. Returns whether they were written.
    def flush_usage(wait : Bool = true) : Bool
      return true if @read_only || @usage_lock.synchronize { @usage.empty? }
      @db.using_connection do |conn|
        conn.exec("PRAGMA busy_timeout = 0") unless wait
        begin
          immediate(conn) { write_usage(conn) }
          true
        rescue ex : SQLite3::Exception
          raise ex unless ex.code == LibSQLite3::Code::BUSY.value
          @usage_lock.synchronize { @usage_try_at = @usage_count + USAGE_WRITE_AT // 10 }
          false
        ensure
          conn.exec("PRAGMA busy_timeout = #{BUSY_TIMEOUT_MS}") unless wait
        end
      end
    end

    # Writes the waiting uses, inside a write transaction. If writing fails,
    # they wait again.
    private def write_usage(conn : ::DB::Connection) : Nil
      usage = @usage_lock.synchronize do
        taken = @usage
        @usage = {} of Int64 => {Int32, Time}
        @usage_count = 0
        @usage_try_at = USAGE_WRITE_AT
        taken
      end
      begin
        usage.each do |id, (uses, last)|
          conn.exec("UPDATE assets SET last_used_at = ?, use_count = use_count + ? WHERE id = ?",
            last.to_s(TIME_FORMAT), uses, id)
        end
      rescue ex
        @usage_lock.synchronize do
          usage.each do |id, (uses, last)|
            later = @usage[id]?
            @usage[id] = later ? {uses + later[0], later[1]} : {uses, last}
            @usage_count += uses
          end
        end
        raise ex
      end
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

    # The image fields of these assets, those that have them, in one query.
    def load_image_meta_batch(ids : Array(Int64)) : Hash(Int64, ImageMeta)
      found = {} of Int64 => ImageMeta
      ids.each_slice(500) do |batch|
        @db.query(<<-SQL, args: batch.map(&.as(::DB::Any))) do |rs|
          SELECT im.asset_id, #{IMAGE_SELECT} FROM image_meta im
          LEFT JOIN image_animation ia ON ia.asset_id = im.asset_id
          WHERE im.asset_id IN (#{Array.new(batch.size, "?").join(", ")})
        SQL
          rs.each { found[rs.read(Int64)] = read_image_meta_join(rs).not_nil! }
        end
      end
      found
    end

    def load_image_meta(asset_id : Int64) : ImageMeta?
      @db.query_one?(<<-SQL, asset_id) { |rs| read_image_meta_join(rs) }
        SELECT #{IMAGE_SELECT} FROM image_meta im
        LEFT JOIN image_animation ia ON ia.asset_id = im.asset_id WHERE im.asset_id = ?
      SQL
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
      writable!
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
      write_transaction do |conn|
        unindex_search(conn, id)
        log_change(conn, id)
        conn.exec("DELETE FROM assets WHERE id = ?", id)
      end
    end

    # Record that an asset changed or went (asset_changes), keeping only the
    # latest CHANGES_KEPT.
    private def log_change(conn, id : Int64) : Nil
      conn.exec("INSERT INTO asset_changes (asset_id) VALUES (?)", id)
      seq = conn.scalar("SELECT last_insert_rowid()").as(Int64)
      conn.exec("DELETE FROM asset_changes WHERE seq <= ?", seq - CHANGES_KEPT) if seq % 1000 == 0
    end

    # Replace an animation's checkpoints (see ImageKeyframe), in time order,
    # each after its start and within its duration. Neighbouring views,
    # starting from the first frame's, may be at most 90 degrees apart, or
    # which way round it turns would be ambiguous; and a checkpoint goes
    # wherever something turns (the top of a jump), so values move only one
    # way between them and a filter at the checkpoints is exact. For an
    # animated WebP, DataDungeon measures the content box at each one,
    # keeping it where it differs from the one before.
    def set_keyframes(id : Int64, keyframes : Array(ImageKeyframe)) : Array(ImageKeyframe)
      writable!
      rec = find_asset_by_id(id) || raise ArgumentError.new("No asset #{id}")
      meta = load_image_meta(id)
      animation = meta.try(&.animation) || raise ArgumentError.new("Asset #{id} isn't an animation")
      keyframes = keyframes.sort_by(&.at_ms)
      keyframes.each_cons_pair do |before, after|
        raise ArgumentError.new("two checkpoints at #{after.at_ms} ms") if before.at_ms == after.at_ms
      end
      keyframes.each do |keyframe|
        raise ArgumentError.new("a checkpoint comes after the start, not at #{keyframe.at_ms} ms") unless keyframe.at_ms > 0
        if (duration = animation.duration_ms) && keyframe.at_ms > duration
          raise ArgumentError.new("a checkpoint at #{keyframe.at_ms} ms is past the end (#{duration} ms)")
        end
        {keyframe.anchor_x, keyframe.anchor_y}.each do |anchor|
          raise ArgumentError.new("an anchor is 0 to 1 across or down") if anchor && !(0.0 <= anchor <= 1.0)
        end
      end
      view = meta.try { |m| unit_or_nil("view", m.view_x, m.view_y, m.view_z) }
      keyframes.each do |keyframe|
        next unless found = unit_or_nil("view", keyframe.view_x, keyframe.view_y, keyframe.view_z)
        if view && view[0] * found[0] + view[1] * found[1] + view[2] * found[2] < -1e-9
          raise ArgumentError.new("the view at #{keyframe.at_ms} ms turns more than 90 degrees from the one before: " \
                                  "add a checkpoint between")
        end
        view = found
      end
      keyframes = with_content(rec, meta.not_nil!, keyframes)

      write_transaction do |conn|
        conn.exec("DELETE FROM image_keyframes WHERE asset_id = ?", id)
        keyframes.each do |keyframe|
          view = unit_or_nil("view", keyframe.view_x, keyframe.view_y, keyframe.view_z)
          light = unit_or_nil("light", keyframe.light_x, keyframe.light_y, keyframe.light_z)
          conn.exec(<<-SQL, id, keyframe.at_ms, keyframe.held? ? 1 : 0, view.try(&.[0]), view.try(&.[1]), view.try(&.[2]),
            INSERT INTO image_keyframes (asset_id, at_ms, held, view_x, view_y, view_z, view_roll,
              light_x, light_y, light_z, anchor_x, anchor_y, content_x, content_y, content_w, content_h)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
            keyframe.view_roll, light.try(&.[0]), light.try(&.[1]), light.try(&.[2]), keyframe.anchor_x, keyframe.anchor_y,
            keyframe.content_x, keyframe.content_y, keyframe.content_w, keyframe.content_h)
        end
        log_change(conn, id)
      end
      load_keyframes(id)
    end

    # An animated WebP's content box at each checkpoint, where it differs
    # from the one before (the first frame's to start).
    private def with_content(rec : AssetRecord, meta : ImageMeta, keyframes : Array(ImageKeyframe)) : Array(ImageKeyframe)
      return keyframes unless rec.content_type == "image/webp" && !keyframes.empty?
      frames = begin
        ImageProbe.decode_webp_frames(read(rec), keyframes.map(&.at_ms))
      rescue ImageProbe::Error | File::NotFoundError
        return keyframes
      end
      boxes = frames.to_h { |(at, (width, height, pixels))| {at, ImageProbe.content_box(width, height, pixels)} }
      before = {meta.content_x, meta.content_y, meta.content_w, meta.content_h}
      keyframes.map do |keyframe|
        box = boxes[keyframe.at_ms]?
        next keyframe unless box && box != before
        before = box
        keyframe.with_content(box)
      end
    end

    # An animation's checkpoints, in time order.
    def load_keyframes(id : Int64) : Array(ImageKeyframe)
      @db.query_all(<<-SQL, id) do |rs|
        SELECT at_ms, held, view_x, view_y, view_z, view_roll, light_x, light_y, light_z, anchor_x, anchor_y,
          content_x, content_y, content_w, content_h FROM image_keyframes WHERE asset_id = ? ORDER BY at_ms
      SQL
        ImageKeyframe.new(rs.read(Int32), rs.read(Int32) != 0, view_x: rs.read(Float64?), view_y: rs.read(Float64?),
          view_z: rs.read(Float64?), view_roll: rs.read(Float64?), light_x: rs.read(Float64?), light_y: rs.read(Float64?),
          light_z: rs.read(Float64?), anchor_x: rs.read(Float64?), anchor_y: rs.read(Float64?),
          content_x: rs.read(Int32?), content_y: rs.read(Int32?), content_w: rs.read(Int32?), content_h: rs.read(Int32?))
      end
    end

    # The image fields best matches use (AssetType::MATCH_FIELDS) of these
    # assets, as text: a view or light as its unit vector `x,y,z`, a roll in
    # quarter turns, a dominant colour as `rrggbb`. Fields not known are left
    # out.
    def match_field_values(ids : Array(Int64)) : Hash(Int64, Hash(String, String))
      found = {} of Int64 => Hash(String, String)
      ids.each_slice(500) do |batch|
        @db.query(<<-SQL, args: batch.map(&.as(::DB::Any))) do |rs|
          SELECT asset_id, view_x, view_y, view_z, view_roll, light_x, light_y, light_z, dominant_color
          FROM image_meta WHERE asset_id IN (#{Array.new(batch.size, "?").join(", ")})
        SQL
          rs.each do
            values = found[rs.read(Int64)] = {} of String => String
            view = {rs.read(Float64?), rs.read(Float64?), rs.read(Float64?)}
            roll = rs.read(Float64?)
            light = {rs.read(Float64?), rs.read(Float64?), rs.read(Float64?)}
            color = rs.read(Int32?)
            values["view"] = view.join(",") { |x| x.not_nil!.round(3) } if view.all?
            values["roll"] = roll.round(3).to_s if roll
            values["light"] = light.join(",") { |x| x.not_nil!.round(3) } if light.all?
            values["dominant-color"] = "%06x" % color if color
          end
        end
      end
      found
    end

    # Measure the stored pictures DataDungeon hasn't read yet (stored before
    # it measured them, or through store_asset), or with `all` every one,
    # of one type or all. Each object is read from storage: for a bucket, a
    # download. A file outside the store, or an object gone, is left as it
    # is. Returns how many were read.
    def measure_images(asset_type : String? = nil, all : Bool = false) : Int32
      writable!
      where = "a.media = 'image' AND a.content_type LIKE 'image/%' AND a.file_path NOT LIKE '/%'"
      where += " AND im.measured IS NOT 1" unless all
      args = [] of ::DB::Any
      if asset_type
        where += " AND a.asset_type = ?"
        args << asset_type
      end
      ids = @db.query_all("SELECT a.id FROM assets a LEFT JOIN image_meta im ON im.asset_id = a.id WHERE #{where} ORDER BY a.id",
        args: args, as: Int64)
      ids.count do |id|
        rec = find_asset_by_id(id) || next false
        data = begin
          read(rec)
        rescue File::NotFoundError
          next false
        end
        found = ImageProbe.measure(data, rec.content_type)
        write_transaction do |conn|
          conn.exec("INSERT OR IGNORE INTO image_meta (asset_id) VALUES (?)", id)
          if found
            x, y, w, h = found.content || {nil, nil, nil, nil}
            conn.exec(<<-SQL, found.width, found.height, found.transparent.try { |t| t ? 1 : 0 }, found.dominant_color, x, y, w, h, id)
              UPDATE image_meta SET width = ?, height = ?, transparent = ?, dominant_color = ?,
                content_x = ?, content_y = ?, content_w = ?, content_h = ?, measured = 1 WHERE asset_id = ?
            SQL
            found.animation.try do |animation|
              given = load_image_meta(id).try(&.animation)
              put_animation(conn, id, given.try(&.merged(animation)) || animation)
            end
          else
            conn.exec("UPDATE image_meta SET measured = 1 WHERE asset_id = ?", id)
          end
          log_change(conn, id)
        end
        true
      end
    end

    # ── Consistency sweep (fsck / vacuum) ──

    # Every object key this store's rows use, retired assets' included: what
    # a program clearing a shared bucket keeps (Storage#shared?).
    def object_keys : Array(String)
      @db.query_all("SELECT DISTINCT file_path FROM assets ORDER BY file_path", as: String)
    end

    # Report-only reconciliation of the index against the storage backend.
    # Walks both directions of divergence: rows whose object is missing, and
    # stored objects with no owning row (leaked blobs — e.g. from deletes made
    # before v0.3.4, when delete_asset didn't unlink). Changes nothing. In
    # shared storage, other stores' objects are among those with no row here.
    def check_consistency : ConsistencyReport
      store = @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"

      # One listing of the backend, compared with the rows, rather than a
      # check per row: on remote storage each check is a round trip.
      stored = store.list_keys.to_set
      indexed = Set(String).new
      missing_ids = [] of Int64
      # Collect first; don't issue nested queries while this cursor is open.
      @db.query("SELECT id, file_path FROM assets") do |rs|
        rs.each do
          id = rs.read(Int64)
          path = rs.read(String)
          indexed << path
          missing_ids << id unless stored.includes?(path)
        end
      end

      missing = missing_ids.compact_map { |id| find_asset_by_id(id) }
      orphans = stored.reject { |key| indexed.includes?(key) }.sort
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
      writable! if delete_missing_rows || delete_orphan_objects
      store = @storage || raise "DataDungeon::DB has no storage backend; construct with cache_root: or storage:"
      if delete_orphan_objects && store.shared?
        raise ArgumentError.new("the storage is shared: an object this store doesn't use may be another's")
      end
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
      return @db.scalar("SELECT COUNT(*) FROM assets WHERE asset_type = ? AND retired_at IS NULL", asset_type).as(Int64).to_i32 if filter_tags.empty?
      from, where, args = tag_filter(asset_type, filter_tags) || return 0

      @db.scalar("SELECT COUNT(*) FROM #{from} WHERE #{where} AND a.retired_at IS NULL", args: args).as(Int64).to_i32
    end

    def random_pool_text(asset_type : String, filter_tags : Hash(String, String)) : String?
      filter_tags = normalize_tags(asset_type, filter_tags)
      if filter_tags.empty?
        return @db.query_one?(
          <<-SQL,
            SELECT tm.content FROM assets a
            JOIN text_meta tm ON tm.asset_id = a.id
            WHERE a.asset_type = ? AND a.retired_at IS NULL
            ORDER BY RANDOM() LIMIT 1
          SQL
          asset_type
        ) { |rs| rs.read(String) }
      end
      from, where, args = tag_filter(asset_type, filter_tags) || return nil

      @db.query_one?(
        "SELECT tm.content FROM #{from} JOIN text_meta tm ON tm.asset_id = a.id WHERE #{where} AND a.retired_at IS NULL ORDER BY RANDOM() LIMIT 1",
        args: args
      ) { |rs| rs.read(String) }
    end

    # How many rows of a key range to count when judging where a tag filter
    # starts; past this its size is estimated.
    RAREST_PROBE = 1000

    # Where a tag filter starts reading: a range of keys in an index (the
    # type's own, or a consumer's), one tag's rows, or the type's
    # newest assets. The traits it covers need no other check; `rows` is
    # how many rows it reads, when known without counting.
    private record Start, table : String, where : String, args : Array(::DB::Any), id : String,
      covered : Array(String), rows : Int64? = nil

    START_COST    =  1.9 # microseconds to read one row of a start, check it and sort it
    TAG_WALK_COST = 0.75 # microseconds to check one asset on a walk through the newest

    # FROM and WHERE (alias `a`) for "assets of this type carrying every one
    # of these normalized tags", or nil when none can, for a listing that
    # wants `reach` assets (nil: all of them). As a query planner would, it
    # starts from whichever place reads fewest rows: the range of each index
    # whose leading traits the filter fixes (the type's own key, and every
    # consumer's), or one tag's rows (counts kept in asset_tag_counts), then
    # checks the other tags on each asset there by primary key. For a page,
    # walking the type's newest assets and checking every tag can cost
    # less: tags common together fill a page soon. A long prefix of common
    # values (`rating pg`) can hold more than one rare tag does, so ranges
    # are counted too, capped so counting stays cheap.
    private def tag_filter(asset_type : String, filter : Hash(String, String),
                           reach : Int32? = nil) : {String, String, Array(::DB::Any)}?
      total = tag_count(asset_type, "", "")
      counts = filter.to_h { |key, value| {key, tag_count(asset_type, key, value)} }
      return nil if counts.empty? || counts.values.any?(&.zero?) # some tag is on no asset

      starts = filter_starts(asset_type, filter, counts)
      sizes = starts.map { |start| start_size(start, counts, total) }
      start, size = starts.zip(sizes).min_by(&.[1])
      if reach
        share = counts.values.product(1.0) { |count| count / total } # taking the tags as independent
        if reach / share * TAG_WALK_COST < size * START_COST
          start = Start.new("assets a", "a.asset_type = ?", [asset_type] of ::DB::Any, "a.id", [] of String)
        end
      end

      from = start.table
      clauses = [start.where]
      args = start.args.dup
      unless from == "assets a"
        # CROSS JOIN keeps SQLite from reordering: the start's range drives.
        from = "#{start.table} CROSS JOIN assets a"
        clauses << "a.id = #{start.id}"
      end
      filter.each do |key, value|
        next if start.covered.includes?(key)
        # Checked from the start's row, before reading the asset.
        clauses << "EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = #{start.id} AND t.tag_key = ? AND t.tag_value = ?)"
        args << key << value
      end
      {from, clauses.join(" AND "), args}
    end

    # How many of a type's assets, current and retired, carry this tag (the
    # empty tag: how many the type has).
    private def tag_count(asset_type : String, key : String, value : String) : Int64
      @db.query_one?("SELECT current + retired FROM asset_tag_counts WHERE asset_type = ? AND tag_key = ? AND tag_value = ?",
        asset_type, key, value, as: Int64) || 0_i64
    end

    private def filter_starts(asset_type : String, filter : Hash(String, String), counts : Hash(String, Int64)) : Array(Start)
      starts = [] of Start
      if type = @types[asset_type]?
        query_indexes(@db, "asset_type = ?", [asset_type] of ::DB::Any).each do |index|
          key_start(type, index, filter).try { |start| starts << start }
        end
      end
      filter.each do |key, value|
        starts << Start.new("asset_tags x", "x.asset_type = ? AND x.tag_key = ? AND x.tag_value = ?",
          [asset_type, key, value] of ::DB::Any, "x.asset_id", [key], counts[key])
      end
      starts
    end

    # How many rows a start reads: known for a tag; for a range, counted up
    # to RAREST_PROBE, and past that estimated from its traits' shares of the
    # type, as if independent.
    private def start_size(start : Start, counts : Hash(String, Int64), total : Int64) : Float64
      if rows = start.rows
        return rows.to_f
      end
      rows = start_count(start, RAREST_PROBE)
      return rows.to_f if rows < RAREST_PROBE
      Math.max(RAREST_PROBE.to_f, start.covered.product(total.to_f) { |trait| counts[trait] / total })
    end

    # The range of an index's keys holding the filter's values for as many
    # leading traits as it fixes (the whole key when it fixes them all), or
    # nil when it doesn't fix the first.
    private def key_start(type : AssetType, index : AssetIndex, filter : Hash(String, String)) : Start?
      traits = index.traits
      lead = traits.take_while { |trait| filter.has_key?(trait) }.size
      return nil if lead == 0
      args = [index.id] of ::DB::Any
      range = if lead == traits.size
                args << TraitKey.key(type.name, traits, filter, type.labels)
                "k.key = ?"
              else
                prefix = TraitKey.prefix(type.name, traits, filter, lead, type.labels)
                args << prefix << prefix.rchop + TraitKey::SEPARATOR.succ
                "k.key >= ? AND k.key < ?"
              end
      Start.new("asset_keys k", "k.index_id = ? AND #{range}", args, "k.asset_id", traits[0, lead])
    end

    # How many rows a start reads (retired assets too), counted up to `cap`.
    private def start_count(start : Start, cap : Int32) : Int64
      @db.scalar("SELECT COUNT(*) FROM (SELECT 1 FROM #{start.table} WHERE #{start.where} LIMIT ?)",
        args: start.args + [cap] of ::DB::Any).as(Int64)
    end

    # ── Eviction helpers ──

    def eviction_candidates(limit : Int32 = 100) : Array(AssetRecord)
      results = [] of AssetRecord
      @db.query(
        <<-SQL,
          SELECT #{ASSET_COLUMNS} FROM assets a
          WHERE a.permanent = 0
          ORDER BY a.last_used_at ASC NULLS FIRST
          LIMIT ?
        SQL
        limit
      ) do |rs|
        rs.each { results << read_asset_record(rs) }
      end
      results
    end

    # ── Internal ──

    # Read IMAGE_SELECT's columns. Returns nil when the LEFT JOIN produced
    # no image_meta row (asset_id NULL).
    private def read_image_meta_join(rs) : ImageMeta?
      asset_id = rs.read(Int64?)
      if asset_id.nil?
        # Consume the remaining NULL meta columns so the row cursor stays aligned.
        (IMAGE_COLUMNS.size + 1 + ANIMATION_COLUMNS.size).times { rs.read(::DB::Any) }
        return nil
      end
      fields = {
        width: rs.read(Int32?), height: rs.read(Int32?), usage_class: rs.read(String?),
        compression: rs.read(String?) || "original", quality_floor: rs.read(Int32?), max_colors: rs.read(Int32?),
        target_format: rs.read(String?), presentation: rs.read(String?),
        transparent: rs.read(Int32?).try(&.!=(0)), dominant_color: rs.read(Int32?),
        content_x: rs.read(Int32?), content_y: rs.read(Int32?), content_w: rs.read(Int32?), content_h: rs.read(Int32?),
        measured: rs.read(Int32?) == 1,
        view_x: rs.read(Float64?), view_y: rs.read(Float64?), view_z: rs.read(Float64?), view_roll: rs.read(Float64?),
        light_x: rs.read(Float64?), light_y: rs.read(Float64?), light_z: rs.read(Float64?),
        anchor_x: rs.read(Float64?), anchor_y: rs.read(Float64?),
        world_width: rs.read(Float64?), world_height: rs.read(Float64?), world_depth: rs.read(Float64?),
      }
      animated = rs.read(Int64?)
      animation = ImageAnimation.new(rs.read(Int32?), rs.read(Int32?), rs.read(Int32?), rs.read(Int32?),
        rs.read(Int32?), rs.read(Int32?))
      ImageMeta.new(**fields, animation: animated ? animation : nil)
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
        key: rs.read(String?),
        file_hash: rs.read(String?),
        created_at: rs.read(String),
        last_used_at: rs.read(String?),
        use_count: (rs.read(Int32?) || 0),
        permanent: (rs.read(Int32?) || 0) != 0,
        generator: rs.read(String?),
        generation: rs.read(String?),
        description: rs.read(String?),
        description_hash: rs.read(String?),
        generated: (rs.read(Int32?) || 0) != 0,
        rating: rs.read(Int32?),
        flagged: (rs.read(Int32?) || 0) != 0,
        made_at: rs.read(String?),
        retired_at: rs.read(String?),
        has_recipe: rs.read(Int64) != 0,
      )
    end
  end
end
