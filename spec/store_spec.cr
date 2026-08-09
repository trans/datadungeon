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

  it "returns record + polymorphic image meta in one call via get_with_meta" do
    dir = File.tempname("dd-eager")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}
    pins = {"water" => 0.62}.to_json

    stored = db.store("venue", tags, bytes: "webp".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original", usage_class: "bg", presentation: pins))

    pair = db.get_with_meta("venue", tags)
    pair.should_not be_nil
    rec, meta = pair.not_nil!
    rec.id.should eq stored.id
    meta.should_not be_nil
    meta.not_nil!.presentation.should eq pins           # base accessor, no narrowing
    meta.should be_a DataDungeon::ImageMeta
    meta.as(DataDungeon::ImageMeta).usage_class.should eq "bg"  # narrow for specifics

    db.get_with_meta("venue", {"venue" => "missing"}).should be_nil
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "dispatches get_with_meta to the right sidecar per media" do
    dir = File.tempname("dd-poly")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    # audio asset → AudioMeta (presentation is nil for non-visual media)
    atags = {"line" => "greeting"}
    db.store("banter", atags, bytes: "ogg".to_slice, content_type: "audio/ogg",
      audio: DataDungeon::AudioMeta.new(duration_ms: 1200, bitrate: 128))
    _, ameta = db.get_with_meta("banter", atags).not_nil!
    ameta.should be_a DataDungeon::AudioMeta
    ameta.not_nil!.presentation.should be_nil
    ameta.as(DataDungeon::AudioMeta).duration_ms.should eq 1200

    # text asset → TextMeta
    ttags = {"quest" => "zork"}
    db.store("decree", ttags, bytes: "top hats".to_slice, content_type: "text/plain",
      text: DataDungeon::TextMeta.new(content: "top hats", language: "en"))
    _, tmeta = db.get_with_meta("decree", ttags).not_nil!
    tmeta.should be_a DataDungeon::TextMeta
    tmeta.as(DataDungeon::TextMeta).content.should eq "top hats"
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
    db.get_with_meta("venue", tags, touch: false)

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

  it "delete_asset removes the backing object, not just the row" do
    dir = File.tempname("dd-del")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    rec = db.store("venue", tags, bytes: "bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    path = db.path_for(rec)
    File.exists?(path).should be_true

    db.delete_asset(rec.id)
    db.find_asset_by_id(rec.id).should be_nil
    File.exists?(path).should be_false
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps the asset readable after a re-store with different bytes (same tags)" do
    dir = File.tempname("dd-restore")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    db.store("venue", tags, bytes: "old-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    rec = db.store("venue", tags, bytes: "new-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))

    # Same-key rewrite: the new object must survive the old row's replacement.
    got = db.get("venue", tags)
    got.should_not be_nil
    File.exists?(db.path_for(rec)).should be_true
    File.read(db.path_for(got.not_nil!)).should eq "new-bytes"
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "leaves no stray object when a re-store changes the extension" do
    dir = File.tempname("dd-extchange")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    old = db.store("venue", tags, bytes: "png-bytes".to_slice,
      content_type: "image/png", image: DataDungeon::ImageMeta.new(compression: "original"))
    old_path = db.path_for(old)
    old_path.ends_with?(".png").should be_true

    new = db.store("venue", tags, bytes: "webp-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    new_path = db.path_for(new)
    new_path.ends_with?(".webp").should be_true

    new_path.should_not eq old_path
    File.exists?(new_path).should be_true
    File.exists?(old_path).should be_false # old-extension object swept
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "does not raise when deleting an asset whose object is already gone" do
    dir = File.tempname("dd-del-gone")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    rec = db.store("venue", tags, bytes: "bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    File.delete(db.path_for(rec)) # object vanishes out from under DD

    db.delete_asset(rec.id) # must be a clean no-op on the missing object
    db.find_asset_by_id(rec.id).should be_nil
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "rejects a sidecar struct that disagrees with the media kind" do
    dir = File.tempname("dd-mismatch")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    expect_raises(ArgumentError, /media is "image".*audio/) do
      db.store("venue", tags,
        bytes: "bytes".to_slice, content_type: "image/webp",
        media: "image", audio: DataDungeon::AudioMeta.new)
    end
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end
end
