require "spec"
require "file_utils"
require "../src/data_dungeon"

# Exercises the high-level store/get path (v0.3 "owns the write path").
# Uses `original` compression + webp passthrough so the tests don't depend on
# libpng/libwebp encoding — the WebP conversion path is covered separately.
# Storing needs a registered type; these are the types the specs store.
private def open_db(dir : String) : DataDungeon::DB
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("venue", pool_traits: %w[venue style])
  db.register_type("banter", pool_traits: %w[line quest])
  db.register_type("decree", pool_traits: %w[quest])
  db.register_type("tile", pool_traits: %w[room])
  db.register_type("portrait", pool_traits: %w[race hair_color])
  db.register_type("panel", pool_traits: %w[hair_color])
  db.register_type("narration", pool_traits: %w[voice])
  db.register_type("file", pool_traits: %w[name])
  db.register_type("clip", pool_traits: %w[name])
  db
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

    hash = Digest::SHA256.hexdigest("webp-bytes")
    rec.asset_type.should eq "venue"
    rec.file_hash.should eq hash
    rec.file_path.should eq "#{hash[0, 2]}/#{hash}.webp" # content addressed
    File.read(db.path_for(rec)).should eq "webp-bytes"
    String.new(db.read(rec)).should eq "webp-bytes"

    got = db.get("venue", tags)
    got.should_not be_nil
    got.not_nil!.id.should eq rec.id
    db.find_asset_by_id(rec.id).not_nil!.use_count.should eq 0 # counted in memory
    db.flush_usage.should be_true
    db.find_asset_by_id(rec.id).not_nil!.use_count.should eq 1 # get touched it
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "counts uses in memory and writes them every hundred, and the rest at close" do
    dir = File.tempname("dd-store")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade", "style" => "silver"}
    a = db.store("venue", tags, bytes: "a".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("venue", {"venue" => "pier", "style" => "silver"}, bytes: "b".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))

    59.times { db.get("venue", tags) }
    40.times { db.touch_asset(b.id) }
    db.find_asset_by_id(a.id).not_nil!.use_count.should eq 0
    db.get("venue", tags) # the hundredth use
    db.find_asset_by_id(a.id).not_nil!.use_count.should eq 60
    db.find_asset_by_id(b.id).not_nil!.use_count.should eq 40

    3.times { db.touch_asset(b.id) }
    db.close
    db = open_db(dir)
    db.find_asset_by_id(b.id).not_nil!.use_count.should eq 43

    db.touch_asset(b.id)
    DataDungeon::DB.flush_open_usage # what runs at exit
    db.find_asset_by_id(b.id).not_nil!.use_count.should eq 44
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "doesn't wait for another connection's write lock to count a use" do
    dir = File.tempname("dd-store")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade", "style" => "silver"}
    a = db.store("venue", tags, bytes: "a".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    other = ::DB.open("sqlite3://#{db.path}")
    other.using_connection do |conn|
      conn.exec("BEGIN IMMEDIATE") # another process writing
      elapsed = Time.measure { 1100.times { db.get("venue", tags) } }
      elapsed.should be < 1.second # busy_timeout is 5 s; nobody waited it out
      db.flush_usage(wait: false).should be_false
      conn.exec("COMMIT")
    end

    db.find_asset_by_id(a.id).not_nil!.use_count.should eq 0
    db.flush_usage(wait: false).should be_true
    db.find_asset_by_id(a.id).not_nil!.use_count.should eq 1100
  ensure
    other.try(&.close)
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "returns the asset already holding the bytes when a store is an exact repeat" do
    dir = File.tempname("dd-dedup")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}
    payload = "same-bytes".to_slice

    a = db.store("venue", tags, bytes: payload, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("venue", tags, bytes: payload, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))

    b.id.should eq a.id # write-skip returned the existing record
    b.file_hash.should eq a.file_hash
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "adds every take under a key and gets the newest made" do
    dir = File.tempname("dd-takes")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    a = db.store("venue", tags, bytes: "v1".to_slice, content_type: "image/webp")
    b = db.store("venue", tags, bytes: "v2".to_slice, content_type: "image/webp")
    c = db.store("venue", tags, bytes: "v3".to_slice, content_type: "image/webp",
      made_at: Time.utc(2020, 1, 1)) # filed last, made first

    b.id.should_not eq a.id
    db.find_pool("venue", tags).map(&.id).should eq [a.id, b.id, c.id]
    db.get("venue", tags, touch: false).not_nil!.id.should eq b.id
    db.get_with_meta("venue", tags, touch: false).not_nil![0].id.should eq b.id
    c.made_at.should eq "2020-01-01 00:00:00"
    c.created_at.should_not eq c.made_at
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "gets the highest rated take, then the newest, and leaves flagged ones out" do
    dir = File.tempname("dd-rank")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}
    older = db.store("venue", tags, bytes: "older".to_slice, content_type: "image/webp", made_at: Time.utc(2026, 1, 1))
    newer = db.store("venue", tags, bytes: "newer".to_slice, content_type: "image/webp", made_at: Time.utc(2026, 6, 1))
    db.get("venue", tags, touch: false).not_nil!.id.should eq newer.id # neither rated: the newest

    db.update_asset(older.id, rating: 3) # loved
    db.get("venue", tags, touch: false).not_nil!.id.should eq older.id
    db.get_with_meta("venue", tags, touch: false).not_nil![0].id.should eq older.id

    db.update_asset(older.id, rating: -1) # hated: below one nobody rated
    db.get("venue", tags, touch: false).not_nil!.id.should eq newer.id

    db.update_asset(newer.id, flagged: true) # reported: out of play
    db.get("venue", tags, touch: false).not_nil!.id.should eq older.id
    db.update_asset(older.id, flagged: true)
    db.get("venue", tags, touch: false).should be_nil
    db.asset_exists?(db.key_for("venue", tags)).should be_true             # still there,
    db.find_pool("venue", tags).map(&.id).should eq [older.id, newer.id]    # and listed,
    db.list_assets("venue").map(&.id).should eq [newer.id, older.id]        # for review
    db.get_by_id(newer.id, touch: false).not_nil!.flagged.should be_true
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
    db.find_asset(db.key_for("venue", tags)).should_not be_nil # row still there; get self-heals
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
    meta.not_nil!.presentation.should eq pins # base accessor, no narrowing
    meta.should be_a DataDungeon::ImageMeta
    meta.as(DataDungeon::ImageMeta).usage_class.should eq "bg" # narrow for specifics

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

    a = db.store("banter", tags, bytes: "candidate-A".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    b = db.store("banter", tags, bytes: "candidate-B".to_slice,
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

  it "keeps the newest take readable after another with different bytes" do
    dir = File.tempname("dd-restore")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    db.store("venue", tags, bytes: "old-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))
    rec = db.store("venue", tags, bytes: "new-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"))

    # Updating the exact lookup key must leave the new object readable.
    got = db.get("venue", tags)
    got.should_not be_nil
    File.exists?(db.path_for(rec)).should be_true
    File.read(db.path_for(got.not_nil!)).should eq "new-bytes"
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "supersedes a take by id, keeping it retired until pruned" do
    dir = File.tempname("dd-supersede")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    tags = {"venue" => "arcade"}

    old = db.store("venue", tags, bytes: "png-bytes".to_slice,
      content_type: "image/png", image: DataDungeon::ImageMeta.new(compression: "original"))
    new = db.store("venue", tags, bytes: "webp-bytes".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original"),
      supersedes: old.id)

    retired = db.find_asset_by_id(old.id).not_nil!
    retired.retired?.should be_true
    new.retired?.should be_false
    db.find_pool("venue", tags).map(&.id).should eq [new.id]
    db.get("venue", tags, touch: false).not_nil!.id.should eq new.id
    db.links_from(new.id, "supersedes").map(&.to_id).should eq [old.id] # its history
    File.exists?(db.path_for(old)).should be_true                       # kept

    db.prune("venue").should eq 1
    db.find_asset_by_id(old.id).should be_nil
    File.exists?(db.path_for(old)).should be_false
    File.exists?(db.path_for(new)).should be_true
    db.check_consistency.clean?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "shares one object between assets with identical bytes" do
    dir = File.tempname("dd-shared")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    a = db.store("venue", {"venue" => "arcade"}, bytes: "same".to_slice, content_type: "image/webp")
    b = db.store("tile", {"room" => "attic"}, bytes: "same".to_slice, content_type: "image/webp")

    a.id.should_not eq b.id
    b.file_path.should eq a.file_path
    db.storage.not_nil!.list_keys.should eq [a.file_path] # stored once

    db.delete_asset(a.id)
    File.read(db.path_for(b)).should eq "same" # still referenced by b
    db.get("tile", {"room" => "attic"}, touch: false).not_nil!.id.should eq b.id

    db.delete_asset(b.id)
    File.exists?(db.path_for(b)).should be_false # last reference gone
    db.check_consistency.clean?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps a pruned take's object that another asset still uses" do
    dir = File.tempname("dd-shared-restore")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    shared = db.store("venue", {"venue" => "arcade"}, bytes: "v1".to_slice, content_type: "image/webp")
    other = db.store("tile", {"room" => "arcade"}, bytes: "v1".to_slice, content_type: "image/webp")
    db.store("venue", {"venue" => "arcade"}, bytes: "v2".to_slice, content_type: "image/webp", supersedes: shared.id)
    db.prune("venue").should eq 1

    File.read(db.path_for(other)).should eq "v1"
    db.get("tile", {"room" => "arcade"}, touch: false).not_nil!.file_path.should eq shared.file_path
    File.read(db.path_for(db.get("venue", {"venue" => "arcade"}, touch: false).not_nil!)).should eq "v2"
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

    rec = db.store("venue", tags, bytes: "bytes".to_slice,
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

    rec = db.store("venue", tags, bytes: "a".to_slice,
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
      db.store("venue", tags,
        bytes: "bytes".to_slice, content_type: "image/webp",
        media: "image", audio: DataDungeon::AudioMeta.new)
    end
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps assets with the same traits as independent takes, each addressed by id" do
    dir = File.tempname("dd-unkeyed")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    a = db.store("venue", {"style" => "silver"}, bytes: "one".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new)
    b = db.store("venue", {"style" => "silver"}, bytes: "two".to_slice,
      content_type: "image/webp", image: DataDungeon::ImageMeta.new)

    a.key.should eq "venue..silver" # no venue: an empty segment
    b.key.should eq a.key
    a.id.should_not eq b.id # independent records
    db.get_by_id(a.id, touch: false).not_nil!.id.should eq a.id
    db.get_by_id(b.id, touch: false).not_nil!.id.should eq b.id
    record, meta = db.get_with_meta_by_id(a.id, touch: false).not_nil!
    record.id.should eq a.id
    meta.should be_a DataDungeon::ImageMeta
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "refuses to store an unregistered type, leaving no object behind" do
    dir = File.tempname("dd-unregistered")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    expect_raises(ArgumentError, /character is not a registered asset type/) do
      db.store("character", {"race" => "human"}, bytes: "a".to_slice, content_type: "image/webp")
    end
    expect_raises(ArgumentError, /character is not a registered asset type/) do
      db.store_asset("character", "image", "image/webp", "/tmp/elsewhere.webp", {"race" => "human"})
    end
    db.storage.not_nil!.list_keys.should be_empty
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "refuses bytes its type already holds unless the store is an exact repeat" do
    dir = File.tempname("dd-provenance")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    first = db.store("portrait", {"hair_color" => "red"},
      bytes: "same".to_slice, content_type: "image/webp",
      description: "A red-haired adventurer", generated: true,
      generator: "arcana", generation: %({"width":512}),
      image: DataDungeon::ImageMeta.new(usage_class: "prop"))
    first.generated.should be_true
    first.description.should eq "A red-haired adventurer"

    again = db.store("portrait", {"hair_color" => "red"},
      bytes: "same".to_slice, content_type: "image/webp")
    again.id.should eq first.id # a retry: the asset as it is
    again.description.should eq "A red-haired adventurer"

    error = expect_raises(DataDungeon::AlreadyStored, /asset #{first.id}: change its traits with update_asset/) do
      db.store("portrait", {"hair_color" => "brown"},
        bytes: "same".to_slice, content_type: "image/webp")
    end
    error.asset_id.should eq first.id
    error.retired?.should be_false
    db.store("panel", {"hair_color" => "brown"}, bytes: "same".to_slice,
      content_type: "image/webp").id.should_not eq first.id # another type may hold them

    db.retire(first.id).should be_true
    error = expect_raises(DataDungeon::AlreadyStored, /\(retired\).*reinstate/) do
      db.store("portrait", {"hair_color" => "red"},
        bytes: "same".to_slice, content_type: "image/webp")
    end
    error.retired?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "refuses a store older than 0.12, leaving it as it was" do
    dir = File.tempname("dd-keys-older")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = open_db(dir)
    db.store("venue", {"venue" => "arcade", "style" => "silver"}, bytes: "a".to_slice, content_type: "image/webp")
    db.close
    # As 0.11 left it: the key a column of assets.
    raw = ::DB.open("sqlite3://#{path}")
    raw.exec("ALTER TABLE assets ADD COLUMN pool_key TEXT")
    raw.exec("UPDATE assets SET pool_key = 'venue.arcade.silver'")
    raw.close

    expect_raises(Exception, /older than 0.12.*DataDungeon 0.14/) { open_db(dir) }
    expect_raises(Exception, /older than 0.12/) do
      DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), read_only: true)
    end
    raw = ::DB.open("sqlite3://#{path}")
    raw.scalar("SELECT pool_key FROM assets").should eq "venue.arcade.silver" # untouched
  ensure
    raw.try(&.close)
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "names objects by content type, ignoring its parameters" do
    dir = File.tempname("dd-ext")
    Dir.mkdir_p(dir)
    db = open_db(dir)

    {"audio/opus" => "opus", "image/svg+xml" => "svg", "text/plain; charset=utf-8" => "txt",
     "audio/ogg; codecs=opus" => "ogg", "application/pdf" => "pdf"}.each do |content_type, ext|
      rec = db.store("file", bytes: content_type.to_slice, content_type: content_type)
      File.extname(rec.file_path).should eq ".#{ext}"
    end
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "adopts a row recorded by its own path into the store" do
    dir = File.tempname("dd-adopt")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    own = File.join(dir, "app-files", "voice.opus")
    Dir.mkdir_p(File.dirname(own))
    File.write(own, "opus-bytes")
    id = db.store_asset("narration", "audio", "audio/opus", own, {"speed" => "1.0"},
      description: "a line", generated: true)
    db.outside_store.map(&.id).should eq [id]

    rec = db.adopt(db.find_asset_by_id(id).not_nil!)

    hash = Digest::SHA256.hexdigest("opus-bytes")
    rec.id.should eq id
    rec.file_path.should eq "#{hash[0, 2]}/#{hash}.opus"
    rec.file_hash.should eq hash
    rec.description.should eq "a line"
    db.load_tags(id).should eq({"speed" => "1.0"})
    String.new(db.read(rec)).should eq "opus-bytes"
    File.read(own).should eq "opus-bytes" # the original stays
    db.outside_store.should be_empty
    db.adopt(rec).should eq rec # already in the store
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "shares an object already in the store when adopting identical bytes" do
    dir = File.tempname("dd-adopt-shared")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    stored = db.store("venue", bytes: "same".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    own = File.join(dir, "same.webp")
    File.write(own, "same")
    id = db.store_asset("venue", "image", "image/webp", own)

    db.adopt(db.find_asset_by_id(id).not_nil!).file_path.should eq stored.file_path
    db.check_consistency.clean?.should be_true
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "leaves a row whose file is gone as it is" do
    dir = File.tempname("dd-adopt-missing")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    gone = File.join(dir, "gone.webp")
    id = db.store_asset("venue", "image", "image/webp", gone)

    expect_raises(File::NotFoundError) { db.adopt(db.find_asset_by_id(id).not_nil!) }
    db.find_asset_by_id(id).not_nil!.file_path.should eq gone
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "finds the assets holding the same bytes by their hash" do
    dir = File.tempname("dd-by-hash")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    one = db.store("venue", {"venue" => "diner"}, bytes: "same".to_slice, content_type: "image/webp")
    two = db.store("tile", {"room" => "arcade"}, bytes: "same".to_slice, content_type: "image/webp")
    db.retire(two.id)
    db.store("venue", {"venue" => "mall"}, bytes: "other".to_slice, content_type: "image/webp")

    db.find_by_hash(Digest::SHA256.hexdigest("same")).map(&.id).should eq [one.id, two.id]
    db.find_by_hash(Digest::SHA256.hexdigest("missing")).should be_empty
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "streams an object through open" do
    dir = File.tempname("dd-open")
    Dir.mkdir_p(dir)
    db = open_db(dir)
    rec = db.store("clip", bytes: "streamed bytes".to_slice, content_type: "audio/mpeg")

    db.open(rec) { |io| io.gets_to_end.should eq "streamed bytes" }
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end
end
