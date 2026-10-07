module DataDungeon
  struct AssetRecord
    getter id : Int64
    getter asset_type : String
    getter media : String
    getter content_type : String
    getter file_path : String
    # Key of the pool of interchangeable assets this one belongs to. For a
    # registered type, its type and traits' values in order:
    # `portrait.golden.pg.f.human`.
    getter pool_key : String?
    getter file_hash : String?
    getter created_at : String
    getter last_used_at : String?
    getter use_count : Int32
    getter permanent : Bool
    getter pool : Bool
    getter generator : String?
    getter generation : String?
    getter description : String?
    getter generated : Bool
    getter rating : Int32?
    getter flagged : Bool

    def initialize(
      @id : Int64,
      @asset_type : String,
      @media : String,
      @content_type : String,
      @file_path : String,
      @pool_key : String?,
      @file_hash : String?,
      @created_at : String,
      @last_used_at : String? = nil,
      @use_count : Int32 = 0,
      @permanent : Bool = false,
      @pool : Bool = false,
      @generator : String? = nil,
      @generation : String? = nil,
      @description : String? = nil,
      @generated : Bool = false,
      @rating : Int32? = nil,
      @flagged : Bool = false,
    )
    end

    @[Deprecated("Use `pool_key`.")]
    def canonical_key : String?
      @pool_key
    end
  end

  # How DataDungeon keys one asset type: its traits, most important first,
  # whose values make up its pool key; the leading traits that form its group;
  # and whether a pool key holds many interchangeable assets (`pool`) or one
  # best asset.
  struct AssetType
    getter name : String
    getter pool_traits : Array(String)
    getter group_traits : Array(String)
    getter pool : Bool
    # Suffixes that make some traits' key segments readable (`tan-skin`).
    getter labels : Hash(String, String)
    # Traits whose value is a set (`lantern,sword`), matched as a whole.
    getter sets : Array(String)
    # Named groups of tags embedded separately for semantic search, e.g.
    # `{"hair" => %w[hair_length hair_color]}`; "description" names the
    # asset's description.
    getter facets : Hash(String, Array(String))

    def initialize(@name : String, @pool_traits : Array(String), @group_traits : Array(String), @pool : Bool,
                   @labels : Hash(String, String) = {} of String => String,
                   @sets : Array(String) = [] of String,
                   @facets : Hash(String, Array(String)) = {} of String => Array(String))
    end

    def trait?(name : String) : Bool
      @pool_traits.includes?(name)
    end

    def set?(name : String) : Bool
      @sets.includes?(name)
    end

    # The pool key of these normalized values.
    def key(values : Hash(String, String)) : String
      TraitKey.key(@name, @pool_traits, values, @labels)
    end

    # The key prefix of these normalized values' first `size` traits.
    def prefix(values : Hash(String, String), size : Int32) : String
      TraitKey.prefix(@name, @pool_traits, values, size, @labels)
    end
  end

  # Result of `DB#find`: the assets matching every trait that must match
  # (`pool`), and the rest of their group (`group`).
  struct Matches
    getter pool : Array(AssetRecord)
    getter group : Array(AssetRecord)

    def initialize(@pool : Array(AssetRecord), @group : Array(AssetRecord))
    end

    # Pool matches first, then the rest of the group.
    def all : Array(AssetRecord)
      @pool + @group
    end
  end

  # Outcome of a store-consistency sweep (`DB#check_consistency` / `DB#vacuum`).
  # Divergence between the index and the backend can go two ways; this reports
  # both. When produced by `vacuum`, the entries are what was found *and* acted
  # on per the flags passed.
  struct ConsistencyReport
    # Rows whose backing object no longer resolves in storage.
    getter missing_objects : Array(AssetRecord)
    # Object keys present in storage with no owning `assets` row.
    getter orphan_objects : Array(String)

    def initialize(
      @missing_objects : Array(AssetRecord),
      @orphan_objects : Array(String),
    )
    end

    # True when the index and the backend are fully reconciled.
    def clean? : Bool
      @missing_objects.empty? && @orphan_objects.empty?
    end
  end

  # Common base for all media metadata. Lets a single accessor
  # (`DB#get_with_meta`) return the sidecar appropriate to the asset's media
  # as one polymorphic type. Callers narrow with `.as?(ImageMeta)` etc. when
  # they need media-specific fields.
  abstract struct AssetMeta
    # Renderer placement hint (opaque JSON blob). Present on visual media
    # (image, video); nil for audio and text.
    def presentation : String?
      nil
    end
  end

  struct ImageMeta < AssetMeta
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

  struct AudioMeta < AssetMeta
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

  struct VideoMeta < AssetMeta
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

  struct TextMeta < AssetMeta
    getter content : String
    getter language : String?

    def initialize(
      @content : String,
      @language : String? = nil,
    )
    end
  end
end
