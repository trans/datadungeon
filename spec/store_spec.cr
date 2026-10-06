require "spec"
require "file_utils"
require "../src/data_dungeon"

# Exercises the high-level store/get path (v0.3 "owns the write path").
# Uses `original` compression + webp passthrough so the tests don't depend on
# libpng/libwebp encoding — the WebP conversion path is covered separately.
private def open_db(dir : String) : DataDungeon::DB
  DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
end

# Applications decide which attributes define exact identity. DataDungeon
# receives the resulting opaque key; it does not hash tags itself.
private def key_for(tags : Hash(String, String)) : String
  payload = tags.to_a.sort_by(&.[0]).map { |key, value| "#{key}=#{value}" }.join("\n")
  Digest::SHA256.hexdigest(payload)
end

describe DataDungeon::DB do
  it "stores an asset, owns the file, and finds it via get" do
    dir = File.tempname("dd-store")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade", "style" => "silver"}

    rec = db.store("venue", tags, pool_key: key_for(tags),
      bytes: "webp-bytes".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    hash = Digest::SHA256.hexdigest("webp-bytes")
    rec.asset_type.should eq "venue"
    rec.file_hash.should eq hash
    rec.file_path.should eq "#{hash[0, 2]}/#{hash}.webp" # content addressed
    File.read(db.path_for(rec)).should eq "webp-bytes"

    got = db.get("venue", key_for(tags))
    got.should_not be_nil
    got.not_nil!.id.should eq rec.id
    db.find_asset_by_id(rec.id).not_nil!.use_count.should eq 1 # get touched it
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

    a = db.store("venue", tags, pool_key: key_for(tags), bytes: payload, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("venue", tags, pool_key: key_for(tags), bytes: payload, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    b.id.should eq a.id # write-skip returned the existing record
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

    a = db.store("venue", tags, pool_key: key_for(tags), bytes: "v1".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("venue", tags, pool_key: key_for(tags), bytes: "v2".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    b.id.should eq a.id
    b.file_hash.should_not eq a.file_hash
    db.find_asset_by_id(a.id).not_nil!.file_hash.should eq b.file_hash
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "self-heals to a miss when the backing file is gone" do
    dir = File.tempname("dd-heal")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    rec = db.store("venue", tags, pool_key: key_for(tags), bytes: "bytes".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    File.delete(db.path_for(rec))

    db.get("venue", key_for(tags)).should be_nil
    db.find_asset("venue", key_for(tags)).should_not be_nil # row still there; get self-heals
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

    stored = db.store("venue", tags, pool_key: key_for(tags), bytes: "webp".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original", usage_class: "bg", presentation: pins))

    pair = db.get_with_meta("venue", key_for(tags))
    pair.should_not be_nil
    rec, meta = pair.not_nil!
    rec.id.should eq stored.id
    meta.should_not be_nil
    meta.not_nil!.presentation.should eq pins # base accessor, no narrowing
    meta.should be_a DataDungeon::ImageMeta
    meta.as(DataDungeon::ImageMeta).usage_class.should eq "bg" # narrow for specifics

    db.get_with_meta("venue", "missing").should be_nil
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
    db.store("banter", atags, pool_key: key_for(atags), bytes: "ogg".to_slice, content_type: "audio/ogg",
      audio: DataDungeon::AudioMeta.new(duration_ms: 1200, bitrate: 128))
    _, ameta = db.get_with_meta("banter", key_for(atags)).not_nil!
    ameta.should be_a DataDungeon::AudioMeta
    ameta.not_nil!.presentation.should be_nil
    ameta.as(DataDungeon::AudioMeta).duration_ms.should eq 1200

    # text asset → TextMeta
    ttags = {"quest" => "zork"}
    db.store("decree", ttags, pool_key: key_for(ttags), bytes: "top hats".to_slice, content_type: "text/plain",
      text: DataDungeon::TextMeta.new(content: "top hats", language: "en"))
    _, tmeta = db.get_with_meta("decree", key_for(ttags)).not_nil!
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

    rec = db.store("venue", tags, pool_key: key_for(tags), bytes: "webp".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    db.get("venue", key_for(tags), touch: false)
    db.get_with_meta("venue", key_for(tags), touch: false)

    db.find_asset_by_id(rec.id).not_nil!.use_count.should eq 0 # no write on read
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps distinct pool members independently addressable" do
    dir = File.tempname("dd-pool")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"quest" => "zork"}

    a = db.store("banter", tags, pool_key: key_for(tags), pool: true, bytes: "candidate-A".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("banter", tags, pool_key: key_for(tags), pool: true, bytes: "candidate-B".to_slice,
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

    rec = db.store("venue", tags, pool_key: key_for(tags), bytes: "bytes".to_slice,
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

    db.store("venue", tags, pool_key: key_for(tags), bytes: "old-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    rec = db.store("venue", tags, pool_key: key_for(tags), bytes: "new-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))

    # Updating the exact lookup key must leave the new object readable.
    got = db.get("venue", key_for(tags))
    got.should_not be_nil
    File.exists?(db.path_for(rec)).should be_true
    File.read(db.path_for(got.not_nil!)).should eq "new-bytes"
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "leaves no stray object when a re-store changes the bytes" do
    dir = File.tempname("dd-supersede")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    old = db.store("venue", tags, pool_key: key_for(tags), bytes: "png-bytes".to_slice,
      content_type: "image/png", image: DataDungeon::ImageMeta.new(compression: "original"))
    old_path = db.path_for(old)
    old_path.ends_with?(".png").should be_true

    new = db.store("venue", tags, pool_key: key_for(tags), bytes: "webp-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    new_path = db.path_for(new)
    new_path.ends_with?(".webp").should be_true

    new.content_type.should eq "image/webp"
    new_path.should_not eq old_path
    File.exists?(new_path).should be_true
    File.exists?(old_path).should be_false # superseded object swept
    db.check_consistency.clean?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "shares one object between assets with identical bytes" do
    dir = File.tempname("dd-shared")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    a = db.store("venue", {"venue" => "arcade"}, pool_key: "arcade",
      bytes: "same".to_slice, content_type: "image/webp")
    b = db.store("tile", {"room" => "attic"}, pool_key: "attic",
      bytes: "same".to_slice, content_type: "image/webp")

    a.id.should_not eq b.id
    b.file_path.should eq a.file_path
    db.storage.not_nil!.list_keys.should eq [a.file_path] # stored once

    db.delete_asset(a.id)
    File.read(db.path_for(b)).should eq "same" # still referenced by b
    db.get("tile", "attic", touch: false).not_nil!.id.should eq b.id

    db.delete_asset(b.id)
    File.exists?(db.path_for(b)).should be_false # last reference gone
    db.check_consistency.clean?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps a superseded object that another asset still uses" do
    dir = File.tempname("dd-shared-restore")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    shared = db.store("venue", {"venue" => "arcade"}, pool_key: "arcade",
      bytes: "v1".to_slice, content_type: "image/webp")
    other = db.store("venue", {"venue" => "diner"}, pool_key: "diner",
      bytes: "v1".to_slice, content_type: "image/webp")
    db.store("venue", {"venue" => "arcade"}, pool_key: "arcade",
      bytes: "v2".to_slice, content_type: "image/webp")

    File.read(db.path_for(other)).should eq "v1"
    db.get("venue", "diner", touch: false).not_nil!.file_path.should eq shared.file_path
    File.read(db.path_for(db.get("venue", "arcade", touch: false).not_nil!)).should eq "v2"
    db.check_consistency.clean?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "does not vacuum an object a row references" do
    dir = File.tempname("dd-fsck-shared")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    rec = db.store("venue", {"venue" => "arcade"}, bytes: "a".to_slice, content_type: "image/webp")
    db.store("tile", {"room" => "attic"}, bytes: "a".to_slice, content_type: "image/webp")

    db.vacuum(delete_orphan_objects: true).orphan_objects.should be_empty
    File.read(db.path_for(rec)).should eq "a"
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "does not raise when deleting an asset whose object is already gone" do
    dir = File.tempname("dd-del-gone")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    rec = db.store("venue", tags, pool_key: key_for(tags), bytes: "bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    File.delete(db.path_for(rec)) # object vanishes out from under DD

    db.delete_asset(rec.id) # must be a clean no-op on the missing object
    db.find_asset_by_id(rec.id).should be_nil
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "reports a clean store as consistent" do
    dir = File.tempname("dd-fsck-clean")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    db.store("venue", {"venue" => "arcade"}, bytes: "a".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    db.store("venue", {"venue" => "diner"}, bytes: "b".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))

    report = db.check_consistency
    report.clean?.should be_true
    report.missing_objects.should be_empty
    report.orphan_objects.should be_empty
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "detects and vacuums a row whose object is gone" do
    dir = File.tempname("dd-fsck-missing")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    rec = db.store("venue", tags, pool_key: key_for(tags), bytes: "a".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    File.delete(db.path_for(rec)) # object vanishes, row remains

    report = db.check_consistency
    report.clean?.should be_false
    report.missing_objects.map(&.id).should eq [rec.id]

    # Report-only vacuum leaves the row in place.
    db.vacuum
    db.find_asset_by_id(rec.id).should_not be_nil

    # Opt-in delete drops the dangling row.
    swept = db.vacuum(delete_missing_rows: true)
    swept.missing_objects.map(&.id).should eq [rec.id]
    db.find_asset_by_id(rec.id).should be_nil
    db.check_consistency.clean?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "detects and vacuums an orphaned object with no row" do
    dir = File.tempname("dd-fsck-orphan")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    db.store("venue", {"venue" => "arcade"}, bytes: "a".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))

    # Simulate a leaked blob (e.g. a pre-v0.3.4 delete): drop a file into the
    # store with no owning row.
    orphan_key = File.join("venue", "ff", "orphan.webp")
    orphan_abs = File.join(dir, "store", orphan_key)
    Dir.mkdir_p(File.dirname(orphan_abs))
    File.write(orphan_abs, "leaked")

    report = db.check_consistency
    report.orphan_objects.should eq [orphan_key]
    report.missing_objects.should be_empty

    # Report-only vacuum leaves it on disk.
    db.vacuum
    File.exists?(orphan_abs).should be_true

    # Opt-in delete removes it.
    swept = db.vacuum(delete_orphan_objects: true)
    swept.orphan_objects.should eq [orphan_key]
    File.exists?(orphan_abs).should be_false
    db.check_consistency.clean?.should be_true
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
      db.store("venue", tags, pool_key: key_for(tags),
        bytes: "bytes".to_slice, content_type: "image/webp",
        media: "image", audio: DataDungeon::AudioMeta.new)
    end
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "stores independent assets without a pool key" do
    dir = File.tempname("dd-unkeyed")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    a = db.store("venue", {"style" => "silver"}, bytes: "same".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new)
    b = db.store("venue", {"style" => "silver"}, bytes: "same".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new)

    a.pool_key.should be_nil
    b.pool_key.should be_nil
    a.id.should_not eq b.id
    a.file_path.should eq b.file_path # independent records, one shared object
    db.get_by_id(a.id, touch: false).not_nil!.id.should eq a.id
    db.get_by_id(b.id, touch: false).not_nil!.id.should eq b.id
    record, meta = db.get_with_meta_by_id(a.id, touch: false).not_nil!
    record.id.should eq a.id
    meta.should be_a DataDungeon::ImageMeta
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "uses an unregistered type's explicit pool key independently of tags" do
    dir = File.tempname("dd-opaque-key")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"race" => "human"}

    first = db.store("portrait", tags, pool_key: "character-a",
      bytes: "a".to_slice, content_type: "image/webp")
    second = db.store("portrait", tags, pool_key: "character-b",
      bytes: "b".to_slice, content_type: "image/webp")

    first.id.should_not eq second.id
    db.get("portrait", "character-a", touch: false).not_nil!.id.should eq first.id
    db.get("portrait", "character-b", touch: false).not_nil!.id.should eq second.id
    db.load_tags(first.id).should eq tags
    db.load_tags(second.id).should eq tags
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "updates description, generation flag, tags and media metadata on re-store" do
    dir = File.tempname("dd-provenance")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    first = db.store("portrait", {"hair_color" => "red"}, pool_key: "portrait-1",
      bytes: "same".to_slice, content_type: "image/webp",
      description: "A red-haired adventurer", generated: true,
      generator: "arcana", generation: %({"width":512}),
      image: DataDungeon::ImageMeta.new(usage_class: "prop"))
    first.generated.should be_true
    first.description.should eq "A red-haired adventurer"
    first.file_path.includes?("portrait-1").should be_false
    second = db.store("portrait", {"hair_color" => "brown"}, pool_key: "portrait-1",
      bytes: "same".to_slice, content_type: "image/webp",
      description: "A brown-haired adventurer", generated: false,
      image: DataDungeon::ImageMeta.new(usage_class: "icon"))

    second.id.should eq first.id
    second.file_path.should eq first.file_path
    second.description.should eq "A brown-haired adventurer"
    second.generated.should be_false
    second.generator.should be_nil
    db.load_tags(second.id).should eq({"hair_color" => "brown"})
    db.load_image_meta(second.id).not_nil!.usage_class.should eq "icon"
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "opens an existing asset database with its tags intact" do
    dir = File.tempname("dd-schema-upgrade")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    raw = ::DB.open("sqlite3://#{path}")
    # The 0.3 layout: a required canonical_key, no description,
    # generated flag or custom tag flag.
    old_schema = DataDungeon::DB::ASSETS_SCHEMA
      .sub("pool_key      TEXT,", "canonical_key TEXT NOT NULL,")
      .lines.reject { |line| line.includes?("description") || line.includes?("generated") }.join
    raw.exec(old_schema)
    raw.exec(DataDungeon::DB::ASSET_TAGS_SCHEMA.lines.reject { |line| line.includes?("custom") || line.includes?("asset_type") }.join)
    raw.exec(DataDungeon::DB::IMAGE_META_SCHEMA)
    raw.exec(<<-SQL)
      INSERT INTO assets
      (id, asset_type, media, content_type, file_path, canonical_key,
       created_at, generator)
      VALUES (7, 'portrait', 'image', 'image/webp', 'portrait/old.webp',
              'old-key', '2026-01-01 00:00:00', 'arcana')
    SQL
    raw.exec("INSERT INTO asset_tags VALUES (7, 'race', 'human')")
    raw.exec("INSERT INTO image_meta (asset_id, width) VALUES (7, 512)")
    raw.close

    db = open_db(dir)
    rec = db.find_asset_by_id(7_i64).not_nil!
    rec.pool_key.should eq "old-key"
    rec.generated.should be_true
    rec.description.should be_nil
    db.load_tags(rec.id).should eq({"race" => "human"})
    db.custom_traits(rec.id).should be_empty
    db.connection.scalar("SELECT asset_type FROM asset_tags WHERE asset_id = 7").should eq "portrait" # backfilled
    db.load_image_meta(rec.id).not_nil!.width.should eq 512                                           # the rebuild cascaded nothing
    db.delete_asset(rec.id)
    db.load_tags(rec.id).should be_empty
  ensure
    raw.try(&.close)
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "drops a unique file_path constraint so old rows can share objects" do
    dir = File.tempname("dd-unique-path-upgrade")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    raw = ::DB.open("sqlite3://#{path}")
    raw.exec(DataDungeon::DB::ASSETS_SCHEMA.sub("file_path     TEXT NOT NULL,", "file_path     TEXT NOT NULL UNIQUE,"))
    raw.exec(DataDungeon::DB::ASSET_TAGS_SCHEMA)
    raw.exec(<<-SQL)
      INSERT INTO assets (id, asset_type, media, content_type, file_path, created_at)
      VALUES (3, 'venue', 'image', 'image/webp', 'venue/0123abcd.webp', '2026-10-01 00:00:00')
    SQL
    raw.exec("INSERT INTO asset_tags (asset_id, asset_type, tag_key, tag_value) VALUES (3, 'venue', 'venue', 'arcade')")
    raw.close

    db = open_db(dir)
    old = db.find_asset_by_id(3_i64).not_nil!
    old.file_path.should eq "venue/0123abcd.webp" # existing objects stay put
    db.load_tags(3_i64).should eq({"venue" => "arcade"})
    db.store_asset("venue", "image", "image/webp", old.file_path, {"venue" => "diner"})
    db.connection.scalar("SELECT COUNT(*) FROM assets WHERE file_path = ?", old.file_path).should eq 2
  ensure
    raw.try(&.close)
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end
end
