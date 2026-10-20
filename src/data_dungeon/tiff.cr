require "./image_probe"

# libtiff 4.5 or later, read and written in memory, with its errors handed
# back rather than printed.
@[Link("tiff")]
lib LibTIFF
  alias Size = LibC::SSizeT
  alias Offset = UInt64
  type TIFF = Void*
  type Options = Void*

  alias ReadWriteProc = Void*, Void*, Size -> Size
  alias SeekProc = Void*, Offset, Int32 -> Offset
  alias CloseProc = Void* -> Int32
  alias SizeProc = Void* -> Offset
  alias MapProc = Void*, Void**, Offset* -> Int32
  alias UnmapProc = Void*, Void*, Offset -> Void
  # The last argument is a va_list, passed on to vsnprintf untouched.
  alias ErrorHandler = TIFF, Void*, UInt8*, UInt8*, Void* -> Int32

  IMAGEWIDTH      =   256_u32
  IMAGELENGTH     =   257_u32
  BITSPERSAMPLE   =   258_u32
  COMPRESSION     =   259_u32
  PHOTOMETRIC     =   262_u32
  ORIENTATION     =   274_u32
  SAMPLESPERPIXEL =   277_u32
  ROWSPERSTRIP    =   278_u32
  PLANARCONFIG    =   284_u32
  PREDICTOR       =   317_u32
  TILEWIDTH       =   322_u32
  TILELENGTH      =   323_u32
  EXTRASAMPLES    =   338_u32
  SAMPLEFORMAT    =   339_u32
  ZIPQUALITY      = 65557_u32

  COMPRESSION_ADOBE_DEFLATE = 8
  PHOTOMETRIC_MINISBLACK    = 1
  PHOTOMETRIC_RGB           = 2
  ORIENTATION_TOPLEFT       = 1
  PLANARCONFIG_CONTIG       = 1
  PREDICTOR_HORIZONTAL      = 2
  EXTRASAMPLE_UNSPECIFIED   = 0
  EXTRASAMPLE_UNASSALPHA    = 2
  SAMPLEFORMAT_UINT         = 1

  fun TIFFOpenOptionsAlloc : Options
  fun TIFFOpenOptionsFree(opts : Options) : Void
  fun TIFFOpenOptionsSetErrorHandlerExtR(opts : Options, handler : ErrorHandler, user_data : Void*) : Void
  fun TIFFOpenOptionsSetWarningHandlerExtR(opts : Options, handler : ErrorHandler, user_data : Void*) : Void
  fun TIFFClientOpenExt(name : UInt8*, mode : UInt8*, clientdata : Void*,
                        readproc : ReadWriteProc, writeproc : ReadWriteProc, seekproc : SeekProc,
                        closeproc : CloseProc, sizeproc : SizeProc, mapproc : MapProc, unmapproc : UnmapProc,
                        opts : Options) : TIFF
  fun TIFFClose(tif : TIFF) : Void
  fun TIFFGetFieldDefaulted(tif : TIFF, tag : UInt32, ...) : Int32
  fun TIFFSetField(tif : TIFF, tag : UInt32, ...) : Int32
  fun TIFFIsTiled(tif : TIFF) : Int32
  fun TIFFTileSize(tif : TIFF) : Size
  fun TIFFStripSize(tif : TIFF) : Size
  fun TIFFComputeTile(tif : TIFF, x : UInt32, y : UInt32, z : UInt32, sample : UInt16) : UInt32
  fun TIFFComputeStrip(tif : TIFF, row : UInt32, sample : UInt16) : UInt32
  fun TIFFReadEncodedTile(tif : TIFF, tile : UInt32, buf : Void*, size : Size) : Size
  fun TIFFReadEncodedStrip(tif : TIFF, strip : UInt32, buf : Void*, size : Size) : Size
  fun TIFFWriteEncodedTile(tif : TIFF, tile : UInt32, data : Void*, size : Size) : Size
  fun TIFFReadRGBAImageOriented(tif : TIFF, width : UInt32, height : UInt32, raster : UInt32*,
                                orientation : Int32, stop_on_error : Int32) : Int32
  fun vsnprintf(buffer : UInt8*, size : LibC::SizeT, format : UInt8*, args : Void*) : Int32
end

module DataDungeon
  # TIFF, through libtiff: a picture of any layout, compression or depth
  # libtiff reads, decoded to 8-bit RGBA; and 8-bit pictures written in
  # 64×64 tiles, deflate-compressed with horizontal prediction, the layout
  # that keeps a small edit small on transfs (its chunk study: 2.6 MiB a
  # small stroke over 37 pictures, against PNG's 32.7). Requiring this file
  # links libtiff and adds `image/tiff` to what DataDungeon measures,
  # converts to WebP and stores as (`target_format: "tiff"`).
  module TIFF
    TILE = 64

    # A TIFF in memory, and what libtiff said went wrong with it.
    private class Handle
      getter io : IO::Memory
      getter errors = [] of String

      def initialize(@io : IO::Memory)
      end
    end

    # The first picture in these bytes as {width, height, RGBA pixels}, 8
    # bits a channel and straight (not premultiplied) alpha.
    def self.decode(data : Bytes) : {Int32, Int32, Bytes}
      open(IO::Memory.new(data, writable: false), "r") do |tif|
        width, height = field_u32(tif, LibTIFF::IMAGEWIDTH), field_u32(tif, LibTIFF::IMAGELENGTH)
        raise ImageProbe::Error.new("a TIFF #{width}×#{height}") unless width > 0 && height > 0
        {width.to_i32, height.to_i32, read_samples(tif, width, height) || read_rgba(tif, width, height)}
      end
    end

    # These RGBA pixels as a TIFF in 64×64 deflate tiles, 8 bits a channel,
    # with alpha only when a pixel isn't opaque. The same pixels always give
    # the same bytes.
    def self.encode(width : Int32, height : Int32, rgba : Bytes) : Bytes
      raise ArgumentError.new("#{width}×#{height} pixels need #{width * height * 4} bytes, not #{rgba.size}") unless rgba.size == width * height * 4
      alpha = (0...width * height).any? { |i| rgba[i * 4 + 3] < 255 }
      channels = alpha ? 4 : 3
      written = IO::Memory.new
      open(written, "w") do |tif|
        LibTIFF.TIFFSetField(tif, LibTIFF::IMAGEWIDTH, width.to_u32)
        LibTIFF.TIFFSetField(tif, LibTIFF::IMAGELENGTH, height.to_u32)
        LibTIFF.TIFFSetField(tif, LibTIFF::BITSPERSAMPLE, 8)
        LibTIFF.TIFFSetField(tif, LibTIFF::SAMPLESPERPIXEL, channels)
        LibTIFF.TIFFSetField(tif, LibTIFF::PHOTOMETRIC, LibTIFF::PHOTOMETRIC_RGB)
        LibTIFF.TIFFSetField(tif, LibTIFF::PLANARCONFIG, LibTIFF::PLANARCONFIG_CONTIG)
        LibTIFF.TIFFSetField(tif, LibTIFF::COMPRESSION, LibTIFF::COMPRESSION_ADOBE_DEFLATE)
        LibTIFF.TIFFSetField(tif, LibTIFF::PREDICTOR, LibTIFF::PREDICTOR_HORIZONTAL)
        LibTIFF.TIFFSetField(tif, LibTIFF::ZIPQUALITY, 6)
        LibTIFF.TIFFSetField(tif, LibTIFF::TILEWIDTH, TILE.to_u32)
        LibTIFF.TIFFSetField(tif, LibTIFF::TILELENGTH, TILE.to_u32)
        if alpha
          extra = Slice[LibTIFF::EXTRASAMPLE_UNASSALPHA.to_u16]
          LibTIFF.TIFFSetField(tif, LibTIFF::EXTRASAMPLES, 1, extra.to_unsafe)
        end
        tile = Bytes.new(TILE * TILE * channels)
        (0...height).step(TILE) do |top|
          (0...width).step(TILE) do |left|
            tile.fill(0_u8)
            Math.min(TILE, height - top).times do |row|
              Math.min(TILE, width - left).times do |column|
                from = ((top + row) * width + left + column) * 4
                to = (row * TILE + column) * channels
                channels.times { |channel| tile[to + channel] = rgba[from + channel] }
              end
            end
            index = LibTIFF.TIFFComputeTile(tif, left.to_u32, top.to_u32, 0_u32, 0_u16)
            if LibTIFF.TIFFWriteEncodedTile(tif, index, tile.to_unsafe.as(Void*), LibTIFF::Size.new(tile.size)) < 0
              raise ImageProbe::Error.new("TIFF tile at #{left}, #{top} wasn't written")
            end
          end
        end
      end
      written.to_slice.dup
    end

    # The common layouts read straight from their samples, so 8-bit pixels
    # come back exactly and 16-bit ones rounded to the nearest 8-bit level:
    # one plane of 8 or 16 bits, top row first, grey or RGB, with or
    # without unassociated alpha. Anything else is nil.
    private def self.read_samples(tif : LibTIFF::TIFF, width : UInt32, height : UInt32) : Bytes?
      bits = field_u16(tif, LibTIFF::BITSPERSAMPLE)
      channels = field_u16(tif, LibTIFF::SAMPLESPERPIXEL)
      photometric = field_u16(tif, LibTIFF::PHOTOMETRIC)
      return nil unless bits.in?(8, 16) &&
                        field_u16(tif, LibTIFF::PLANARCONFIG) == LibTIFF::PLANARCONFIG_CONTIG &&
                        field_u16(tif, LibTIFF::SAMPLEFORMAT) == LibTIFF::SAMPLEFORMAT_UINT &&
                        field_u16(tif, LibTIFF::ORIENTATION) == LibTIFF::ORIENTATION_TOPLEFT
      colours = case {photometric, channels}
                when {LibTIFF::PHOTOMETRIC_RGB, 3}, {LibTIFF::PHOTOMETRIC_RGB, 4}               then 3
                when {LibTIFF::PHOTOMETRIC_MINISBLACK, 1}, {LibTIFF::PHOTOMETRIC_MINISBLACK, 2} then 1
                else                                                                                 return nil
                end
      alpha = channels > colours
      return nil if alpha && !straight_alpha?(tif)
      w, h = width.to_i32, height.to_i32
      rgba = Bytes.new(w * h * 4, 255_u8)
      sample = bits // 8
      place = ->(block : Bytes, left : Int32, top : Int32, block_width : Int32, rows : Int32) do
        rows.times do |row|
          y = top + row
          break if y >= h
          block_width.times do |column|
            x = left + column
            break if x >= w
            from = (row * block_width + column) * channels * sample
            to = (y * w + x) * 4
            channels.times do |channel|
              value = sample == 1 ? block[from + channel] : level(block, from + channel * 2)
              if channel < colours
                (colours == 1 ? 3 : 1).times { |copy| rgba[to + channel + copy] = value }
              else
                rgba[to + 3] = value
              end
            end
          end
        end
      end
      if LibTIFF.TIFFIsTiled(tif) != 0
        tile_width, tile_height = field_u32(tif, LibTIFF::TILEWIDTH).to_i32, field_u32(tif, LibTIFF::TILELENGTH).to_i32
        block = Bytes.new(LibTIFF.TIFFTileSize(tif))
        (0...h).step(tile_height) do |top|
          (0...w).step(tile_width) do |left|
            index = LibTIFF.TIFFComputeTile(tif, left.to_u32, top.to_u32, 0_u32, 0_u16)
            raise ImageProbe::Error.new("unreadable TIFF tile") if LibTIFF.TIFFReadEncodedTile(tif, index, block.to_unsafe.as(Void*), LibTIFF::Size.new(block.size)) < 0
            place.call(block, left, top, tile_width, tile_height)
          end
        end
      else
        rows = Math.min(field_u32(tif, LibTIFF::ROWSPERSTRIP), height).to_i32
        block = Bytes.new(LibTIFF.TIFFStripSize(tif))
        (0...h).step(rows) do |top|
          index = LibTIFF.TIFFComputeStrip(tif, top.to_u32, 0_u16)
          raise ImageProbe::Error.new("unreadable TIFF strip") if LibTIFF.TIFFReadEncodedStrip(tif, index, block.to_unsafe.as(Void*), LibTIFF::Size.new(block.size)) < 0
          place.call(block, 0, top, w, rows)
        end
      end
      rgba
    end

    # A 16-bit sample, in the machine's byte order as libtiff hands it over,
    # at its nearest 8-bit level.
    private def self.level(block : Bytes, at : Int32) : UInt8
      ((IO::ByteFormat::SystemEndian.decode(UInt16, block[at, 2]).to_i32 + 128) // 257).to_u8
    end

    # Whether the one extra sample is alpha as it stands (unassociated, or
    # unspecified, which readers take as alpha).
    private def self.straight_alpha?(tif : LibTIFF::TIFF) : Bool
      count = 0_u16
      kinds = Pointer(UInt16).null
      return true if LibTIFF.TIFFGetFieldDefaulted(tif, LibTIFF::EXTRASAMPLES, pointerof(count), pointerof(kinds)) == 0 || count == 0
      count == 1 && kinds[0].in?(LibTIFF::EXTRASAMPLE_UNASSALPHA, LibTIFF::EXTRASAMPLE_UNSPECIFIED)
    end

    # Any other TIFF through libtiff's RGBA reader, which premultiplies by
    # alpha: undone here, so a partly clear pixel's colour comes back to
    # within a level or so.
    private def self.read_rgba(tif : LibTIFF::TIFF, width : UInt32, height : UInt32) : Bytes
      raster = Slice(UInt32).new(width.to_i32 * height.to_i32)
      if LibTIFF.TIFFReadRGBAImageOriented(tif, width, height, raster.to_unsafe, LibTIFF::ORIENTATION_TOPLEFT, 1) == 0
        raise ImageProbe::Error.new("unreadable TIFF")
      end
      rgba = Bytes.new(raster.size * 4)
      raster.each_with_index do |pixel, i|
        a = (pixel >> 24).to_i32
        3.times do |channel|
          value = ((pixel >> (channel * 8)) & 0xFF).to_i32
          value = Math.min(255, (value * 255 + a // 2) // a) if 0 < a < 255
          rgba[i * 4 + channel] = value.to_u8
        end
        rgba[i * 4 + 3] = a.to_u8
      end
      rgba
    end

    private def self.field_u32(tif : LibTIFF::TIFF, tag : UInt32) : UInt32
      value = 0_u32
      LibTIFF.TIFFGetFieldDefaulted(tif, tag, pointerof(value))
      value
    end

    private def self.field_u16(tif : LibTIFF::TIFF, tag : UInt32) : UInt16
      value = 0_u16
      LibTIFF.TIFFGetFieldDefaulted(tif, tag, pointerof(value))
      value
    end

    # libtiff on this IO, closed after; what it reported wrong is raised.
    # The callbacks rescue everything: an exception mustn't unwind through
    # libtiff.
    private def self.open(io : IO::Memory, mode : String, & : LibTIFF::TIFF -> T) : T forall T
      handle = Handle.new(io)
      box = Box.box(handle)
      options = LibTIFF.TIFFOpenOptionsAlloc
      LibTIFF.TIFFOpenOptionsSetErrorHandlerExtR(options, ->(_tif, data, _module, format, args) {
        message = Bytes.new(256)
        LibTIFF.vsnprintf(message.to_unsafe, LibC::SizeT.new(message.size), format, args)
        Box(Handle).unbox(data).errors << String.new(message.to_unsafe)
        1
      }, box)
      LibTIFF.TIFFOpenOptionsSetWarningHandlerExtR(options, ->(_tif, _data, _module, _format, _args) { 1 }, box)
      tif = LibTIFF.TIFFClientOpenExt("memory", mode, box,
        ->(data, buffer, size) {
          begin
            LibTIFF::Size.new(Box(Handle).unbox(data).io.read(Slice.new(buffer.as(UInt8*), size)))
          rescue
            LibTIFF::Size.new(-1)
          end
        },
        ->(data, buffer, size) {
          begin
            Box(Handle).unbox(data).io.write(Slice.new(buffer.as(UInt8*), size))
            size
          rescue
            LibTIFF::Size.new(-1)
          end
        },
        ->(data, offset, whence) {
          begin
            memory = Box(Handle).unbox(data).io
            memory.seek(offset.to_i64, IO::Seek.new(whence))
            memory.pos.to_u64
          rescue
            UInt64::MAX
          end
        },
        ->(_data) { 0 },
        ->(data) { Box(Handle).unbox(data).io.size.to_u64 },
        ->(_data, _base, _size) { 0 },
        ->(_data, _base, _size) { nil },
        options)
      LibTIFF.TIFFOpenOptionsFree(options)
      raise ImageProbe::Error.new("not a TIFF: #{handle.errors.first? || "libtiff refused it"}") if tif.null?
      begin
        result = yield tif
      ensure
        LibTIFF.TIFFClose(tif)
      end
      raise ImageProbe::Error.new("unreadable TIFF: #{handle.errors.first}") unless handle.errors.empty?
      result
    end
  end

  ImageProbe::DECODERS["image/tiff"] = ->TIFF.decode(Bytes)
  ImageProbe::ENCODERS["image/tiff"] = ->TIFF.encode(Int32, Int32, Bytes)
end
