module DataDungeon
  # A file format DataDungeon knows: the content types it's sent as (the
  # first is its standard name), the extension its objects take, and its
  # medium. An asset's format is its content type (DESIGN-formats).
  record Format, content_types : Array(String), extension : String, media : String

  class DB
    # The formats DataDungeon knows. Anything else is stored too, under the
    # extension of the file it came from, or `.bin` without one.
    FORMATS = [
      # Pictures
      Format.new(%w[image/webp], "webp", "image"),
      Format.new(%w[image/png], "png", "image"),
      Format.new(%w[image/jpeg image/jpg], "jpg", "image"),
      Format.new(%w[image/gif], "gif", "image"),
      Format.new(%w[image/svg+xml], "svg", "image"),
      Format.new(%w[image/tiff], "tif", "image"),
      Format.new(%w[image/x-xcf], "xcf", "image"),
      # Sound and video
      Format.new(%w[audio/mpeg audio/mp3], "mp3", "audio"),
      Format.new(%w[audio/ogg], "ogg", "audio"),
      Format.new(%w[audio/opus], "opus", "audio"),
      Format.new(%w[audio/wav audio/x-wav], "wav", "audio"),
      Format.new(%w[video/webm], "webm", "video"),
      Format.new(%w[video/mp4], "mp4", "video"),
      # Text: Yarn has no registered type and takes the one in common use;
      # eyarn, Yarn with emoji as cues, is DataDungeon's own
      Format.new(%w[text/plain], "txt", "text"),
      Format.new(%w[text/x-yarn], "yarn", "text"),
      Format.new(%w[text/vnd.datadungeon.eyarn], "eyarn", "text"),
      Format.new(%w[text/vtt], "vtt", "text"),
      Format.new(%w[application/x-subrip], "srt", "text"),
      Format.new(%w[text/csv], "csv", "text"),
      Format.new(%w[application/json], "json", "text"),
      Format.new(%w[application/xml], "xml", "text"),
      Format.new(%w[application/yaml application/x-yaml], "yaml", "text"),
      Format.new(%w[application/toml], "toml", "text"),
      # Documents
      Format.new(%w[application/pdf], "pdf", "data"),
      Format.new(%w[application/epub+zip], "epub", "data"),
      # 3D and fonts
      Format.new(%w[model/gltf-binary], "glb", "model"),
      Format.new(%w[model/gltf+json], "gltf", "model"),
      Format.new(%w[font/ttf], "ttf", "font"),
      Format.new(%w[font/otf], "otf", "font"),
      Format.new(%w[font/woff], "woff", "font"),
      Format.new(%w[font/woff2], "woff2", "font"),
    ]

    # A compressed tar's content type is only the compression's
    # (`application/gzip`), so its name keeps the tar in the usual short form.
    COMPRESSED_TARS = {"gz" => "tgz", "bz2" => "tbz2", "xz" => "txz", "zst" => "tzst"}

    # Application types that are text to read.
    STRUCTURED_TEXT = %w[application/json application/xml application/yaml application/x-yaml application/toml]

    # The format a content type names, ignoring parameters such as
    # `; charset=utf-8`, or nil for one DataDungeon doesn't know.
    def self.format(content_type : String) : Format?
      type = base_type(content_type)
      FORMATS.find(&.content_types.includes?(type))
    end

    # A content type's medium, when the caller gives none: a known format's,
    # else its top-level type (image, audio, video, text, model, font), with
    # JSON, XML and YAML counted as text, and any other type (raw bytes)
    # "data".
    def self.media_of(content_type : String) : String
      if known = format(content_type)
        return known.media
      end
      type = base_type(content_type)
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

    # The extension an object of this content type takes: a known format's;
    # `json` or `xml` for a type of that syntax (a format of an app's own,
    # `application/vnd.cattacula.marionette+json`); else the extension of
    # the file's name, so a format DataDungeon doesn't know keeps its own;
    # else `bin`. The format decides when it's known, never the name, so the
    # same bytes don't become two objects (`.jpeg` and `.jpg`).
    def self.extension_for(content_type : String, name : String? = nil) : String
      type = base_type(content_type)
      if known = format(type)
        known.extension
      elsif type.ends_with?("+json")
        "json"
      elsif type.ends_with?("+xml")
        "xml"
      else
        name.try { |file| name_extension(file) } || "bin"
      end
    end

    # A file name's extension as an object's: one part, lowercased, letters
    # and digits only, a compressed tar's in its short form (`.tar.gz` is
    # `tgz`); nil when it has none we can use (`.bashrc`, `notes`, `a.c++`).
    private def self.name_extension(name : String) : String?
      parts = File.basename(name).downcase.split('.')
      parts.shift if parts.first.empty? # a leading dot names, not extends
      return nil if parts.size < 2
      ext = parts.last
      ext = COMPRESSED_TARS[ext] if parts.size > 2 && parts[-2] == "tar" && COMPRESSED_TARS.has_key?(ext)
      ext if ext.matches?(/\A[a-z0-9]+\z/)
    end

    private def self.base_type(content_type : String) : String
      content_type.split(';').first.strip.downcase
    end
  end
end
