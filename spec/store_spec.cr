require "spec"
require "file_utils"
require "../src/data_dungeon"

# Exercises the high-level store/get path (v0.3 "owns the write path").
# Uses `original` compression + webp passthrough so the tests don't depend on
# libpng/libwebp encoding — the WebP conversion path is covered separately.
private def open_db(dir : String) : DataDungeon::DB
  DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
end

describe DataDungeon::DB do
  it "stores an asset, owns the file, and finds it via get" do
    dir = File.tempname("dd-store")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade", "style" => "silver"}

    rec = db.store("venue", tags,
      bytes: "webp-bytes".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    rec.asset_type.should eq "venue"
    rec.file_hash.should_not be_nil
    rec.file_path.starts_with?("venue/").should be_true
    File.exists?(db.path_for(rec)).should be_true

    got = db.get("venue", tags)
    got.should_not be_nil
    got.not_nil!.id.should eq rec.id
    db.find_asset_by_id(rec.id).not_nil!.use_count.should eq 1  # get touched it
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "write-skips an identical single-best re-store (same id, no rewrite)" do
    dir = File.tempname("dd-dedup")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}
    payload = "same-bytes".to_slice

    a = db.store("venue", tags, bytes: payload, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("venue", tags, bytes: payload, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    b.id.should eq a.id            # write-skip returned the existing record
    b.file_hash.should eq a.file_hash
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "replaces a single-best asset when the bytes change" do
    dir = File.tempname("dd-replace")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    a = db.store("venue", tags, bytes: "v1".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("venue", tags, bytes: "v2".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    b.id.should_not eq a.id
    b.file_hash.should_not eq a.file_hash
    db.find_asset_by_id(a.id).should be_nil  # old row replaced
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "self-heals to a miss when the backing file is gone" do
    dir = File.tempname("dd-heal")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    rec = db.store("venue", tags, bytes: "bytes".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    File.delete(db.path_for(rec))

    db.get("venue", tags).should be_nil
    db.find_asset("venue", tags).should_not be_nil  # row still there; get self-heals
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "returns record + image meta in one call via get_with_image_meta" do
    dir = File.tempname("dd-eager")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}
    pins = {"water" => 0.62}.to_json

    stored = db.store("venue", tags, bytes: "webp".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original", usage_class: "bg", presentation: pins))

    pair = db.get_with_image_meta("venue", tags)
    pair.should_not be_nil
    rec, meta = pair.not_nil!
    rec.id.should eq stored.id
    meta.should_not be_nil
    meta.not_nil!.presentation.should eq pins
    meta.not_nil!.usage_class.should eq "bg"

    db.get_with_image_meta("venue", {"venue" => "missing"}).should be_nil
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "does not touch usage when touch: false" do
    dir = File.tempname("dd-notouch")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    rec = db.store("venue", tags, bytes: "webp".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    db.get("venue", tags, touch: false)
    db.get_with_image_meta("venue", tags, touch: false)

    db.find_asset_by_id(rec.id).not_nil!.use_count.should eq 0  # no write on read
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps distinct pool members content-addressed" do
    dir = File.tempname("dd-pool")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"quest" => "zork"}

    a = db.store("banter", tags, pool: true, bytes: "candidate-A".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("banter", tags, pool: true, bytes: "candidate-B".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))

    a.id.should_not eq b.id
    a.file_path.should_not eq b.file_path
    File.exists?(db.path_for(a)).should be_true
    File.exists?(db.path_for(b)).should be_true
    db.count_pool_assets("banter", tags).should eq 2
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end
end
