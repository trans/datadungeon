require "digest/sha256"

module DataDungeon
  # Compute a canonical key from a sorted hash of tag pairs.
  def self.canonical_key(tags : Hash(String, String)) : String
    sorted = tags.to_a.sort_by(&.[0])
    payload = sorted.map { |k, v| "#{k}=#{v}" }.join("\n")
    Digest::SHA256.hexdigest(payload)
  end

  struct AssetRecord
    getter id : Int64
    getter asset_type : String
    getter media : String
    getter content_type : String
    getter file_path : String
    getter canonical_key : String
    getter file_hash : String?
    getter created_at : String
    getter last_used_at : String?
    getter use_count : Int32
    getter permanent : Bool
    getter pool : Bool
    getter generator : String?
    getter generation : String?
    getter rating : Int32?
    getter flagged : Bool

    def initialize(
      @id : Int64,
      @asset_type : String,
      @media : String,
      @content_type : String,
      @file_path : String,
      @canonical_key : String,
      @file_hash : String?,
      @created_at : String,
      @last_used_at : String? = nil,
      @use_count : Int32 = 0,
      @permanent : Bool = false,
      @pool : Bool = false,
      @generator : String? = nil,
      @generation : String? = nil,
      @rating : Int32? = nil,
      @flagged : Bool = false,
    )
    end
  end

  struct ImageMeta
    getter width : Int32?
    getter height : Int32?
    getter usage_class : String?
    getter animated : Bool
    getter frame_count : Int32?
    getter duration_ms : Int32?
    getter compression : String
    getter quality_floor : Int32?
    getter max_colors : Int32?
    getter target_format : String?
    getter presentation : String?

    def initialize(
      @width : Int32? = nil,
      @height : Int32? = nil,
      @usage_class : String? = nil,
      @animated : Bool = false,
      @frame_count : Int32? = nil,
      @duration_ms : Int32? = nil,
      @compression : String = "original",
      @quality_floor : Int32? = nil,
      @max_colors : Int32? = nil,
      @target_format : String? = nil,
      @presentation : String? = nil,
    )
    end
  end

  struct AudioMeta
    getter duration_ms : Int32?
    getter sample_rate : Int32?
    getter bitrate : Int32?
    getter channels : Int32
    getter transcript_id : Int64?
    getter compression : String
    getter target_format : String?

    def initialize(
      @duration_ms : Int32? = nil,
      @sample_rate : Int32? = nil,
      @bitrate : Int32? = nil,
      @channels : Int32 = 1,
      @transcript_id : Int64? = nil,
      @compression : String = "original",
      @target_format : String? = nil,
    )
    end
  end

  struct VideoMeta
    getter width : Int32?
    getter height : Int32?
    getter duration_ms : Int32?
    getter frame_rate : Float64?
    getter usage_class : String?
    getter has_audio : Bool
    getter compression : String
    getter quality_floor : Int32?
    getter target_format : String?
    getter presentation : String?

    def initialize(
      @width : Int32? = nil,
      @height : Int32? = nil,
      @duration_ms : Int32? = nil,
      @frame_rate : Float64? = nil,
      @usage_class : String? = nil,
      @has_audio : Bool = false,
      @compression : String = "original",
      @quality_floor : Int32? = nil,
      @target_format : String? = nil,
      @presentation : String? = nil,
    )
    end
  end

  struct TextMeta
    getter content : String
    getter language : String?

    def initialize(
      @content : String,
      @language : String? = nil,
    )
    end
  end
end
