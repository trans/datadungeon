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

  # Legacy constant — kept for backward compatibility with fuzzy scoring
  module PortraitIndex
    # Max score for exact match: 8 measurement buckets × 2 + phy_tier × 2 + 5 appearance × 1 = 23
    MAX_SCORE = 23
  end
end
