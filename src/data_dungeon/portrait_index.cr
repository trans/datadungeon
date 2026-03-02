require "json"

module DataDungeon
  # Bucket steps for rounding measurements (from body_measurements.yml)
  BUCKET_STEPS = {
    "height" => 3, "shoulders" => 2, "chest" => 2, "waist" => 3,
    "hips" => 3, "neck" => 1, "arm_length" => 3, "leg_inseam" => 3,
  }

  def self.bucket(value : Float64, step : Int32) : Int32
    (value / step).round.to_i * step
  end

  struct PortraitAttrs
    getter height_bucket : Int32
    getter shoulders_bucket : Int32
    getter chest_bucket : Int32
    getter waist_bucket : Int32
    getter hips_bucket : Int32
    getter neck_bucket : Int32
    getter arm_length_bucket : Int32
    getter leg_inseam_bucket : Int32
    getter phy_tier : Int32
    getter skin : String
    getter hair_length : String
    getter hair_texture : String
    getter hair_color : String
    getter facial_hair : String
    getter outfit : String
    getter outfit_color : String
    getter embellishment : String

    def initialize(
      @height_bucket : Int32 = 69,
      @shoulders_bucket : Int32 = 18,
      @chest_bucket : Int32 = 40,
      @waist_bucket : Int32 = 33,
      @hips_bucket : Int32 = 36,
      @neck_bucket : Int32 = 16,
      @arm_length_bucket : Int32 = 27,
      @leg_inseam_bucket : Int32 = 30,
      @phy_tier : Int32 = 2,
      @skin : String = "tan",
      @hair_length : String = "short",
      @hair_texture : String = "straight",
      @hair_color : String = "brown",
      @facial_hair : String = "clean shaven",
      @outfit : String = "tunic",
      @outfit_color : String = "brown",
      @embellishment : String = "",
    )
    end

    def self.from_json(parsed : JSON::Any) : PortraitAttrs
      # Parse measurements object (from frontend bodyEditor.getMeasurements())
      m = parsed["measurements"]?
      height_in = m.try(&.["height"]?.try(&.as_f?)) || m.try(&.["height"]?.try(&.as_i?.try(&.to_f))) || 70.0
      shoulders_in = m.try(&.["shoulders"]?.try(&.as_f?)) || m.try(&.["shoulders"]?.try(&.as_i?.try(&.to_f))) || 18.0
      chest_in = m.try(&.["chest"]?.try(&.as_f?)) || m.try(&.["chest"]?.try(&.as_i?.try(&.to_f))) || 40.0
      waist_in = m.try(&.["waist"]?.try(&.as_f?)) || m.try(&.["waist"]?.try(&.as_i?.try(&.to_f))) || 34.0
      hips_in = m.try(&.["hips"]?.try(&.as_f?)) || m.try(&.["hips"]?.try(&.as_i?.try(&.to_f))) || 36.0
      neck_in = m.try(&.["neck"]?.try(&.as_f?)) || m.try(&.["neck"]?.try(&.as_i?.try(&.to_f))) || 16.0
      arm_in = m.try(&.["arm_length"]?.try(&.as_f?)) || m.try(&.["arm_length"]?.try(&.as_i?.try(&.to_f))) || 26.0
      leg_in = m.try(&.["leg_inseam"]?.try(&.as_f?)) || m.try(&.["leg_inseam"]?.try(&.as_i?.try(&.to_f))) || 31.0

      PortraitAttrs.new(
        height_bucket: DataDungeon.bucket(height_in, BUCKET_STEPS["height"]),
        shoulders_bucket: DataDungeon.bucket(shoulders_in, BUCKET_STEPS["shoulders"]),
        chest_bucket: DataDungeon.bucket(chest_in, BUCKET_STEPS["chest"]),
        waist_bucket: DataDungeon.bucket(waist_in, BUCKET_STEPS["waist"]),
        hips_bucket: DataDungeon.bucket(hips_in, BUCKET_STEPS["hips"]),
        neck_bucket: DataDungeon.bucket(neck_in, BUCKET_STEPS["neck"]),
        arm_length_bucket: DataDungeon.bucket(arm_in, BUCKET_STEPS["arm_length"]),
        leg_inseam_bucket: DataDungeon.bucket(leg_in, BUCKET_STEPS["leg_inseam"]),
        phy_tier: parsed["phy_tier"]?.try(&.as_i?) || 2,
        skin: parsed["skin"]?.try(&.as_s?) || "tan",
        hair_length: parsed["hair_length"]?.try(&.as_s?) || "short",
        hair_texture: parsed["hair_texture"]?.try(&.as_s?) || "straight",
        hair_color: parsed["hair_color"]?.try(&.as_s?) || "brown",
        facial_hair: parsed["facial_hair"]?.try(&.as_s?) || "clean shaven",
        outfit: parsed["outfit"]?.try(&.as_s?) || "tunic",
        outfit_color: parsed["outfit_color"]?.try(&.as_s?) || "brown",
        embellishment: parsed["embellishment"]?.try(&.as_s?) || "",
      )
    end
  end

  struct PortraitMatch
    getter hash : String
    getter score : Int32
    getter exact : Bool

    def initialize(@hash : String, @score : Int32 = 0, @exact : Bool = false)
    end
  end

  # Mixin for SQLite-backed portrait index queries.
  # Include in a class that has `@db : DB::Database`.
  module PortraitIndex
    TIME_FORMAT = "%F %T"

    PORTRAIT_INDEX_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS portrait_index (
        hash TEXT NOT NULL,
        art_style TEXT NOT NULL,
        rating TEXT NOT NULL,
        race TEXT NOT NULL,
        gender TEXT NOT NULL,
        height_bucket INTEGER NOT NULL DEFAULT 69,
        shoulders_bucket INTEGER NOT NULL DEFAULT 18,
        chest_bucket INTEGER NOT NULL DEFAULT 40,
        waist_bucket INTEGER NOT NULL DEFAULT 33,
        hips_bucket INTEGER NOT NULL DEFAULT 36,
        neck_bucket INTEGER NOT NULL DEFAULT 16,
        arm_length_bucket INTEGER NOT NULL DEFAULT 27,
        leg_inseam_bucket INTEGER NOT NULL DEFAULT 30,
        phy_tier INTEGER NOT NULL,
        skin TEXT NOT NULL,
        hair_length TEXT NOT NULL,
        hair_texture TEXT NOT NULL,
        hair_color TEXT NOT NULL,
        facial_hair TEXT NOT NULL,
        outfit TEXT NOT NULL,
        outfit_color TEXT NOT NULL,
        embellishment TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        PRIMARY KEY (art_style, rating, race, gender, hash)
      )
    SQL

    # Max score for exact match: 8 measurement buckets × 2 + phy_tier × 2 + 5 appearance × 1 = 23
    MAX_SCORE = 23

    def save_portrait(hash : String, art_style : String, rating : String, race : String, gender : String, attrs : PortraitAttrs) : Nil
      now = Time.utc.to_s(TIME_FORMAT)
      @db.exec(
        <<-SQL,
          INSERT OR REPLACE INTO portrait_index
          (hash, art_style, rating, race, gender,
           height_bucket, shoulders_bucket, chest_bucket, waist_bucket,
           hips_bucket, neck_bucket, arm_length_bucket, leg_inseam_bucket,
           phy_tier, skin, hair_length, hair_texture, hair_color,
           facial_hair, outfit, outfit_color, embellishment, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        hash, art_style, rating, race, gender,
        attrs.height_bucket, attrs.shoulders_bucket, attrs.chest_bucket, attrs.waist_bucket,
        attrs.hips_bucket, attrs.neck_bucket, attrs.arm_length_bucket, attrs.leg_inseam_bucket,
        attrs.phy_tier, attrs.skin,
        attrs.hair_length, attrs.hair_texture, attrs.hair_color,
        attrs.facial_hair, attrs.outfit, attrs.outfit_color,
        attrs.embellishment, now
      )
    end

    def find_exact_portrait(art_style : String, rating : String, race : String, gender : String, hash : String) : Bool
      result = @db.scalar(
        "SELECT COUNT(*) FROM portrait_index WHERE art_style = ? AND rating = ? AND race = ? AND gender = ? AND hash = ?",
        art_style, rating, race, gender, hash
      )
      result.as(Int64) > 0
    end

    def find_closest_portrait(art_style : String, rating : String, race : String, gender : String, attrs : PortraitAttrs) : PortraitMatch?
      @db.query_one?(
        <<-SQL,
          SELECT hash,
            (CASE WHEN height_bucket=? THEN 2 WHEN ABS(height_bucket-?)<=3 THEN 1 ELSE 0 END) +
            (CASE WHEN shoulders_bucket=? THEN 2 WHEN ABS(shoulders_bucket-?)<=2 THEN 1 ELSE 0 END) +
            (CASE WHEN chest_bucket=? THEN 2 WHEN ABS(chest_bucket-?)<=2 THEN 1 ELSE 0 END) +
            (CASE WHEN waist_bucket=? THEN 2 WHEN ABS(waist_bucket-?)<=3 THEN 1 ELSE 0 END) +
            (CASE WHEN hips_bucket=? THEN 2 WHEN ABS(hips_bucket-?)<=3 THEN 1 ELSE 0 END) +
            (CASE WHEN neck_bucket=? THEN 2 WHEN ABS(neck_bucket-?)<=1 THEN 1 ELSE 0 END) +
            (CASE WHEN arm_length_bucket=? THEN 2 WHEN ABS(arm_length_bucket-?)<=3 THEN 1 ELSE 0 END) +
            (CASE WHEN leg_inseam_bucket=? THEN 2 WHEN ABS(leg_inseam_bucket-?)<=3 THEN 1 ELSE 0 END) +
            (CASE WHEN phy_tier=? THEN 2 ELSE 0 END) +
            (CASE WHEN skin=? THEN 1 ELSE 0 END) +
            (CASE WHEN hair_length=? THEN 1 ELSE 0 END) +
            (CASE WHEN hair_texture=? THEN 1 ELSE 0 END) +
            (CASE WHEN hair_color=? THEN 1 ELSE 0 END) +
            (CASE WHEN outfit=? THEN 1 ELSE 0 END)
            AS score
          FROM portrait_index
          WHERE art_style=? AND rating=? AND race=? AND gender=?
          ORDER BY score DESC, created_at DESC
          LIMIT 1
        SQL
        attrs.height_bucket, attrs.height_bucket,
        attrs.shoulders_bucket, attrs.shoulders_bucket,
        attrs.chest_bucket, attrs.chest_bucket,
        attrs.waist_bucket, attrs.waist_bucket,
        attrs.hips_bucket, attrs.hips_bucket,
        attrs.neck_bucket, attrs.neck_bucket,
        attrs.arm_length_bucket, attrs.arm_length_bucket,
        attrs.leg_inseam_bucket, attrs.leg_inseam_bucket,
        attrs.phy_tier,
        attrs.skin, attrs.hair_length, attrs.hair_texture, attrs.hair_color,
        attrs.outfit,
        art_style, rating, race, gender
      ) do |rs|
        hash = rs.read(String)
        score = rs.read(Int64).to_i32
        PortraitMatch.new(hash, score, score == MAX_SCORE)
      end
    end
  end
end
