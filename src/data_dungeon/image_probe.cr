require "./webp"

# libpng's simplified API: it reports errors in the struct rather than by
# longjmp, so a bad file can't take the process down.
@[Link("png16")]
lib LibPNGImage
  struct Image
    opaque : Void*
    version : UInt32
    width : UInt32
    height : UInt32
    format : UInt32
    flags : UInt32
    colormap_entries : UInt32
    warning_or_error : UInt32
    message : UInt8[64]
  end

  VERSION     = 1_u32
  FORMAT_RGBA = 3_u32 # colour and alpha, 8 bits each

  fun png_image_begin_read_from_memory(image : Image*, memory : Void*, size : LibC::SizeT) : Int32
  fun png_image_finish_read(image : Image*, background : Void*, buffer : Void*, row_stride : Int32, colormap : Void*) : Int32
  fun png_image_free(image : Image*) : Void
end

@[Link("webp")]
lib LibWebPDecode
  struct Features
    width : Int32
    height : Int32
    has_alpha : Int32
    has_animation : Int32
    format : Int32
    pad : UInt32[5]
  end

  ABI = 0x0210 # WEBP_DECODER_ABI_VERSION (only its major part must match)

  fun WebPGetFeaturesInternal(data : UInt8*, size : LibC::SizeT, features : Features*, version : Int32) : Int32
  fun WebPDecodeRGBA(data : UInt8*, size : LibC::SizeT, width : Int32*, height : Int32*) : UInt8*
  fun WebPFree(ptr : Void*) : Void
end

@[Link("webpdemux")]
lib LibWebPDemux
  struct Data
    bytes : UInt8*
    size : LibC::SizeT
  end

  struct Iterator
    frame_num : Int32
    num_frames : Int32
    x_offset : Int32
    y_offset : Int32
    width : Int32
    height : Int32
    duration : Int32
    dispose_method : Int32
    complete : Int32
    fragment : Data
    has_alpha : Int32
    blend_method : Int32
    pad : UInt32[2]
    private_ : Void*
  end

  struct AnimOptions
    color_mode : Int32
    use_threads : Int32
    padding : UInt32[7]
  end

  struct AnimInfo
    canvas_width : UInt32
    canvas_height : UInt32
    loop_count : UInt32
    bgcolor : UInt32
    frame_count : UInt32
    pad : UInt32[4]
  end

  ABI         = 0x0107 # WEBP_DEMUX_ABI_VERSION
  MODE_RGBA   =      1
  LOOP_COUNT  =      3 # WebPFormatFeature
  FRAME_COUNT =      5

  fun WebPDemuxInternal(data : Data*, allow_partial : Int32, state : Void*, version : Int32) : Void*
  fun WebPDemuxGetI(dmux : Void*, feature : Int32) : UInt32
  fun WebPDemuxGetFrame(dmux : Void*, frame_number : Int32, iter : Iterator*) : Int32
  fun WebPDemuxNextFrame(iter : Iterator*) : Int32
  fun WebPDemuxReleaseIterator(iter : Iterator*) : Void
  fun WebPDemuxDelete(dmux : Void*) : Void
  fun WebPAnimDecoderOptionsInitInternal(options : AnimOptions*, version : Int32) : Int32
  fun WebPAnimDecoderNewInternal(data : Data*, options : AnimOptions*, version : Int32) : Void*
  fun WebPAnimDecoderGetInfo(dec : Void*, info : AnimInfo*) : Int32
  fun WebPAnimDecoderHasMoreFrames(dec : Void*) : Int32
  fun WebPAnimDecoderGetNext(dec : Void*, buf : UInt8**, timestamp : Int32*) : Int32
  fun WebPAnimDecoderDelete(dec : Void*) : Void
end

module DataDungeon
  # What DataDungeon reads from a picture's bytes: its size; whether any
  # pixel is transparent; the colour most of the visible picture is
  # (0xRRGGBB); the box around the visible pixels ({x, y, w, h}); and, for
  # an animation, its frames. Fields a format doesn't give are nil: a JPEG
  # or GIF gives its size (and a GIF its frames) from its header, and the
  # rest needs its pixels decoded.
  record Measurement,
    width : Int32,
    height : Int32,
    transparent : Bool? = nil,
    dominant_color : Int32? = nil,
    content : {Int32, Int32, Int32, Int32}? = nil,
    animation : ImageAnimation? = nil

  module ImageProbe
    class Error < Exception
    end

    # A pixel counts as visible from this alpha up (about 6%), so the faint
    # noise a cut-out's matting leaves doesn't widen its content box.
    VISIBLE_ALPHA = 16

    # The measurement of these bytes, or nil for a format DataDungeon can't
    # read (or bytes that aren't the image they claim to be).
    def self.measure(data : Bytes, content_type : String) : Measurement?
      case content_type.downcase
      when "image/png"               then png(data)
      when "image/webp"              then webp(data)
      when "image/gif"               then gif(data)
      when "image/jpeg", "image/jpg" then jpeg(data)
      end
    rescue Error | IndexError
      nil
    end

    # The RGBA pixels of a still PNG or WebP, or of an animation's first
    # frame: {width, height, pixels}.
    def self.decode(data : Bytes, content_type : String) : {Int32, Int32, Bytes}
      case content_type.downcase
      when "image/png"  then decode_png(data)
      when "image/webp" then decode_webp(data)
      else                   raise Error.new("DataDungeon can't decode #{content_type}")
      end
    end

    private def self.png(data : Bytes) : Measurement
      width, height, rgba = decode_png(data)
      from_pixels(width, height, rgba)
    end

    def self.decode_png(data : Bytes) : {Int32, Int32, Bytes}
      image = LibPNGImage::Image.new
      image.version = LibPNGImage::VERSION
      if LibPNGImage.png_image_begin_read_from_memory(pointerof(image), data.to_unsafe.as(Void*), data.size) == 0
        raise Error.new("not a PNG: #{String.new(image.message.to_unsafe)}")
      end
      image.format = LibPNGImage::FORMAT_RGBA
      width, height = image.width.to_i32, image.height.to_i32
      rgba = Bytes.new(width * height * 4)
      if LibPNGImage.png_image_finish_read(pointerof(image), nil, rgba.to_unsafe.as(Void*), 0, nil) == 0
        LibPNGImage.png_image_free(pointerof(image))
        raise Error.new("unreadable PNG: #{String.new(image.message.to_unsafe)}")
      end
      {width, height, rgba}
    end

    private def self.webp(data : Bytes) : Measurement
      features = webp_features(data)
      return from_pixels(*decode_webp(data)) if features.has_animation == 0
      width, height, rgba = decode_webp(data)
      from_pixels(width, height, rgba).copy_with(animation: webp_animation(data))
    end

    private def self.webp_features(data : Bytes) : LibWebPDecode::Features
      features = LibWebPDecode::Features.new
      unless LibWebPDecode.WebPGetFeaturesInternal(data.to_unsafe, data.size, pointerof(features), LibWebPDecode::ABI) == 0
        raise Error.new("not a WebP")
      end
      features
    end

    def self.decode_webp(data : Bytes) : {Int32, Int32, Bytes}
      if webp_features(data).has_animation != 0 # its first frame
        return decode_webp_frames(data, [0]).first?.try(&.[1]) || raise Error.new("an animated WebP with no frames")
      end
      width = height = 0
      pixels = LibWebPDecode.WebPDecodeRGBA(data.to_unsafe, data.size, pointerof(width), pointerof(height))
      raise Error.new("unreadable WebP") if pixels.null?
      rgba = Bytes.new(width * height * 4)
      rgba.copy_from(pixels, rgba.size)
      LibWebPDecode.WebPFree(pixels.as(Void*))
      {width, height, rgba}
    end

    # An animated WebP's frames as shown at each of these moments (ms from
    # its start): {moment, {width, height, pixels}}. Frames are decoded in
    # order, up to the last moment asked for.
    def self.decode_webp_frames(data : Bytes, moments : Array(Int32)) : Array({Int32, {Int32, Int32, Bytes}})
      webp_data = LibWebPDemux::Data.new(bytes: data.to_unsafe, size: data.size)
      options = LibWebPDemux::AnimOptions.new
      LibWebPDemux.WebPAnimDecoderOptionsInitInternal(pointerof(options), LibWebPDemux::ABI)
      options.color_mode = LibWebPDemux::MODE_RGBA
      decoder = LibWebPDemux.WebPAnimDecoderNewInternal(pointerof(webp_data), pointerof(options), LibWebPDemux::ABI)
      raise Error.new("unreadable animated WebP") if decoder.null?
      begin
        info = LibWebPDemux::AnimInfo.new
        LibWebPDemux.WebPAnimDecoderGetInfo(decoder, pointerof(info))
        width, height = info.canvas_width.to_i32, info.canvas_height.to_i32
        found = [] of {Int32, {Int32, Int32, Bytes}}
        pending = moments.sort
        while !pending.empty? && LibWebPDemux.WebPAnimDecoderHasMoreFrames(decoder) != 0
          buffer = Pointer(UInt8).null
          ends = 0
          break if LibWebPDemux.WebPAnimDecoderGetNext(decoder, pointerof(buffer), pointerof(ends)) == 0
          # This frame shows until `ends` (from the previous frame's end); the
          # last frame takes every moment left.
          last = LibWebPDemux.WebPAnimDecoderHasMoreFrames(decoder) == 0
          while (moment = pending.first?) && (moment < ends || last)
            rgba = Bytes.new(width * height * 4)
            rgba.copy_from(buffer, rgba.size)
            found << {moment, {width, height, rgba}}
            pending.shift
          end
        end
        found
      ensure
        LibWebPDemux.WebPAnimDecoderDelete(decoder)
      end
    end

    # Frames, total duration and loop count, from the container alone.
    private def self.webp_animation(data : Bytes) : ImageAnimation
      webp_data = LibWebPDemux::Data.new(bytes: data.to_unsafe, size: data.size)
      demux = LibWebPDemux.WebPDemuxInternal(pointerof(webp_data), 0, nil, LibWebPDemux::ABI)
      raise Error.new("unreadable animated WebP") if demux.null?
      begin
        frames = LibWebPDemux.WebPDemuxGetI(demux, LibWebPDemux::FRAME_COUNT).to_i32
        loops = LibWebPDemux.WebPDemuxGetI(demux, LibWebPDemux::LOOP_COUNT).to_i32
        duration = 0
        iter = LibWebPDemux::Iterator.new
        if LibWebPDemux.WebPDemuxGetFrame(demux, 1, pointerof(iter)) != 0
          loop do
            duration += iter.duration
            break if LibWebPDemux.WebPDemuxNextFrame(pointerof(iter)) == 0
          end
          LibWebPDemux.WebPDemuxReleaseIterator(pointerof(iter))
        end
        ImageAnimation.new(frame_count: frames, duration_ms: duration, loop_count: loops)
      ensure
        LibWebPDemux.WebPDemuxDelete(demux)
      end
    end

    # A GIF's size, frames, total duration and loop count, read from its
    # blocks without decoding the pixels.
    private def self.gif(data : Bytes) : Measurement
      raise Error.new("not a GIF") unless data.size >= 13 && String.new(data[0, 3]) == "GIF"
      width = data[6].to_i32 | data[7].to_i32 << 8
      height = data[8].to_i32 | data[9].to_i32 << 8
      pos = 13
      pos += 3 * (2 << (data[10] & 0x07)) if data[10] & 0x80 != 0 # global colour table
      frames = duration = 0
      loops : Int32? = nil
      delay = 0
      loop do
        case data[pos]
        when 0x21 # an extension
          label = data[pos + 1]
          if label == 0xF9 # graphic control: this frame's delay, in hundredths
            delay = (data[pos + 4].to_i32 | data[pos + 5].to_i32 << 8) * 10
          elsif label == 0xFF && String.new(data[pos + 3, 8]) == "NETSCAPE"
            loops = data[pos + 16].to_i32 | data[pos + 17].to_i32 << 8
          end
          pos = skip_gif_blocks(data, pos + 2)
        when 0x2C # an image: one frame
          frames += 1
          duration += delay
          delay = 0
          packed = data[pos + 9]
          pos += 10
          pos += 3 * (2 << (packed & 0x07)) if packed & 0x80 != 0 # local colour table
          pos = skip_gif_blocks(data, pos + 1)                    # after the LZW code size
        when 0x3B then break
        else           raise Error.new("unreadable GIF")
        end
      end
      animation = frames > 1 ? ImageAnimation.new(frame_count: frames, duration_ms: duration, loop_count: loops) : nil
      Measurement.new(width, height, animation: animation)
    end

    private def self.skip_gif_blocks(data : Bytes, pos : Int32) : Int32
      while (size = data[pos]) != 0
        pos += size + 1
      end
      pos + 1
    end

    # A JPEG's size from its frame header. JPEGs have no transparency, so
    # every pixel is visible.
    private def self.jpeg(data : Bytes) : Measurement
      raise Error.new("not a JPEG") unless data[0] == 0xFF && data[1] == 0xD8
      pos = 2
      loop do
        raise Error.new("unreadable JPEG") unless data[pos] == 0xFF
        marker = data[pos + 1]
        length = data[pos + 2].to_i32 << 8 | data[pos + 3].to_i32
        # A start-of-frame marker (C0-CF, but C4, C8 and CC are others)
        if 0xC0 <= marker <= 0xCF && !marker.in?(0xC4, 0xC8, 0xCC)
          height = data[pos + 5].to_i32 << 8 | data[pos + 6].to_i32
          width = data[pos + 7].to_i32 << 8 | data[pos + 8].to_i32
          return Measurement.new(width, height, transparent: false, content: {0, 0, width, height})
        end
        pos += 2 + length
      end
    end

    # Transparency, content box and dominant colour, from RGBA pixels in one
    # pass. The dominant colour is the mean of the most common colour bin
    # (eight levels a channel), counting each pixel by its opacity.
    def self.from_pixels(width : Int32, height : Int32, rgba : Bytes) : Measurement
      transparent = false
      left, top, right, bottom = width, height, -1, -1
      weight = Array(Int64).new(512, 0_i64)
      sums = Array(Int64).new(512 * 3, 0_i64)
      i = 0
      height.times do |y|
        width.times do |x|
          r, g, b, a = rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]
          i += 4
          transparent = true if a < 255
          next if a < VISIBLE_ALPHA
          left = x if x < left
          right = x if x > right
          top = y if y < top
          bottom = y if y > bottom
          bin = (r.to_i32 >> 5) << 6 | (g.to_i32 >> 5) << 3 | (b.to_i32 >> 5)
          weight[bin] += a
          sums[bin * 3] += r.to_i64 * a
          sums[bin * 3 + 1] += g.to_i64 * a
          sums[bin * 3 + 2] += b.to_i64 * a
        end
      end
      return Measurement.new(width, height, transparent: transparent) if right < 0 # nothing visible
      bin = weight.index(weight.max).not_nil!
      color = (0..2).reduce(0) { |rgb, channel| rgb << 8 | (sums[bin * 3 + channel] // weight[bin]).to_i32 }
      Measurement.new(width, height, transparent: transparent, dominant_color: color,
        content: {left, top, right - left + 1, bottom - top + 1})
    end

    # Just the content box of these pixels, for an animation's keyframes.
    def self.content_box(width : Int32, height : Int32, rgba : Bytes) : {Int32, Int32, Int32, Int32}?
      from_pixels(width, height, rgba).content
    end
  end
end
