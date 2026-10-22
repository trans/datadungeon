@[Link("webp")]
lib LibWebP
  fun WebPEncodeRGBA(rgba : UInt8*, width : Int32, height : Int32, stride : Int32,
                     quality_factor : Float32, output : UInt8**) : LibC::SizeT
  fun WebPFree(ptr : Void*) : Void
end

module DataDungeon
  module WebP
    QUALITY = 85_f32

    # Decode a PNG file to raw RGBA pixels: {width, height, rgba_bytes}.
    # Through ImageProbe's reader, which turns a bad file into an error;
    # libpng's own reader, used here before 0.16.2, aborted the process.
    def self.decode_png(png_path : String) : {Int32, Int32, Bytes}
      ImageProbe.decode_png(File.open(png_path, &.getb_to_end))
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

    # Convert PNG bytes to WebP bytes.
    def self.png_to_webp_bytes(png : Bytes, quality : Float32 = QUALITY) : Bytes
      width, height, pixels = ImageProbe.decode_png(png)
      encode_webp_bytes(pixels, width, height, quality)
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
