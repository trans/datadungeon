require "sqlite3"

module DataDungeon
  class DB
    include PortraitIndex
    include RaceRegistry

    @db : ::DB::Database

    def initialize(path : String)
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      @db = ::DB.open("sqlite3://#{path}")
      setup_schema
    end

    def close : Nil
      @db.close
    end

    private def setup_schema : Nil
      @db.exec("PRAGMA journal_mode=WAL")
      # Migration: portrait_index v2 uses measurement buckets instead of height/build strings
      migrate_portrait_index_v2
      @db.exec(PORTRAIT_INDEX_SCHEMA)
      @db.exec(RACE_SCHEMA)
      @db.exec(RACE_MEASUREMENTS_SCHEMA)
      @db.exec(RACE_OPTIONS_SCHEMA)
      # Migration: race_options gained a gender column (must run before seed)
      migrate_race_options_gender
      seed_races
    end

    private def migrate_portrait_index_v2 : Nil
      # Check if old schema has 'height TEXT' column (v1) — drop and let it recreate
      has_old_height = false
      begin
        @db.query("PRAGMA table_info(portrait_index)") do |rs|
          rs.each do
            _cid = rs.read(Int32)
            name = rs.read(String)
            col_type = rs.read(String?)
            if name == "height" && col_type.try(&.upcase) == "TEXT"
              has_old_height = true
            end
            rs.read(Int32)    # notnull
            rs.read(String?)  # dflt_value
            rs.read(Int32)    # pk
          end
        end
      rescue
        # Table doesn't exist yet — nothing to migrate
        return
      end
      return unless has_old_height
      @db.exec("DROP TABLE IF EXISTS portrait_index")
    end

    private def migrate_race_options_gender : Nil
      has_gender = false
      @db.query("PRAGMA table_info(race_options)") do |rs|
        rs.each do
          _cid = rs.read(Int32)
          name = rs.read(String)
          has_gender = true if name == "gender"
          rs.read(String?)  # type
          rs.read(Int32)    # notnull
          rs.read(String?)  # dflt_value
          rs.read(Int32)    # pk
        end
      end
      return if has_gender

      @db.exec("DROP TABLE IF EXISTS race_options")
      @db.exec(RACE_OPTIONS_SCHEMA)
      seed_races # re-seed to populate with gender-aware options
    end
  end
end
