require "spec"
require "file_utils"
require "compress/zlib"
require "digest/crc32"
require "../src/data_dungeon"
require "../src/data_dungeon/matches"

# Real image bytes, built here so the specs need no fixtures.

alias Pixel = {UInt8, UInt8, UInt8, UInt8}

private def rgba(width : Int32, height : Int32, & : Int32, Int32 -> Pixel) : Bytes
  io = IO::Memory.new
  height.times { |y| width.times { |x| p = yield x, y; io.write(Bytes[p[0], p[1], p[2], p[3]]) } }
  io.to_slice
end

private def png_chunk(io : IO, type : String, data : Bytes) : Nil
  io.write_bytes(data.size.to_u32, IO::ByteFormat::BigEndian)
  body = type.to_slice + data
  io.write(body)
  io.write_bytes(Digest::CRC32.checksum(body), IO::ByteFormat::BigEndian)
end

private def png(width : Int32, height : Int32, & : Int32, Int32 -> Pixel) : Bytes
  pixels = rgba(width, height) { |x, y| yield x, y }
  raw = IO::Memory.new
  height.times do |y|
    raw.write_byte(0_u8) # no filter
    raw.write(pixels[y * width * 4, width * 4])
  end
  compressed = IO::Memory.new
  Compress::Zlib::Writer.open(compressed) { |zlib| zlib.write(raw.to_slice) }
  ihdr = IO::Memory.new
  ihdr.write_bytes(width.to_u32, IO::ByteFormat::BigEndian)
  ihdr.write_bytes(height.to_u32, IO::ByteFormat::BigEndian)
  ihdr.write(Bytes[8, 6, 0, 0, 0]) # 8-bit RGBA
  io = IO::Memory.new
  io.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  png_chunk(io, "IHDR", ihdr.to_slice)
  png_chunk(io, "IDAT", compressed.to_slice)
  png_chunk(io, "IEND", Bytes.empty)
  io.to_slice
end

private def riff_chunk(type : String, data : Bytes) : Bytes
  io = IO::Memory.new
  io << type
  io.write_bytes(data.size.to_u32, IO::ByteFormat::LittleEndian)
  io.write(data)
  io.write_byte(0_u8) if data.size.odd?
  io.to_slice
end

private def riff_chunks(webp : Bytes) : Array({String, Bytes})
  chunks = [] of {String, Bytes}
  pos = 12
  while pos < webp.size
    type = String.new(webp[pos, 4])
    size = IO::ByteFormat::LittleEndian.decode(UInt32, webp[pos + 4, 4]).to_i32
    chunks << {type, webp[pos + 8, size]}
    pos += 8 + size + size % 2
  end
  chunks
end

private def u24(value : Int32) : Bytes
  Bytes[value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF]
end

# An animated WebP of these frames, each shown `each_ms`, looping forever.
private def animated_webp(width : Int32, height : Int32, frames : Array(Bytes), each_ms : Int32) : Bytes
  body = IO::Memory.new
  body << "WEBP"
  body.write(riff_chunk("VP8X", Bytes[0x12, 0, 0, 0] + u24(width - 1) + u24(height - 1))) # animation, alpha
  body.write(riff_chunk("ANIM", Bytes[0, 0, 0, 0, 0, 0]))
  frames.each do |pixels|
    still = DataDungeon::WebP.encode_webp_bytes(pixels, width, height)
    frame = IO::Memory.new
    frame.write(u24(0) + u24(0) + u24(width - 1) + u24(height - 1) + u24(each_ms) + Bytes[0])
    riff_chunks(still).each { |(type, data)| frame.write(riff_chunk(type, data)) unless type == "VP8X" }
    body.write(riff_chunk("ANMF", frame.to_slice))
  end
  riff = IO::Memory.new
  riff << "RIFF"
  riff.write_bytes(body.size.to_u32, IO::ByteFormat::LittleEndian)
  riff.write(body.to_slice)
  riff.to_slice
end

# A 5x4 GIF of two frames, 0.1 s each, looping forever: its blocks only
# (the pixel data isn't valid LZW, which DataDungeon never decodes).
private def gif : Bytes
  frame = Bytes[0x21, 0xF9, 4, 0, 10, 0, 0, 0,            # graphic control: 10 hundredths
    0x2C, 0, 0, 0, 0, 5, 0, 4, 0, 0, 2, 2, 0x4C, 0x01, 0] # image, LZW size, a sub-block
  "GIF89a".to_slice + Bytes[5, 0, 4, 0, 0x80, 0, 0] + Bytes[0, 0, 0, 255, 255, 255] +
    Bytes[0x21, 0xFF, 11] + "NETSCAPE2.0".to_slice + Bytes[3, 1, 0, 0, 0] + frame + frame + Bytes[0x3B]
end

private def jpeg : Bytes
  Bytes[0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, # an APP0 segment to skip
    0xFF, 0xC0, 0, 11, 8, 0, 30, 0, 40, 1, 1, 0x11, 0, 0xFF, 0xD9]
end

RED   = {255_u8, 0_u8, 0_u8, 255_u8}
BLUE  = {0_u8, 0_u8, 255_u8, 255_u8}
GREEN = {0_u8, 255_u8, 0_u8, 255_u8}
CLEAR = {0_u8, 0_u8, 0_u8, 0_u8}

private def with_db(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("prop", pool_traits: %w[thing], match_fields: %w[view dominant-color])
  db.register_type("plug", pool_traits: %w[motion])
  {"speech", "sequence", "script"}.each { |type| db.register_type(type, pool_traits: %w[name]) }
  yield db
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

describe DataDungeon::ImageProbe do
  it "measures a cut-out PNG: transparency, content box and dominant colour" do
    cutout = png(10, 8) { |x, y| 3 <= x < 7 && 2 <= y < 5 ? RED : CLEAR }
    found = DataDungeon::ImageProbe.measure(cutout, "image/png").not_nil!
    {found.width, found.height}.should eq({10, 8})
    found.transparent.should be_true
    found.content.should eq({3, 2, 4, 3})
    found.dominant_color.should eq 0xFF0000
    found.animation.should be_nil
  end

  it "measures an opaque picture by what most of it is" do
    mostly_blue = png(10, 10) { |x, _| x < 7 ? BLUE : GREEN }
    found = DataDungeon::ImageProbe.measure(mostly_blue, "image/png").not_nil!
    found.transparent.should be_false
    found.content.should eq({0, 0, 10, 10})
    found.dominant_color.should eq 0x0000FF
  end

  it "measures an animated WebP's first frame and its frames" do
    frames = [0, 1, 2].map { |n| rgba(16, 16) { |x, y| x < 4 + n * 4 && y < 8 ? RED : CLEAR } }
    found = DataDungeon::ImageProbe.measure(animated_webp(16, 16, frames, 100), "image/webp").not_nil!
    {found.width, found.height}.should eq({16, 16})
    found.content.should eq({0, 0, 4, 8})
    animation = found.animation.not_nil!
    {animation.frame_count, animation.duration_ms, animation.loop_count}.should eq({3, 300, 0})

    shown = DataDungeon::ImageProbe.decode_webp_frames(animated_webp(16, 16, frames, 100), [0, 150, 250, 999])
    shown.map { |(at, (w, h, pixels))| {at, DataDungeon::ImageProbe.content_box(w, h, pixels)} }
      .should eq [{0, {0, 0, 4, 8}}, {150, {0, 0, 8, 8}}, {250, {0, 0, 12, 8}}, {999, {0, 0, 12, 8}}]
  end

  it "reads a GIF's and a JPEG's size, and a GIF's frames, from their headers" do
    found = DataDungeon::ImageProbe.measure(gif, "image/gif").not_nil!
    {found.width, found.height, found.transparent}.should eq({5, 4, nil})
    animation = found.animation.not_nil!
    {animation.frame_count, animation.duration_ms, animation.loop_count}.should eq({2, 200, 0})

    photo = DataDungeon::ImageProbe.measure(jpeg, "image/jpeg").not_nil!
    {photo.width, photo.height, photo.transparent, photo.content}.should eq({40, 30, false, {0, 0, 40, 30}})
    photo.dominant_color.should be_nil
  end

  it "gives nothing for bytes that aren't the image they claim" do
    DataDungeon::ImageProbe.measure("not a png".to_slice, "image/png").should be_nil
    DataDungeon::ImageProbe.measure("RIFF".to_slice, "image/webp").should be_nil
    DataDungeon::ImageProbe.measure(Bytes[0xFF, 0xD8, 0x00], "image/jpeg").should be_nil
    DataDungeon::ImageProbe.measure("svg".to_slice, "image/svg+xml").should be_nil
  end
end

describe "Media" do
  it "takes an asset's medium from its content type" do
    {
      "image/png" => "image", "image/svg+xml" => "image", "audio/mpeg" => "audio", "video/webm" => "video",
      "text/plain; charset=utf-8" => "text", "application/json" => "text", "application/ld+json" => "text",
      "application/xml" => "text", "model/gltf-binary" => "model", "font/woff2" => "font",
      "application/pdf" => "data", "application/octet-stream" => "data",
    }.each { |content_type, media| DataDungeon::DB.media_of(content_type).should eq media }
  end

end

describe DataDungeon::Direction do
  it "turns readable views into vectors and back" do
    {
      {"front", 0.0, 0.0, {0.0, 0.0, 1.0}},
      {"front", 0.5, 0.0, {0.7071, 0.0, 0.7071}},
      {"front", 1.0, 0.0, {1.0, 0.0, 0.0}},
      {"back", 0.0, 1.0 / 3, {0.0, 0.5, -0.866}},
    }.each do |side, yaw, pitch, (x, y, z)|
      vx, vy, vz = DataDungeon::Direction.new(side, yaw, pitch).vector
      {vx.round(4), vy.round(4), vz.round(3)}.should eq({x, y, z.round(3)})
      back = DataDungeon::Direction.from(vx, vy, vz)
      {back.side, back.yaw.round(3), back.pitch.round(3)}.should eq({side, yaw.round(3), pitch.round(3)})
    end
    DataDungeon::Direction.from(0.0, 1.0, 0.0).yaw.should eq 0.0                                 # straight down: no yaw
    DataDungeon::Direction.from(3.0, 0.0, 4.0).vector.map(&.round(2)).should eq({0.6, 0.0, 0.8}) # made unit
  end

  it "names eight directions around, and from above or below" do
    DataDungeon::Direction.new("front").name.should eq "front"
    DataDungeon::Direction.new("front", 0.5).name.should eq "front-right"
    DataDungeon::Direction.new("back", -0.5).name.should eq "back-left"
    DataDungeon::Direction.new("back", -0.5, 0.5).name.should eq "back-left from-above"
    DataDungeon::Direction.new("front", 1.0, -0.4).name.should eq "right from-below"
    DataDungeon::Direction.new("front", 0.0, 0.9).name.should eq "top-down"
    DataDungeon::Direction.new("back", 0.0, -1.0).name.should eq "bottom-up"
  end

  it "refuses values out of range" do
    expect_raises(ArgumentError, /side/) { DataDungeon::Direction.new("left") }
    expect_raises(ArgumentError, /yaw/) { DataDungeon::Direction.new("front", 1.5) }
    expect_raises(ArgumentError, /zero vector/) { DataDungeon::Direction.from(0.0, 0.0, 0.0) }
  end
end

describe "Image fields" do
  it "fills what it measures when it stores a picture, and keeps the application's fields" do
    with_db("dd-image-store") do |db|
      cutout = png(10, 8) { |x, y| 3 <= x < 7 && 2 <= y < 5 ? RED : CLEAR }
      rec = db.store("prop", {"thing" => "lamp"}, bytes: cutout, content_type: "image/png",
        image: DataDungeon::ImageMeta.new(width: 512, usage_class: "prop", view: DataDungeon::Direction.new("back", -0.5),
          light: DataDungeon::Direction.new("front", -0.5, 0.5), anchor_x: 0.5, anchor_y: 1.0, world_height: 3.0))

      meta = db.load_image_meta(rec.id).not_nil!
      {meta.width, meta.height}.should eq({10, 8}) # measured, not as asked
      meta.measured?.should be_true
      {meta.transparent, meta.dominant_color, meta.content_w}.should eq({true, 0xFF0000, 4})
      meta.usage_class.should eq "prop"
      meta.view.not_nil!.name.should eq "back-left"
      meta.light.not_nil!.yaw.should eq -0.5
      {meta.anchor_x, meta.anchor_y, meta.world_height, meta.world_width}.should eq({0.5, 1.0, 3.0, nil})
      JSON.parse(meta.to_json)["dominant_color"].should eq "#ff0000"
      db.get_with_meta_by_id(rec.id, touch: false).not_nil![1].as(DataDungeon::ImageMeta).view_z.not_nil!.should be < 0
      db.list_assets(q: "back-left").map(&.id).should eq [rec.id] # the view is a search word
      db.connection.query_one("SELECT side, yaw, pitch FROM image_views WHERE asset_id = ?", rec.id,
        as: {String, Float64, Float64}).should eq({"back", -0.5, 0.0}) # readable at the sqlite3 prompt

      plain = db.store("prop", {"thing" => "sign"}, bytes: png(2, 2) { BLUE }, content_type: "image/png")
      db.load_image_meta(plain.id).not_nil!.dominant_color.should eq 0x0000FF # measured with no fields given
      expect_raises(ArgumentError, /anchor/) do
        db.store("prop", {"thing" => "x"}, bytes: png(1, 1) { RED }, content_type: "image/png",
          image: DataDungeon::ImageMeta.new(anchor_x: 2.0))
      end
    end
  end

  it "sets the application's fields on a stored picture, changing only those given" do
    with_db("dd-image-update") do |db|
      rec = db.store("prop", {"thing" => "lamp"}, bytes: png(4, 4) { RED }, content_type: "image/png",
        image: DataDungeon::ImageMeta.new(usage_class: "prop", world_height: 3.0))
      db.update_asset(rec.id, image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("front", 1.0),
        world_width: 0.4, animation: DataDungeon::ImageAnimation.new(frame_count: 4, duration_ms: 400, frame_w: 2, frame_h: 2, columns: 2)))

      meta = db.load_image_meta(rec.id).not_nil!
      {meta.usage_class, meta.world_height, meta.world_width}.should eq({"prop", 3.0, 0.4})
      meta.view.not_nil!.name.should eq "right"
      meta.animation.not_nil!.columns.should eq 2
      meta.dominant_color.should eq 0xFF0000 # measured fields untouched
      db.list_assets(q: "right").map(&.id).should eq [rec.id]

      voice = db.store("speech", bytes: "mp3".to_slice, content_type: "audio/mpeg")
      expect_raises(ArgumentError, /no image fields/) { db.update_asset(voice.id, image: DataDungeon::ImageMeta.new(world_width: 1.0)) }
    end
  end

  it "filters pictures by field ranges, a view within an angle, and a named direction" do
    with_db("dd-image-filter") do |db|
      store = ->(thing : String, height : Float64, view : DataDungeon::Direction) do
        db.store("prop", {"thing" => thing}, bytes: png(height.to_i, 2) { RED }, # a width each: other bytes
          content_type: "image/png", image: DataDungeon::ImageMeta.new(world_height: height, view: view))
      end
      lamp = store.call("lamp", 3.0, DataDungeon::Direction.new("front"))
      sign = store.call("sign", 1.5, DataDungeon::Direction.new("back", -0.5, 0.5))
      tree = store.call("tree", 6.0, DataDungeon::Direction.new("front", 1.0))
      ids = ->(filter : DataDungeon::ImageFilter) { db.list_assets("prop", image: filter).map(&.id) }

      ids.call(DataDungeon::ImageFilter.new({"world_height" => {2.0, 4.0}})).should eq [lamp.id]
      ids.call(DataDungeon::ImageFilter.new({"world_height" => {2.0, nil}})).should eq [tree.id, lamp.id]
      ids.call(DataDungeon::ImageFilter.new(view: DataDungeon::Direction.new("front", 0.25))).should eq [lamp.id]
      ids.call(DataDungeon::ImageFilter.new(view: DataDungeon::Direction.new("front", 0.5), view_within: 50.0))
        .should eq [tree.id, lamp.id]
      ids.call(DataDungeon::ImageFilter.new(direction: "back-left")).should eq [sign.id]
      ids.call(DataDungeon::ImageFilter.new(direction: "back-left from-above")).should eq [sign.id]
      ids.call(DataDungeon::ImageFilter.new(direction: "right")).should eq [tree.id]
      ids.call(DataDungeon::ImageFilter.new(direction: "front")).should eq [lamp.id]
      ids.call(DataDungeon::ImageFilter.new(direction: "top-down")).should be_empty
      db.count_assets("prop", image: DataDungeon::ImageFilter.new({"world_height" => {nil, 5.0}})).should eq 2
      expect_raises(ArgumentError, /isn't an image field/) { ids.call(DataDungeon::ImageFilter.new({"mood" => {1.0, 2.0}})) }
      expect_raises(ArgumentError, /isn't a named view/) { ids.call(DataDungeon::ImageFilter.new(direction: "north")) }
    end
  end

  it "counts a type's pictures by named direction, kept through every change" do
    with_db("dd-image-view-counts") do |db|
      view = ->(side : String, yaw : Float64, pitch : Float64) { DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new(side, yaw, pitch)) }
      a = db.store("prop", {"thing" => "a"}, bytes: png(1, 1) { RED }, content_type: "image/png", image: view.call("front", 0.0, 0.0))
      b = db.store("prop", {"thing" => "b"}, bytes: png(2, 1) { RED }, content_type: "image/png", image: view.call("back", -0.5, 0.5))
      c = db.store("prop", {"thing" => "c"}, bytes: png(3, 1) { RED }, content_type: "image/png", image: view.call("front", 0.0, 1.0))
      db.store("prop", {"thing" => "d"}, bytes: png(4, 1) { RED }, content_type: "image/png") # no view
      db.view_counts("prop").should eq({"back-left" => 1, "from-above" => 1, "front" => 1, "top-down" => 1})

      db.retire(b.id)
      db.view_counts("prop").should eq({"front" => 1, "top-down" => 1})
      db.view_counts("prop", retired: true).should eq({"back-left" => 1, "from-above" => 1})
      db.update_asset(a.id, image: view.call("back", -0.5, 0.0))
      db.view_counts("prop").should eq({"back-left" => 1, "top-down" => 1})
      db.delete_asset(c.id)
      db.rename_type("prop", "icon")
      db.view_counts("icon", retired: nil).should eq({"back-left" => 2, "from-above" => 1})
      db.view_counts("prop").should be_empty
      db.tag_keys("icon").keys.should eq ["thing"] # the counts aren't tags
      kept = db.connection.query_all("SELECT * FROM asset_tag_counts ORDER BY 1, 2, 3", as: {String, String, String, Int64, Int64})
      fresh = DataDungeon::DB::COUNT_TAGS.flat_map do |sql|
        db.connection.query_all(sql.sub(/\A\s*INSERT INTO[^\n]*\n/, ""), as: {String, String, String, Int64, Int64})
      end
      kept.should eq fresh.sort # as counted afresh

      expect_raises(ArgumentError, /@ are DataDungeon's/) do
        db.store("icon", {"@view" => "front"}, bytes: png(5, 1) { RED }, content_type: "image/png")
      end
      expect_raises(ArgumentError, /@ are DataDungeon's/) { db.rename_tag("icon", "thing", "@thing") }
    end
  end

  it "keeps an animation's checkpoints, measuring the content box at each" do
    with_db("dd-image-keyframes") do |db|
      frames = [0, 1, 2].map { |n| rgba(16, 16) { |x, y| x < 4 + n * 4 && y < 8 ? RED : CLEAR } }
      spin = db.store("plug", {"motion" => "spin"}, bytes: animated_webp(16, 16, frames, 100), content_type: "image/webp",
        image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("front"), world_depth: 40.0))
      still = db.store("plug", {"motion" => "none"}, bytes: png(3, 3) { RED }, content_type: "image/png",
        image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("front")))

      set = db.set_keyframes(spin.id, [
        DataDungeon::ImageKeyframe.new(200, view: DataDungeon::Direction.new("back")),
        DataDungeon::ImageKeyframe.new(100, view: DataDungeon::Direction.new("front", 1.0)),
        DataDungeon::ImageKeyframe.new(250, held: true, anchor_y: 0.9),
      ])
      set.map(&.at_ms).should eq [100, 200, 250]
      set.map(&.view.try(&.name)).should eq ["right", "back", nil]
      set.map { |k| {k.content_w, k.content_h} }.should eq [{8, 8}, {12, 8}, {nil, nil}] # measured where it changed
      set[2].held?.should be_true
      db.load_keyframes(spin.id).should eq set

      ever = ->(filter : DataDungeon::ImageFilter) { db.list_assets("plug", image: filter).map(&.id) }
      ever.call(DataDungeon::ImageFilter.new(direction: "back")).should eq [spin.id] # at a checkpoint
      ever.call(DataDungeon::ImageFilter.new(direction: "front")).should eq [still.id, spin.id]
      ever.call(DataDungeon::ImageFilter.new({"content_w" => {10, 12}})).should eq [spin.id]
      ever.call(DataDungeon::ImageFilter.new({"world_depth" => {30, 50}, "view_z" => {nil, -0.87}})).should eq [spin.id]

      expect_raises(ArgumentError, /more than 90 degrees/) do
        db.set_keyframes(spin.id, [DataDungeon::ImageKeyframe.new(100, view: DataDungeon::Direction.new("back"))])
      end
      expect_raises(ArgumentError, /after the start/) { db.set_keyframes(spin.id, [DataDungeon::ImageKeyframe.new(0)]) }
      expect_raises(ArgumentError, /past the end/) { db.set_keyframes(spin.id, [DataDungeon::ImageKeyframe.new(301)]) }
      expect_raises(ArgumentError, /isn't an animation/) { db.set_keyframes(still.id, [DataDungeon::ImageKeyframe.new(1)]) }
      db.load_keyframes(spin.id).size.should eq 3 # a refused change changes nothing

      db.delete_asset(spin.id)
      db.connection.scalar("SELECT COUNT(*) FROM image_keyframes").should eq 0
    end
  end

  it "measures pictures stored before it measured them" do
    with_db("dd-image-measure") do |db|
      rec = db.store("prop", {"thing" => "lamp"}, bytes: png(6, 6) { |x, _| x < 3 ? GREEN : CLEAR }, content_type: "image/png")
      db.connection.exec("UPDATE image_meta SET measured = NULL, content_w = NULL, dominant_color = NULL")
      gif_rec = db.store("sequence", bytes: gif, content_type: "image/gif")
      db.connection.exec("DELETE FROM image_meta WHERE asset_id = ?", gif_rec.id)
      db.connection.exec("DELETE FROM image_animation WHERE asset_id = ?", gif_rec.id)

      script = db.store("script", bytes: %({"lines":[]}).to_slice, content_type: "application/json")
      db.measure_images.should eq 2
      db.measure_images.should eq 0               # nothing left
      db.load_image_meta(script.id).should be_nil # not a picture, whatever its media says
      meta = db.load_image_meta(rec.id).not_nil!
      {meta.content_w, meta.dominant_color, meta.measured?}.should eq({3, 0x00FF00, true})
      db.load_image_meta(gif_rec.id).not_nil!.animation.not_nil!.frame_count.should eq 2
      db.measure_images("prop", all: true).should eq 1
    end
  end

end

describe "Best matches on image fields" do
  it "ranks a cycle's neighbours before its opposite" do
    with_db("dd-match-cycle") do |db|
      db.register_type("drop", pool_traits: %w[place time], cycles: {"time" => %w[Dawn day dusk night]})
      ids = %w[day dusk dawn].to_h do |time|
        {time, db.store("drop", {"place" => "park", "time" => time}, bytes: time.to_slice, content_type: "text/plain").id}
      end
      index = DataDungeon::MatchIndex.new(db)
      begin
        found = index.best_matches("drop", {"time" => "night"})
        found.first(2).map(&.asset.id).sort.should eq [ids["dusk"], ids["dawn"]].sort
        found.first(2).each { |match| match.score.should be_close(0.5, 1e-9) }
        found.last.asset.id.should eq ids["day"]
        found.last.score.should be_close(0.0, 1e-9)
      ensure
        index.close
      end
      expect_raises(ArgumentError, /at least three/) { db.register_type("data", pool_traits: %w[a], cycles: {"a" => %w[x y]}) }
      expect_raises(ArgumentError, /can't be matched on/) { db.register_type("data", pool_traits: %w[a], match_fields: %w[mood]) }
    end
  end

  it "matches pictures by view and dominant colour" do
    with_db("dd-match-fields") do |db|
      db.register_type("prop", pool_traits: %w[thing], match_fields: %w[view dominant-color])
      red = db.store("prop", {"thing" => "lamp"}, bytes: png(2, 2) { RED }, content_type: "image/png",
        image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("front")))
      blue = db.store("prop", {"thing" => "sign"}, bytes: png(3, 2) { BLUE }, content_type: "image/png",
        image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("front", 1.0)))
      dark_red = db.store("prop", {"thing" => "bin"}, bytes: png(4, 2) { {200_u8, 10_u8, 10_u8, 255_u8} }, content_type: "image/png",
        image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("back")))
      index = DataDungeon::MatchIndex.new(db)
      begin
        by_view = index.best_matches("prop", {"view" => "front-right"})
        by_view.first(2).map(&.asset.id).sort.should eq [red.id, blue.id].sort
        by_view.first.score.should be_close(0.707, 0.001)
        by_view.last.asset.id.should eq dark_red.id

        index.best_matches("prop", {"dominant-color" => "#ff0000"}).map(&.asset.id).should eq [red.id, dark_red.id, blue.id]
        index.best_matches("prop", {"view" => "back,0,0", "dominant-color" => "red"}).first.asset.id.should eq dark_red.id
        index.similar(red.id).first.asset.id.should eq dark_red.id # alike in colour, though it faces away

        db.update_asset(blue.id, image: DataDungeon::ImageMeta.new(view: DataDungeon::Direction.new("back")))
        index.best_matches("prop", {"view" => "back"}).first(2).map(&.asset.id).sort.should eq [blue.id, dark_red.id].sort
        expect_raises(ArgumentError, /not traits/) { index.best_matches("prop", {"view" => "back"}, require: %w[view]) }
        expect_raises(ArgumentError, /isn't a named direction/) { index.best_matches("prop", {"view" => "north"}) }
      ensure
        index.close
      end
    end
  end
end
