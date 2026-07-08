@[Link("png16")]
lib LibPNG
  alias SizeT = LibC::SizeT

  type PngStructP = Void*
  type PngInfoP = Void*

  fun png_create_read_struct(user_png_ver : UInt8*, error_ptr : Void*, error_fn : Void*, warn_fn : Void*) : PngStructP
  fun png_create_info_struct(png_ptr : PngStructP) : PngInfoP
  fun png_destroy_read_struct(png_ptr_ptr : PngStructP*, info_ptr_ptr : PngInfoP*, end_info_ptr_ptr : Void*) : Void
  fun png_init_io(png_ptr : PngStructP, fp : Void*) : Void
  fun png_read_info(png_ptr : PngStructP, info_ptr : PngInfoP) : Void
  fun png_get_image_width(png_ptr : PngStructP, info_ptr : PngInfoP) : UInt32
  fun png_get_image_height(png_ptr : PngStructP, info_ptr : PngInfoP) : UInt32
  fun png_get_color_type(png_ptr : PngStructP, info_ptr : PngInfoP) : UInt8
  fun png_get_bit_depth(png_ptr : PngStructP, info_ptr : PngInfoP) : UInt8
  fun png_set_expand(png_ptr : PngStructP) : Void
  fun png_set_gray_to_rgb(png_ptr : PngStructP) : Void
  fun png_set_add_alpha(png_ptr : PngStructP, filler : UInt32, flags : Int32) : Void
  fun png_set_strip_16(png_ptr : PngStructP) : Void
  fun png_set_interlace_handling(png_ptr : PngStructP) : Int32
  fun png_read_update_info(png_ptr : PngStructP, info_ptr : PngInfoP) : Void
  fun png_get_rowbytes(png_ptr : PngStructP, info_ptr : PngInfoP) : SizeT
  fun png_read_image(png_ptr : PngStructP, row_pointers : UInt8**) : Void
  fun png_read_end(png_ptr : PngStructP, info_ptr : PngInfoP) : Void
end

@[Link("webp")]
lib LibWebP
  fun WebPEncodeRGBA(rgba : UInt8*, width : Int32, height : Int32, stride : Int32,
                     quality_factor : Float32, output : UInt8**) : LibC::SizeT
  fun WebPFree(ptr : Void*) : Void
end

# libc fopen/fclose for libpng I/O
lib LibC
  fun fopen(filename : UInt8*, mode : UInt8*) : Void*
  fun fclose(stream : Void*) : Int32
end

module DataDungeon
  module WebP
    QUALITY = 85_f32

    # Decode a PNG file to raw RGBA pixels.
    # Returns {width, height, rgba_bytes}.
    def self.decode_png(png_path : String) : {Int32, Int32, Bytes}
      fp = LibC.fopen(png_path.to_unsafe, "rb".to_unsafe)
      raise "Cannot open #{png_path}" if fp.null?

      png_ptr = LibPNG.png_create_read_struct("1.6.0".to_unsafe, nil, nil, nil)
      raise "png_create_read_struct failed" if png_ptr.null?

      info_ptr = LibPNG.png_create_info_struct(png_ptr)
      if info_ptr.null?
        LibPNG.png_destroy_read_struct(pointerof(png_ptr), nil, nil)
        raise "png_create_info_struct failed"
      end

      LibPNG.png_init_io(png_ptr, fp)
      LibPNG.png_read_info(png_ptr, info_ptr)

      width = LibPNG.png_get_image_width(png_ptr, info_ptr).to_i32
      height = LibPNG.png_get_image_height(png_ptr, info_ptr).to_i32
      color_type = LibPNG.png_get_color_type(png_ptr, info_ptr)
      bit_depth = LibPNG.png_get_bit_depth(png_ptr, info_ptr)

      # Normalize to 8-bit RGBA regardless of input format
      LibPNG.png_set_expand(png_ptr)       # expand palette/gray/tRNS to RGB(A)
      LibPNG.png_set_gray_to_rgb(png_ptr)  # gray → RGB
      if bit_depth == 16
        LibPNG.png_set_strip_16(png_ptr)   # 16-bit → 8-bit
      end
      # Add alpha channel if missing (PNG_FILLER_AFTER = 1)
      if (color_type & 0x04) == 0  # no alpha
        LibPNG.png_set_add_alpha(png_ptr, 0xFF_u32, 1)
      end
      LibPNG.png_set_interlace_handling(png_ptr)
      LibPNG.png_read_update_info(png_ptr, info_ptr)

      rowbytes = LibPNG.png_get_rowbytes(png_ptr, info_ptr).to_i32
      pixels = Bytes.new(height * rowbytes)

      # Build row pointer array
      row_pointers = Pointer(UInt8*).malloc(height)
      height.times do |y|
        row_pointers[y] = pixels.to_unsafe + y * rowbytes
      end

      LibPNG.png_read_image(png_ptr, row_pointers)
      LibPNG.png_read_end(png_ptr, info_ptr)
      LibPNG.png_destroy_read_struct(pointerof(png_ptr), pointerof(info_ptr), nil)
      LibC.fclose(fp)

      {width, height, pixels}
    end

    # Encode RGBA pixels to a WebP file. Returns output file size in bytes.
    def self.encode_webp(rgba : Bytes, width : Int32, height : Int32, webp_path : String,
                         quality : Float32 = QUALITY) : Int64
      stride = width * 4
      output_ptr = Pointer(UInt8).null
      size = LibWebP.WebPEncodeRGBA(rgba.to_unsafe, width, height, stride, quality, pointerof(output_ptr))
      raise "WebP encode failed" if size == 0 || output_ptr.null?

      begin
        File.open(webp_path, "wb") do |f|
          f.write(Slice.new(output_ptr, size))
        end
        size.to_i64
      ensure
        LibWebP.WebPFree(output_ptr.as(Void*))
      end
    end

    # Encode RGBA pixels to WebP in memory. Returns the encoded bytes.
    def self.encode_webp_bytes(rgba : Bytes, width : Int32, height : Int32,
                               quality : Float32 = QUALITY) : Bytes
      stride = width * 4
      output_ptr = Pointer(UInt8).null
      size = LibWebP.WebPEncodeRGBA(rgba.to_unsafe, width, height, stride, quality, pointerof(output_ptr))
      raise "WebP encode failed" if size == 0 || output_ptr.null?

      begin
        bytes = Bytes.new(size)
        Slice.new(output_ptr, size).copy_to(bytes)
        bytes
      ensure
        LibWebP.WebPFree(output_ptr.as(Void*))
      end
    end

    # Convert PNG bytes to WebP bytes. libpng reads through a real file
    # descriptor, so the input is staged to a temp file for decoding.
    def self.png_to_webp_bytes(png : Bytes, quality : Float32 = QUALITY) : Bytes
      tmp = File.tempfile("dd-png", ".png")
      begin
        File.write(tmp.path, png)
        width, height, pixels = decode_png(tmp.path)
        encode_webp_bytes(pixels, width, height, quality)
      ensure
        tmp.delete
      end
    end

    # Convert a PNG file to WebP. Returns the new .webp path.
    def self.encode(png_path : String, webp_path : String, quality : Float32 = QUALITY) : Int64
      width, height, pixels = decode_png(png_path)
      encode_webp(pixels, width, height, webp_path, quality)
    end

    # In-place conversion: writes .webp sibling, deletes the original, returns new path.
    def self.convert!(path : String, quality : Float32 = QUALITY) : String
      webp_path = path.sub(/\.png\z/i, ".webp")
      raise "Not a .png file: #{path}" if webp_path == path
      encode(path, webp_path, quality)
      File.delete(path)
      webp_path
    end
  end
end
