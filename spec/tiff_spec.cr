require "spec"
require "file_utils"
require "compress/zlib"
require "digest/crc32"
require "../src/data_dungeon/http"
require "../src/data_dungeon/tiff"

# TIFF masters (Thomas, 2026-10-20: tiled TIFF, 8-bit, for the park's
# originals), built here byte by byte so libtiff reads files DataDungeon
# didn't write.

alias Pixel16 = {UInt16, UInt16, UInt16, UInt16}

# A baseline TIFF: one uncompressed strip of RGBA, 8 or 16 bits a sample,
# unassociated alpha, as GIMP exports one.
private def tiff(width : Int32, height : Int32, bits : Int32, & : Int32, Int32 -> Pixel16) : Bytes
  pixels = IO::Memory.new
  height.times do |y|
    width.times do |x|
      sample = yield x, y
      sample.each { |value| bits == 16 ? pixels.write_bytes(value, IO::ByteFormat::LittleEndian) : pixels.write_byte((value >> 8).to_u8) }
    end
  end
  entries = [
    {256_u16, 4_u16, 1_u32, width.to_u32}, {257_u16, 4_u16, 1_u32, height.to_u32},
    {258_u16, 3_u16, 4_u32, 0_u32}, # bits per sample: four, kept after the IFD
    {259_u16, 3_u16, 1_u32, 1_u32}, {262_u16, 3_u16, 1_u32, 2_u32},
    {273_u16, 4_u16, 1_u32, 0_u32}, # strip offset: after the bits
    {277_u16, 3_u16, 1_u32, 4_u32}, {278_u16, 4_u16, 1_u32, height.to_u32},
    {279_u16, 4_u16, 1_u32, pixels.size.to_u32}, {284_u16, 3_u16, 1_u32, 1_u32},
    {338_u16, 3_u16, 1_u32, 2_u32}, # unassociated alpha
  ]
  ifd_end = 8 + 2 + entries.size * 12 + 4
  io = IO::Memory.new
  io.write("II".to_slice)
  io.write_bytes(42_u16, IO::ByteFormat::LittleEndian)
  io.write_bytes(8_u32, IO::ByteFormat::LittleEndian)
  io.write_bytes(entries.size.to_u16, IO::ByteFormat::LittleEndian)
  entries.each do |(tag, type, count, value)|
    value = ifd_end.to_u32 if tag == 258
    value = (ifd_end + 8).to_u32 if tag == 273
    io.write_bytes(tag, IO::ByteFormat::LittleEndian)
    io.write_bytes(type, IO::ByteFormat::LittleEndian)
    io.write_bytes(count, IO::ByteFormat::LittleEndian)
    if type == 3 && count == 1 # a short, padded to the value's four bytes
      io.write_bytes(value.to_u16, IO::ByteFormat::LittleEndian)
      io.write_bytes(0_u16, IO::ByteFormat::LittleEndian)
    else
      io.write_bytes(value, IO::ByteFormat::LittleEndian)
    end
  end
  io.write_bytes(0_u32, IO::ByteFormat::LittleEndian)
  4.times { io.write_bytes(bits.to_u16, IO::ByteFormat::LittleEndian) }
  io.write(pixels.to_slice)
  io.to_slice
end

# A 16-bit RGBA PNG with no gAMA or sRGB chunk, which libpng's simplified
# reader would take for linear light.
private def png16(width : Int32, height : Int32, & : Int32, Int32 -> Pixel16) : Bytes
  raw = IO::Memory.new
  height.times do |y|
    raw.write_byte(0_u8)
    width.times { |x| (yield x, y).each { |value| raw.write_bytes(value, IO::ByteFormat::BigEndian) } }
  end
  compressed = IO::Memory.new
  Compress::Zlib::Writer.open(compressed) { |zlib| zlib.write(raw.to_slice) }
  chunk = ->(io : IO, type : String, data : Bytes) do
    io.write_bytes(data.size.to_u32, IO::ByteFormat::BigEndian)
    body = type.to_slice + data
    io.write(body)
    io.write_bytes(Digest::CRC32.checksum(body), IO::ByteFormat::BigEndian)
  end
  ihdr = IO::Memory.new
  ihdr.write_bytes(width.to_u32, IO::ByteFormat::BigEndian)
  ihdr.write_bytes(height.to_u32, IO::ByteFormat::BigEndian)
  ihdr.write(Bytes[16, 6, 0, 0, 0])
  io = IO::Memory.new
  io.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  chunk.call(io, "IHDR", ihdr.to_slice)
  chunk.call(io, "IDAT", compressed.to_slice)
  chunk.call(io, "IEND", Bytes.empty)
  io.to_slice
end

# The first IFD's tags, each with its first value, as libtiff writes a
# little-endian file: the layout a stored TIFF has.
private def tags(bytes : Bytes) : Hash(Int32, Int32)
  format = IO::ByteFormat::LittleEndian
  at = format.decode(UInt32, bytes[4, 4]).to_i32
  found = {} of Int32 => Int32
  format.decode(UInt16, bytes[at, 2]).times do |i|
    entry = at + 2 + i * 12
    tag, type, count = format.decode(UInt16, bytes[entry, 2]).to_i32, format.decode(UInt16, bytes[entry + 2, 2]), format.decode(UInt32, bytes[entry + 4, 4])
    size = type == 3 ? 2 : 4
    value = count * size <= 4 ? entry + 8 : format.decode(UInt32, bytes[entry + 8, 4]).to_i32
    found[tag] = size == 2 ? format.decode(UInt16, bytes[value, 2]).to_i32 : format.decode(UInt32, bytes[value, 4]).to_i32
  end
  found
end

# A 70×50 cut-out: clear around a box from (10, 5) to (59, 44), whose left
# half is a 16-bit red that isn't an 8-bit level, half see-through at its
# left edge; the rest blue.
private def cut_out(x : Int32, y : Int32) : Pixel16
  return {0_u16, 0_u16, 0_u16, 0_u16} unless 10 <= x < 60 && 5 <= y < 45
  return {0_u16, 0_u16, 65535_u16, 65535_u16} if x >= 35
  {51_000_u16, 1_000_u16, 1_000_u16, x == 10 ? 32_768_u16 : 65535_u16}
end

private def with_db(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("prop", pool_traits: %w[thing fmt])
  yield db, dir
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

private def answer(api, request : HTTP::Request) : HTTP::Client::Response
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  api.call(HTTP::Server::Context.new(request, response))
  response.close
  HTTP::Client::Response.from_io(io.rewind)
end

describe "TIFF" do
  it "reads 8- and 16-bit TIFFs, 16 bits rounded to the nearest 8-bit level" do
    {8, 16}.each do |bits|
      width, height, rgba = DataDungeon::ImageProbe.decode(tiff(70, 50, bits) { |x, y| cut_out(x, y) }, "image/tiff")
      {width, height}.should eq({70, 50})
      at = ->(x : Int32, y : Int32) { rgba[(y * 70 + x) * 4, 4].to_a }
      at.call(0, 0).should eq [0, 0, 0, 0]
      at.call(20, 20).should eq(bits == 16 ? [198, 4, 4, 255] : [199, 3, 3, 255]) # 51000/257 rounds; >> 8 truncates
      at.call(10, 20)[3].should eq 128
      at.call(40, 20).should eq [0, 0, 255, 255]
    end
    expect_raises(DataDungeon::ImageProbe::Error, /not a TIFF/) { DataDungeon::TIFF.decode("not a tiff".to_slice) }
  end

  it "measures a stored TIFF, as .tif" do
    with_db("dd-tiff-measure") do |db|
      rec = db.store("prop", {"thing" => "barrel", "fmt" => "tif"}, bytes: tiff(70, 50, 16) { |x, y| cut_out(x, y) }, content_type: "image/tiff")
      rec.file_path.should end_with ".tif"
      image = db.load_image_meta(rec.id).not_nil!
      {image.width, image.height, image.transparent, image.measured?}.should eq({70, 50, true, true})
      {image.content_x, image.content_y, image.content_w, image.content_h}.should eq({10, 5, 50, 40})
      image.dominant_color.should eq 0x0000FF # the blue half outweighs the red, with its see-through edge

      broken = db.store("prop", {"thing" => "crate", "fmt" => "tif"}, bytes: "II*\0 and nothing".to_slice, content_type: "image/tiff")
      db.load_image_meta(broken.id).not_nil!.width.should be_nil
    end
  end

  it "stores a TIFF or a PNG as 8-bit TIFF in 64×64 deflate tiles when asked" do
    with_db("dd-tiff-tiles") do |db|
      as_tiles = DataDungeon::ImageMeta.new(compression: "normalize", target_format: "tiff")
      given = tiff(70, 50, 16) { |x, y| cut_out(x, y) }
      rec = db.store("prop", {"thing" => "barrel", "fmt" => "tif"}, bytes: given, content_type: "image/tiff", image: as_tiles)
      rec.content_type.should eq "image/tiff"
      stored = db.read(rec)
      tags(stored).select(258, 259, 277, 317, 322, 323).should eq({258 => 8, 259 => 8, 277 => 4, 317 => 2, 322 => 64, 323 => 64})
      DataDungeon::TIFF.decode(stored).should eq DataDungeon::ImageProbe.decode(given, "image/tiff")
      db.load_image_meta(rec.id).not_nil!.content_w.should eq 50

      # The same pixels make the same file, so storing them again is a repeat.
      db.store("prop", {"thing" => "barrel", "fmt" => "tif"}, bytes: given, content_type: "image/tiff", image: as_tiles).id.should eq rec.id

      # A PNG, and an opaque picture, which keeps no alpha.
      opaque = png16(70, 50) { |x, y| {51_000_u16, 1_000_u16, (x * 900).to_u16, 65535_u16} }
      flat = db.store("prop", {"thing" => "wall", "fmt" => "tif"}, bytes: opaque, content_type: "image/png", image: as_tiles)
      {flat.content_type, tags(db.read(flat))[277]}.should eq({"image/tiff", 3})
      DataDungeon::TIFF.decode(db.read(flat))[2][0, 4].should eq Bytes[198, 4, 0, 255]
    end
  end

  it "reads a 16-bit PNG with no gamma as stored, not as linear light" do
    width, height, rgba = DataDungeon::ImageProbe.decode(png16(70, 50) { |x, y| cut_out(x, y) }, "image/png")
    {width, height}.should eq({70, 50})
    rgba[(20 * 70 + 20) * 4, 4].to_a.should eq [198, 4, 4, 255]
    rgba[(20 * 70 + 10) * 4 + 3].should eq 128
  end

  it "makes a picture's WebP: an asset of its own, derived from it" do
    with_db("dd-tiff-webp") do |db|
      master = db.store("prop", {"thing" => "barrel", "fmt" => "tif"}, bytes: tiff(70, 50, 8) { |x, y| cut_out(x, y) },
        content_type: "image/tiff", description: "A barrel, cut out.", permanent: true,
        image: DataDungeon::ImageMeta.new(anchor_x: 0.5, anchor_y: 0.9))
      db.update_asset(master.id, rating: 3)
      webp = db.store_webp(master.id, {"fmt" => "webp"})
      {webp.asset_type, webp.content_type, webp.description, webp.rating, webp.permanent}.should eq({"prop", "image/webp", "A barrel, cut out.", 3, false})
      db.load_tags(webp.id).should eq({"thing" => "barrel", "fmt" => "webp"})
      image = db.load_image_meta(webp.id).not_nil!
      {image.width, image.height, image.anchor_x, image.anchor_y, image.content_x, image.content_w}.should eq({70, 50, 0.5, 0.9, 10, 50})
      link = db.links_from(webp.id, "derived-from").first
      {link.to_id, link.data.try(&.["quality"].as_i)}.should eq({master.id, 85})

      db.store_webp(master.id, {"fmt" => "webp"}).id.should eq webp.id # a repeat
      expect_raises(DataDungeon::AlreadyStored) { db.store_webp(master.id, {"fmt" => "web"}) }
      db.store_webp(master.id, {"fmt" => "webp-60"}, quality: 60).id.should_not eq webp.id
      expect_raises(ArgumentError, /quality/) { db.store_webp(master.id, quality: 101) }

      xcf = db.store("prop", {"thing" => "barrel", "fmt" => "xcf"}, bytes: "gimp xcf v012\0".to_slice, content_type: "image/x-xcf")
      xcf.file_path.should end_with ".xcf"
      expect_raises(ArgumentError, /image\/x-xcf/) { db.store_webp(xcf.id) }
    end
  end

  it "stores uploads as TIFF tiles and makes their WebP over HTTP" do
    with_db("dd-tiff-http") do |db|
      api = DataDungeon::API.new(db, write_token: "w")
      io = IO::Memory.new
      form = HTTP::FormData::Builder.new(io)
      form.file("file", IO::Memory.new(tiff(70, 50, 16) { |x, y| cut_out(x, y) }), HTTP::FormData::FileMetadata.new(filename: "barrel.tif"),
        HTTP::Headers{"Content-Type" => "image/tiff"})
      form.field("asset", {type: "prop", tags: {thing: "barrel", fmt: "tif"}, description: "A barrel.",
                           image: {compression: "normalize", target_format: "tiff", anchor_x: 0.5, anchor_y: 1}}.to_json)
      form.finish
      headers = HTTP::Headers{"Content-Type" => form.content_type, "Authorization" => "Bearer w"}
      stored = JSON.parse(answer(api, HTTP::Request.new("POST", "/assets", headers, io.to_s)).body)["asset"]
      id = stored["id"].as_i64
      tags(db.read(db.find_asset_by_id(id).not_nil!))[322].should eq 64

      post = ->(body : String) { answer(api, HTTP::Request.new("POST", "/assets/#{id}/webp", HTTP::Headers{"Authorization" => "Bearer w"}, body)) }
      made = post.call({tags: {fmt: "webp"}, quality: 80}.to_json)
      made.status_code.should eq 200
      webp = JSON.parse(made.body)
      {webp["asset"]["content_type"].as_s, webp["tags"]["fmt"].as_s}.should eq({"image/webp", "webp"})
      db.load_image_meta(webp["asset"]["id"].as_i64).not_nil!.anchor_y.should eq 1.0
      post.call({tags: {fmt: "web"}, quality: 80}.to_json).status_code.should eq 409
      answer(api, HTTP::Request.new("POST", "/assets/999/webp", HTTP::Headers{"Authorization" => "Bearer w"})).status_code.should eq 404
      answer(api, HTTP::Request.new("POST", "/assets/#{id}/webp")).status_code.should eq 403
    end
  end
end
