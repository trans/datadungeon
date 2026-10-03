require "digest/sha256"

module DataDungeon
  class Cache
    SIZES = {
      background: {width: 1024, height: 768},
      tile:       {width: 768, height: 1024},
    }

    struct ImageAsset
      getter path : String
      getter url : String
      getter kind : String
      getter cached : Bool
      getter raw_request : String
      getter raw_response : String
      # What generating it cost in USD, when the provider reports it (Runware
      # does); nil for cache hits and providers that don't say
      getter cost : Float64?

      def initialize(
        @path : String, @url : String, @kind : String, @cached : Bool,
        @raw_request : String = "", @raw_response : String = "",
        @cost : Float64? = nil,
      )
      end
    end

    struct CacheLocation
      getter path : String
      getter url : String
      getter kind : String
      getter params_hash : String
      getter prompt_hash : String
      getter filename : String

      def initialize(
        @path : String,
        @url : String,
        @kind : String,
        @params_hash : String,
        @prompt_hash : String,
        @filename : String,
      )
      end
    end

    struct PortraitCacheLocation
      getter path : String
      getter url : String
      getter dir : String
      getter filename : String
      getter art_style : String
      getter rating : String
      getter race : String
      getter gender : String

      def initialize(
        @path : String, @url : String, @dir : String, @filename : String,
        @art_style : String, @rating : String, @race : String, @gender : String,
      )
      end
    end

    getter cache_root : String

    def initialize(@cache_root : String)
    end

    # ── Flat hash cache (backgrounds/tiles) ──

    def cache_location_for(prompt : String, kind : Symbol, params_hash : String) : CacheLocation
      prompt_hash = Digest::SHA256.hexdigest(prompt)
      filename = "#{prompt_hash}.webp"
      path = File.join(@cache_root, params_hash, filename)
      url = "/api/images/#{params_hash}/#{filename}"
      CacheLocation.new(path, url, kind.to_s, params_hash, prompt_hash, filename)
    end

    def resolve_cached_file(params_hash : String, filename : String) : String?
      return nil unless params_hash =~ /\A[a-f0-9]{64}\z/
      return nil unless filename =~ /\A[a-f0-9]{64}\.(png|jpg|webp)\z/

      path = File.join(@cache_root, params_hash, filename)
      File.file?(path) ? path : nil
    end

    def content_type_for(filename : String) : String
      case File.extname(filename).downcase
      when ".png"  then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".webp" then "image/webp"
      else              "application/octet-stream"
      end
    end

    # ── Backdrop hierarchical cache ──

    def save_backdrop(source_path : String, art_style : String, rating : String, centerfold : Bool) : Nil
      s = Prompts::VALID_ART_STYLES.includes?(art_style) ? art_style : "silver"
      r = Prompts::VALID_RATINGS.includes?(rating) ? rating : "pg"
      subdir = centerfold ? "centerfold" : "scenic"
      dir = File.join(@cache_root, "backdrops", s, r, subdir)
      Dir.mkdir_p(dir)
      dest = File.join(dir, File.basename(source_path))
      return if File.exists?(dest)
      begin
        File.link(source_path, dest)
      rescue
        File.copy(source_path, dest)
      end
    end

    def random_backdrop_preview(art_style : String, max_rating : String) : String?
      s = Prompts::VALID_ART_STYLES.includes?(art_style) ? art_style : "silver"
      eligible = eligible_ratings(max_rating)
      files = [] of String
      eligible.each do |r|
        %w[scenic centerfold].each do |subdir|
          dir = File.join(@cache_root, "backdrops", s, r, subdir)
          next unless Dir.exists?(dir)
          Dir.glob(File.join(dir, "*.{png,jpg,webp}")).each { |f| files << f }
        end
      end
      files.empty? ? nil : files.sample
    end

    # ── Portrait hierarchical cache ──

    def portrait_cache_location_for(
      art_style : String, rating : String, race : String, gender : String,
      embellishment_hash : String,
    ) : PortraitCacheLocation
      s = Prompts::VALID_ART_STYLES.includes?(art_style) ? art_style : "silver"
      rt = Prompts::VALID_RATINGS.includes?(rating) ? rating : "pg"
      r = Prompts::VALID_RACES.includes?(race) ? race : "human"
      g = Prompts::VALID_GENDERS.includes?(gender) ? gender : "x"

      dir = File.join(@cache_root, "portraits", s, rt, r, g)
      filename = "#{embellishment_hash}.webp"
      path = File.join(dir, filename)
      url = "/api/portraits/#{s}/#{rt}/#{r}/#{g}/#{filename}"
      PortraitCacheLocation.new(path, url, dir, filename, s, rt, r, g)
    end

    def resolve_portrait_file(
      art_style : String, rating : String, race : String, gender : String,
      filename : String,
    ) : String?
      return nil unless Prompts::VALID_ART_STYLES.includes?(art_style)
      return nil unless Prompts::VALID_RATINGS.includes?(rating)
      return nil unless Prompts::VALID_RACES.includes?(race)
      return nil unless Prompts::VALID_GENDERS.includes?(gender)
      return nil unless filename =~ /\A[a-f0-9]{64}\.(png|webp)\z/

      path = File.join(@cache_root, "portraits", art_style, rating, race, gender, filename)
      File.file?(path) ? path : nil
    end

    def portrait_url_from_path(file_path : String) : String?
      prefix = File.join(@cache_root, "portraits")
      return nil unless file_path.starts_with?(prefix)
      relative = file_path[prefix.size..].lstrip('/')
      "/api/portraits/#{relative}"
    end

    private def eligible_ratings(max : String) : Array(String)
      idx = Prompts::VALID_RATINGS.index(max) || 1
      Prompts::VALID_RATINGS[0..idx]
    end
  end
end
