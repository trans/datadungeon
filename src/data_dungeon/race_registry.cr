require "yaml"

module DataDungeon
  struct RaceRow
    getter id : String
    getter name : String
    getter description : String?
    getter builtin : Bool
    getter created_by : String?
    getter created_at : Time
    getter updated_at : Time

    def initialize(
      @id : String,
      @name : String,
      @description : String? = nil,
      @builtin : Bool = false,
      @created_by : String? = nil,
      @created_at : Time = Time.utc,
      @updated_at : Time = Time.utc,
    )
    end
  end

  struct RaceMeasurement
    getter race_id : String
    getter gender : String
    getter measurement : String
    getter range_min : Float64
    getter range_max : Float64
    getter default_value : Float64

    def initialize(
      @race_id : String,
      @gender : String,
      @measurement : String,
      @range_min : Float64,
      @range_max : Float64,
      @default_value : Float64,
    )
    end
  end

  struct RaceOption
    getter race_id : String
    getter gender : String
    getter category : String
    getter value : String
    getter sort_order : Int32

    def initialize(
      @race_id : String,
      @gender : String = "a",
      @category : String = "",
      @value : String = "",
      @sort_order : Int32 = 0,
    )
    end
  end

  # Mixin for SQLite-backed race registry.
  # Include in a class that has `@db : DB::Database`.
  module RaceRegistry
    TIME_FORMAT_RACE = "%F %T"

    RACE_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS races (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        builtin INTEGER NOT NULL DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL

    RACE_MEASUREMENTS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS race_measurements (
        race_id TEXT NOT NULL,
        gender TEXT NOT NULL,
        measurement TEXT NOT NULL,
        range_min REAL NOT NULL,
        range_max REAL NOT NULL,
        default_value REAL NOT NULL,
        PRIMARY KEY (race_id, gender, measurement),
        FOREIGN KEY (race_id) REFERENCES races(id)
      )
    SQL

    RACE_OPTIONS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS race_options (
        race_id TEXT NOT NULL,
        gender TEXT NOT NULL DEFAULT 'a',
        category TEXT NOT NULL,
        value TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (race_id, gender, category, value),
        FOREIGN KEY (race_id) REFERENCES races(id)
      )
    SQL

    BODY_YAML = YAML.parse({{ read_file("#{__DIR__}/../../data/body_measurements.yml") }})

    # Default portrait options shared by most races (gender "a" = any).
    # Races override specific categories in RACE_OPTION_OVERRIDES.
    DEFAULT_OPTIONS = {
      "a" => {
        "skin"         => %w[pale olive tan brown dark],
        "hair_length"  => %w[bald short medium long],
        "hair_texture" => %w[straight wavy curly],
        "hair_color"   => %w[black brown blonde red grey],
        "outfit"       => ["leather armor", "chain mail", "plate armor", "robes", "a tunic", "furs", "a uniform"],
        "outfit_color" => %w[brown black white tan red green blue purple orange yellow cyan silver gold],
      },
      "m" => {
        "facial_hair" => ["clean shaven", "stubble", "a trim beard", "a heavy beard", "a mustache", "a goatee"],
      },
    }

    RACE_OPTION_OVERRIDES = {
      "orc" => {
        "a" => {"skin" => %w[green dark brown olive]},
      },
      "elf" => {
        "a" => {"skin" => %w[pale olive tan brown]},
      },
      "dwarf" => {
        "m" => {"facial_hair" => ["stubble", "a trim beard", "a heavy beard", "a mustache", "a goatee", "braided beard"]},
      },
      "gnome" => {
        "a" => {"skin" => %w[pale olive tan brown]},
      },
      "halfling" => {
        "a" => {"skin" => %w[pale olive tan brown]},
      },
    }

    def load_race(id : String) : RaceRow?
      @db.query_one?(
        "SELECT id, name, description, builtin, created_by, created_at, updated_at FROM races WHERE id = ?",
        id
      ) do |rs|
        RaceRow.new(
          id: rs.read(String),
          name: rs.read(String),
          description: rs.read(String?),
          builtin: rs.read(Int32) == 1,
          created_by: rs.read(String?),
          created_at: Time.parse_utc(rs.read(String), TIME_FORMAT_RACE),
          updated_at: Time.parse_utc(rs.read(String), TIME_FORMAT_RACE),
        )
      end
    end

    def list_races : Array(RaceRow)
      results = [] of RaceRow
      @db.query("SELECT id, name, description, builtin, created_by, created_at, updated_at FROM races ORDER BY builtin DESC, name ASC") do |rs|
        rs.each do
          results << RaceRow.new(
            id: rs.read(String),
            name: rs.read(String),
            description: rs.read(String?),
            builtin: rs.read(Int32) == 1,
            created_by: rs.read(String?),
            created_at: Time.parse_utc(rs.read(String), TIME_FORMAT_RACE),
            updated_at: Time.parse_utc(rs.read(String), TIME_FORMAT_RACE),
          )
        end
      end
      results
    end

    def load_race_measurements(race_id : String, gender : String) : Array(RaceMeasurement)
      results = [] of RaceMeasurement
      @db.query(
        "SELECT race_id, gender, measurement, range_min, range_max, default_value FROM race_measurements WHERE race_id = ? AND gender = ?",
        race_id, gender
      ) do |rs|
        rs.each do
          results << RaceMeasurement.new(
            race_id: rs.read(String),
            gender: rs.read(String),
            measurement: rs.read(String),
            range_min: rs.read(Float64),
            range_max: rs.read(Float64),
            default_value: rs.read(Float64),
          )
        end
      end
      results
    end

    # Load options for a race+gender. Gender-specific rows override "a" (any)
    # rows for the same category. If no rows exist for a category at all
    # for the requested gender, that category is omitted.
    def load_race_options(race_id : String, gender : String) : Hash(String, Array(String))
      any_options = {} of String => Array(String)
      specific_options = {} of String => Array(String)

      @db.query(
        "SELECT gender, category, value FROM race_options WHERE race_id = ? AND gender IN (?, 'a') ORDER BY category, sort_order",
        race_id, gender
      ) do |rs|
        rs.each do
          g = rs.read(String)
          cat = rs.read(String)
          val = rs.read(String)
          if g == "a"
            (any_options[cat] ||= [] of String) << val
          else
            (specific_options[cat] ||= [] of String) << val
          end
        end
      end

      # Merge: specific gender overrides "a" per category
      result = any_options
      specific_options.each do |cat, vals|
        result[cat] = vals
      end
      result
    end

    # TODO: INSERT OR IGNORE won't update existing rows if YAML defaults change.
    # For built-in races, consider a versioned migration or INSERT OR REPLACE
    # scoped to builtin=1 rows. Must not clobber user-created custom races.
    def seed_races : Nil
      now = Time.utc.to_s(TIME_FORMAT_RACE)
      races_yaml = BODY_YAML["races"]

      races_yaml.as_h.each do |race_key, gender_data|
        race_id = race_key.as_s

        # Insert race row
        @db.exec(
          "INSERT OR IGNORE INTO races (id, name, description, builtin, created_at, updated_at) VALUES (?, ?, ?, 1, ?, ?)",
          race_id, race_id.capitalize, nil, now, now
        )

        # Insert measurements per gender
        gender_data.as_h.each do |gender_key, measurements|
          gender = gender_key.as_s
          measurements.as_h.each do |measure_key, vals|
            measure = measure_key.as_s
            range = vals["range"].as_a
            range_min = range[0].as_i.to_f64
            range_max = range[1].as_i.to_f64
            default_val = vals["default"].as_i.to_f64
            @db.exec(
              "INSERT OR IGNORE INTO race_measurements (race_id, gender, measurement, range_min, range_max, default_value) VALUES (?, ?, ?, ?, ?, ?)",
              race_id, gender, measure, range_min, range_max, default_val
            )
          end
        end

        # Insert portrait options per gender bucket
        race_overrides = RACE_OPTION_OVERRIDES[race_id]?
        DEFAULT_OPTIONS.each do |gender_key, categories|
          gender_overrides = race_overrides.try(&.[gender_key]?)
          categories.each do |category, values|
            option_values = gender_overrides.try(&.[category]?) || values
            option_values.each_with_index do |value, idx|
              @db.exec(
                "INSERT OR IGNORE INTO race_options (race_id, gender, category, value, sort_order) VALUES (?, ?, ?, ?, ?)",
                race_id, gender_key, category, value, idx
              )
            end
          end
        end
      end
    end
  end
end
