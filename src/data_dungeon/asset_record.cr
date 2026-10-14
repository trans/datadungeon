require "json"

module DataDungeon
  struct AssetRecord
    include JSON::Serializable

    getter id : Int64
    getter asset_type : String
    getter media : String
    getter content_type : String
    getter file_path : String
    # The asset's key in its type's own index, derived from its traits: its
    # type and traits' values in the registered order,
    # `portrait.golden.pg.f.human`. Several assets can share a key; the id is
    # what names one durably. Nil for an asset of an unregistered type,
    # stored before 0.12 required registering.
    getter key : String?
    getter file_hash : String?
    getter created_at : String
    getter last_used_at : String?
    getter use_count : Int32
    getter permanent : Bool
    getter generator : String?
    getter generation : String?
    getter description : String?
    # The description's SHA-256, the same in every store: assets with the
    # same hash share one description (`list_assets(description_hash:)`).
    getter description_hash : String?
    getter generated : Bool
    getter rating : Int32?
    getter flagged : Bool
    # When the content was made (by default, when it was filed): the date
    # "newest first" prefers by.
    getter made_at : String?
    # When it was retired, by a newer take superseding it or on its own; a
    # retired asset is kept but left out of lookups, listings and searches.
    getter retired_at : String?
    # Whether it has a recipe (DB#recipe), so a reader knows to ask for it.
    getter? has_recipe : Bool

    def retired? : Bool
      !@retired_at.nil?
    end

    def initialize(
      @id : Int64,
      @asset_type : String,
      @media : String,
      @content_type : String,
      @file_path : String,
      @key : String?,
      @file_hash : String?,
      @created_at : String,
      @last_used_at : String? = nil,
      @use_count : Int32 = 0,
      @permanent : Bool = false,
      @generator : String? = nil,
      @generation : String? = nil,
      @description : String? = nil,
      @description_hash : String? = nil,
      @generated : Bool = false,
      @rating : Int32? = nil,
      @flagged : Bool = false,
      @made_at : String? = nil,
      @retired_at : String? = nil,
      @has_recipe : Bool = false,
    )
    end
  end

  # How DataDungeon keys one asset type: its traits, most important first,
  # whose values make up its key; and the leading traits that form its
  # group.
  struct AssetType
    include JSON::Serializable

    getter name : String
    getter pool_traits : Array(String)
    getter group_traits : Array(String)
    # Suffixes that make some traits' key segments readable (`tan-skin`).
    getter labels : Hash(String, String)
    # Traits whose value is a set (`lantern,sword`), matched as a whole.
    getter sets : Array(String)
    # Named groups of tags embedded separately for semantic search, e.g.
    # `{"hair" => %w[hair-length hair-color]}`; "description" names the
    # asset's description.
    getter facets : Hash(String, Array(String))
    # For best matches (MatchIndex): traits whose values are ordered, low to
    # high (`{"rating" => ["g", "pg", "r", "x"]}`), so near values count as
    # close; traits whose values are colors, compared by appearance; and
    # each trait's default weight (1 unless given). None of these affect
    # keys.
    getter scales : Hash(String, Array(String))
    getter colors : Array(String)
    getter weights : Hash(String, Float64)
    # Traits whose values go round a circle (`{"time" => %w[dawn day dusk night]}`),
    # so night's nearest are dusk and dawn; and the image fields matched
    # on beside the traits (MATCH_FIELDS).
    getter cycles : Hash(String, Array(String))
    getter match_fields : Array(String)

    # Image fields best matches can use: a view or light by direction, the
    # view's roll around a circle, the dominant colour by appearance.
    MATCH_FIELDS = %w[view light roll dominant-color]

    def initialize(@name : String, @pool_traits : Array(String), @group_traits : Array(String),
                   @labels : Hash(String, String) = {} of String => String,
                   @sets : Array(String) = [] of String,
                   @facets : Hash(String, Array(String)) = {} of String => Array(String),
                   @scales : Hash(String, Array(String)) = {} of String => Array(String),
                   @colors : Array(String) = [] of String,
                   @weights : Hash(String, Float64) = {} of String => Float64,
                   @cycles : Hash(String, Array(String)) = {} of String => Array(String),
                   @match_fields : Array(String) = [] of String)
    end

    def trait?(name : String) : Bool
      @pool_traits.includes?(name)
    end

    def set?(name : String) : Bool
      @sets.includes?(name)
    end

    # This registration under another type name.
    def renamed(name : String) : AssetType
      AssetType.new(name, @pool_traits, @group_traits, @labels, @sets, @facets, @scales, @colors, @weights,
        @cycles, @match_fields)
    end

    # This registration with a trait or facet tag renamed wherever it appears.
    def with_tag_renamed(from : String, to : String) : AssetType
      swap = ->(name : String) { name == from ? to : name }
      AssetType.new(@name, @pool_traits.map(&swap), @group_traits.map(&swap),
        @labels.to_h { |trait, label| {swap.call(trait), label} }, @sets.map(&swap),
        @facets.transform_values(&.map(&swap)), @scales.to_h { |trait, values| {swap.call(trait), values} },
        @colors.map(&swap), @weights.to_h { |trait, weight| {swap.call(trait), weight} },
        @cycles.to_h { |trait, values| {swap.call(trait), values} }, @match_fields)
    end

    # The key of these normalized values, in the type's own index.
    def key(values : Hash(String, String)) : String
      TraitKey.key(@name, @pool_traits, values, @labels)
    end

    # The key prefix of these normalized values' first `size` traits.
    def prefix(values : Hash(String, String), size : Int32) : String
      TraitKey.prefix(@name, @pool_traits, values, size, @labels)
    end
  end

  # An index a consumer keeps on a registered type (`DB#register_index`):
  # the traits it usually asks by, in that order, so a lookup fixing the
  # leading ones is one range scan.
  struct AssetIndex
    include JSON::Serializable

    getter id : Int64
    getter asset_type : String
    getter consumer : String
    getter name : String
    getter traits : Array(String)

    def initialize(@id : Int64, @asset_type : String, @consumer : String, @name : String, @traits : Array(String))
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
  # A relation from one asset to another asset (`to_id`) or to a name
  # (`to_name`): see DB#link.
  struct Link
    include JSON::Serializable

    getter from_id : Int64
    getter rel : String
    getter to_id : Int64?
    getter to_name : String?
    getter created_at : String
    # What the link says about this use, such as how the asset is placed.
    getter data : JSON::Any?

    def initialize(@from_id : Int64, @rel : String, @to_id : Int64?, @to_name : String?, @created_at : String,
                   @data : JSON::Any? = nil)
    end
  end

  struct ConsistencyReport
    include JSON::Serializable

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

  # Image fields (image_meta). `nil` means not known, never zero.
  #
  # Measured by DataDungeon from the stored bytes: `width`, `height`,
  # `transparent` (any pixel not fully opaque), `dominant_color` (0xRRGGBB,
  # hex in JSON), the content box around the visible pixels (`content_*`),
  # and an animation's frames (`animation`). For an animation every field
  # describes its first frame, and keyframes record what changes.
  #
  # Set by the application, usually from what it asked the generator for:
  # the view (`view_x/y/z`, a unit vector from the thing toward the camera,
  # in the thing's frame, and `view_roll` in quarter turns), the light
  # (`light_x/y/z`, where it comes from, in the picture's frame), the anchor
  # (`anchor_x/y`, 0 to 1 across and down, the point that sits on the
  # ground or attaches), and the thing's real size in metres in its own
  # frame (`world_width` across, `world_height` up, `world_depth` front to
  # back). `view:` and `light:` take the readable form (Direction).
  struct ImageMeta < AssetMeta
    include JSON::Serializable

    getter width : Int32?
    getter height : Int32?
    getter usage_class : String?
    getter compression : String
    getter quality_floor : Int32?
    getter max_colors : Int32?
    getter target_format : String?
    getter presentation : String?
    getter transparent : Bool?
    @[JSON::Field(converter: DataDungeon::HexColor)]
    getter dominant_color : Int32?
    getter content_x : Int32?
    getter content_y : Int32?
    getter content_w : Int32?
    getter content_h : Int32?
    # Whether DataDungeon has read the bytes (measuring what their format allows).
    getter? measured : Bool
    getter view_x : Float64?
    getter view_y : Float64?
    getter view_z : Float64?
    getter view_roll : Float64?
    getter light_x : Float64?
    getter light_y : Float64?
    getter light_z : Float64?
    getter anchor_x : Float64?
    getter anchor_y : Float64?
    getter world_width : Float64?
    getter world_height : Float64?
    getter world_depth : Float64?
    getter animation : ImageAnimation?

    # The fields the application sets, which `update_asset(image:)` changes.
    SET_FIELDS = %w[usage_class presentation view_x view_y view_z view_roll light_x light_y light_z
      anchor_x anchor_y world_width world_height world_depth]

    def initialize(
      @width : Int32? = nil,
      @height : Int32? = nil,
      @usage_class : String? = nil,
      @compression : String = "original",
      @quality_floor : Int32? = nil,
      @max_colors : Int32? = nil,
      @target_format : String? = nil,
      @presentation : String? = nil,
      @transparent : Bool? = nil,
      @dominant_color : Int32? = nil,
      @content_x : Int32? = nil,
      @content_y : Int32? = nil,
      @content_w : Int32? = nil,
      @content_h : Int32? = nil,
      @measured : Bool = false,
      @view_x : Float64? = nil,
      @view_y : Float64? = nil,
      @view_z : Float64? = nil,
      @view_roll : Float64? = nil,
      @light_x : Float64? = nil,
      @light_y : Float64? = nil,
      @light_z : Float64? = nil,
      @anchor_x : Float64? = nil,
      @anchor_y : Float64? = nil,
      @world_width : Float64? = nil,
      @world_height : Float64? = nil,
      @world_depth : Float64? = nil,
      @animation : ImageAnimation? = nil,
      view : Direction? = nil,
      light : Direction? = nil,
    )
      if view
        @view_x, @view_y, @view_z = view.vector
        @view_roll ||= view.roll
      end
      if light
        @light_x, @light_y, @light_z = light.vector
      end
    end

    # The view in readable form, or nil when not known.
    def view : Direction?
      x, y, z = @view_x, @view_y, @view_z
      Direction.from(x, y, z, @view_roll || 0.0) if x && y && z
    end

    # The light in readable form, or nil when not known.
    def light : Direction?
      x, y, z = @light_x, @light_y, @light_z
      Direction.from(x, y, z) if x && y && z
    end

    # Whether it's an animation (see `animation`).
    def animated : Bool
      !@animation.nil?
    end

    # These fields with what DataDungeon measured in place of its own.
    def measured(measurement : Measurement) : ImageMeta
      copy = self
      copy.measure!(measurement)
      copy
    end

    # These fields marked as read, for bytes DataDungeon can't measure.
    def tried : ImageMeta
      copy = self
      copy.mark_measured!
      copy
    end

    protected def mark_measured! : Nil
      @measured = true
    end

    protected def measure!(m : Measurement) : Nil
      @measured = true
      @width, @height = m.width, m.height
      @transparent = m.transparent
      @dominant_color = m.dominant_color
      @content_x, @content_y, @content_w, @content_h = m.content || {nil, nil, nil, nil}
      @animation = m.animation.try { |found| @animation.try(&.merged(found)) || found }
    end
  end

  # An animated picture's frames: how many, how long all of them last, how
  # many times it plays (0: forever), and for a sprite sheet the grid its
  # frames sit in. One row of image_animation; a still picture has none.
  struct ImageAnimation
    include JSON::Serializable

    getter frame_count : Int32?
    getter duration_ms : Int32?
    getter loop_count : Int32?
    getter frame_w : Int32?
    getter frame_h : Int32?
    getter columns : Int32?

    def initialize(@frame_count : Int32? = nil, @duration_ms : Int32? = nil, @loop_count : Int32? = nil,
                   @frame_w : Int32? = nil, @frame_h : Int32? = nil, @columns : Int32? = nil)
    end

    # What was measured, keeping the sprite-sheet grid the application gave.
    def merged(measured : ImageAnimation) : ImageAnimation
      ImageAnimation.new(measured.frame_count, measured.duration_ms, measured.loop_count, @frame_w, @frame_h, @columns)
    end
  end

  # One checkpoint of an animation, `at_ms` after its start: only the fields
  # that change, each reaching its value then. Between checkpoints a value
  # glides from its neighbour (numbers in a straight line, a view or light
  # along the shorter arc), or with `held` jumps at the checkpoint, for an
  # animation that switches rather than moves. DataDungeon measures the
  # content box at each checkpoint of an animated WebP.
  struct ImageKeyframe
    include JSON::Serializable

    getter at_ms : Int32
    getter? held : Bool
    getter view_x : Float64?
    getter view_y : Float64?
    getter view_z : Float64?
    getter view_roll : Float64?
    getter light_x : Float64?
    getter light_y : Float64?
    getter light_z : Float64?
    getter anchor_x : Float64?
    getter anchor_y : Float64?
    getter content_x : Int32?
    getter content_y : Int32?
    getter content_w : Int32?
    getter content_h : Int32?

    def initialize(@at_ms : Int32, @held : Bool = false, view : Direction? = nil, light : Direction? = nil,
                   @anchor_x : Float64? = nil, @anchor_y : Float64? = nil,
                   @view_x : Float64? = nil, @view_y : Float64? = nil, @view_z : Float64? = nil, @view_roll : Float64? = nil,
                   @light_x : Float64? = nil, @light_y : Float64? = nil, @light_z : Float64? = nil,
                   @content_x : Int32? = nil, @content_y : Int32? = nil, @content_w : Int32? = nil, @content_h : Int32? = nil)
      if view
        @view_x, @view_y, @view_z = view.vector
        @view_roll ||= view.roll
      end
      if light
        @light_x, @light_y, @light_z = light.vector
      end
    end

    def view : Direction?
      x, y, z = @view_x, @view_y, @view_z
      Direction.from(x, y, z, @view_roll || 0.0) if x && y && z
    end

    def light : Direction?
      x, y, z = @light_x, @light_y, @light_z
      Direction.from(x, y, z) if x && y && z
    end

    # This checkpoint with the content box DataDungeon measured.
    def with_content(box : {Int32, Int32, Int32, Int32}) : ImageKeyframe
      copy = self
      copy.content!(box)
      copy
    end

    protected def content!(box : {Int32, Int32, Int32, Int32}) : Nil
      @content_x, @content_y, @content_w, @content_h = box
    end
  end

  # A direction in readable form, in quarter turns (1 = 90 degrees): `side`
  # front or back, `yaw` toward the right (+1) or left (-1) on either face,
  # `pitch` from above (+1) or below (-1), and for a view `roll`, the picture
  # turned in its own plane (-2 to 2). A view is where the camera stands, in
  # the thing's frame (z toward its front, x its right, y up); a light is
  # where the light comes from, in the picture's frame (z toward the viewer,
  # x right, y up). DataDungeon stores the unit vector, so neighbouring
  # directions compare by a dot product with no seams; this is the form for
  # people. A profile whose nose points left in the picture shows the thing's
  # right side: yaw +1.
  struct Direction
    include JSON::Serializable

    getter side : String
    getter yaw : Float64
    getter pitch : Float64
    getter roll : Float64

    # Eight directions around a thing, by azimuth from its front.
    AROUND = %w[front front-right right back-right back back-left left front-left]

    def initialize(@side : String = "front", @yaw : Float64 = 0.0, @pitch : Float64 = 0.0, @roll : Float64 = 0.0)
      raise ArgumentError.new("side is front or back, not #{@side}") unless @side.in?("front", "back")
      raise ArgumentError.new("yaw is -1 to 1 quarter turns") unless -1.0 <= @yaw <= 1.0
      raise ArgumentError.new("pitch is -1 to 1 quarter turns") unless -1.0 <= @pitch <= 1.0
      raise ArgumentError.new("roll is -2 to 2 quarter turns") unless -2.0 <= @roll <= 2.0
    end

    # The readable form of a vector (made unit length first).
    def self.from(x : Float64, y : Float64, z : Float64, roll : Float64 = 0.0) : Direction
      x, y, z = Direction.unit(x, y, z)
      pitch = Math.asin(y.clamp(-1.0, 1.0))
      across = Math.cos(pitch)
      yaw = across < 1e-9 ? 0.0 : Math.asin((x / across).clamp(-1.0, 1.0))
      new(z >= 0 ? "front" : "back", (yaw / QUARTER).round(4), (pitch / QUARTER).round(4), roll)
    end

    # A vector of length 1 in the same direction; a zero vector has none.
    def self.unit(x : Float64, y : Float64, z : Float64) : {Float64, Float64, Float64}
      length = Math.sqrt(x * x + y * y + z * z)
      raise ArgumentError.new("a direction can't be the zero vector") if length < 1e-9
      {x / length, y / length, z / length}
    end

    QUARTER = Math::PI / 2

    def vector : {Float64, Float64, Float64}
      yaw, pitch = @yaw * QUARTER, @pitch * QUARTER
      z = Math.cos(pitch) * Math.cos(yaw)
      {Math.cos(pitch) * Math.sin(yaw), Math.sin(pitch), @side == "front" ? z : -z}
    end

    # Its name: one of eight directions around (`back-left`), with
    # `from-above` or `from-below` nearer 45 degrees up or down than level,
    # or `top-down` or `bottom-up` nearer the poles. Each name is the middle
    # of its sector, where pictures asked for by name sit.
    def name : String
      Direction.name(*vector)
    end

    def self.name(x : Float64, y : Float64, z : Float64) : String
      elevation = Math.asin(y.clamp(-1.0, 1.0)) * 180 / Math::PI
      return "top-down" if elevation >= 67.5
      return "bottom-up" if elevation <= -67.5
      around = AROUND[(Math.atan2(x, z) * 180 / Math::PI / 45).round.to_i % 8]
      if elevation >= 22.5
        "#{around} from-above"
      elsif elevation <= -22.5
        "#{around} from-below"
      else
        around
      end
    end
  end

  # What a listing asks of a picture's fields (list_assets(image:)): each of
  # `ranges` between its lowest and highest (either end open), a view or a
  # light within so many degrees of a direction, and a named `direction`
  # (`back-left`, `from-above`, `top-down`, or several words).
  struct ImageFilter
    getter ranges : Hash(String, {Float64?, Float64?})
    getter view : Direction?
    getter view_within : Float64
    getter light : Direction?
    getter light_within : Float64
    getter direction : String?

    # `ranges` maps a field to {low, high}, numbers or nil for an open end.
    def initialize(ranges : Hash = {} of String => {Float64?, Float64?}, @view : Direction? = nil, @view_within = 30.0,
                   @light : Direction? = nil, @light_within = 30.0, @direction : String? = nil)
      @ranges = ranges.to_h do |field, (low, high)|
        {field.to_s, {low.try(&.to_f64).as(Float64?), high.try(&.to_f64).as(Float64?)}}
      end
    end
  end

  # A colour as an integer (0xRRGGBB) in the database, `#rrggbb` in JSON.
  module HexColor
    def self.to_json(value : Int32, json : JSON::Builder) : Nil
      json.string("#%06x" % value)
    end

    def self.from_json(pull : JSON::PullParser) : Int32
      parse(pull.read_string)
    end

    def self.parse(text : String) : Int32
      hex = text.lchop('#')
      raise ArgumentError.new("a colour is #rrggbb, not #{text}") unless hex.size == 6 && hex.hexbytes?
      hex.to_i(16)
    end
  end

  struct AudioMeta < AssetMeta
    include JSON::Serializable

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
    include JSON::Serializable

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
    include JSON::Serializable

    getter content : String
    getter language : String?

    def initialize(
      @content : String,
      @language : String? = nil,
    )
    end
  end
end
