require "spec"
require "file_utils"
require "../src/data_dungeon"

# Browsing and curating a store: listing its types and tags, paging through
# assets, editing them in place, and opening it read-only.
private def with_db(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  yield db, dir
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

private def open_read_only(dir : String) : DataDungeon::DB
  DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"), read_only: true)
end

private def store_backdrop(db, style : String, rating : String, bytes : String) : DataDungeon::AssetRecord
  db.store("backdrop", {"art-style" => style, "rating" => rating}, bytes: bytes.to_slice, content_type: "image/webp")
end

describe "DataDungeon::DB browsing" do
  it "lists types with their counts, registered ones even when empty" do
    with_db("dd-browse-types") do |db|
      db.register_type("backdrop", pool_traits: %w[art-style rating], pool: true)
      db.register_type("voice", pool_traits: %w[line])
      store_backdrop(db, "golden", "pg", "a")
      store_backdrop(db, "silver", "pg", "b")
      db.store("legacy", bytes: "l".to_slice, content_type: "image/webp")

      db.asset_types.should eq({"backdrop" => 2, "legacy" => 1, "voice" => 0})
    end
  end

  it "lists a type's tag names and each one's values, most frequent first" do
    with_db("dd-browse-tags") do |db|
      db.register_type("backdrop", pool_traits: %w[art-style rating], pool: true)
      store_backdrop(db, "golden", "pg", "a")
      store_backdrop(db, "golden", "x", "b")
      store_backdrop(db, "silver", "pg", "c")

      db.tag_keys("backdrop").should eq({"art-style" => 3, "rating" => 3})
      db.tag_values("backdrop", "art-style").should eq({"golden" => 2, "silver" => 1})
      db.tag_values("backdrop", "art-style", limit: 1).should eq({"golden" => 2})
      db.tag_keys("missing").should be_empty
    end
  end

  it "pages through a type's assets, newest first, filtered by tags or not" do
    with_db("dd-browse-page") do |db|
      db.register_type("backdrop", pool_traits: %w[art-style rating], pool: true)
      a = store_backdrop(db, "golden", "pg", "a")
      b = store_backdrop(db, "silver", "pg", "b")
      c = store_backdrop(db, "golden", "pg", "c")

      db.list_assets("backdrop").map(&.id).should eq [c.id, b.id, a.id]
      db.list_assets("backdrop", limit: 2).map(&.id).should eq [c.id, b.id]
      db.list_assets("backdrop", limit: 2, offset: 2).map(&.id).should eq [a.id]
      db.list_assets("backdrop", {"art-style" => "Golden"}).map(&.id).should eq [c.id, a.id]
      db.count_pool_assets("backdrop", {"art-style" => "golden"}).should eq 2
      db.list_assets("backdrop", {"art-style" => "bronze"}).should be_empty
    end
  end

  it "edits an asset in place, re-deriving its key and keeping unchanged custom flags" do
    with_db("dd-browse-update") do |db|
      db.register_type("portrait", pool_traits: %w[art-style race])
      rec = db.store("portrait", {"art-style" => "golden", "race" => "ape", "note" => "x"}, custom: %w[race],
        bytes: "p".to_slice, content_type: "image/webp", description: "an ape")

      updated = db.update_asset(rec.id, description: "a golden ape", flagged: true, rating: 3)
      updated.description.should eq "a golden ape"
      updated.flagged.should be_true
      updated.rating.should eq 3
      updated.pool_key.should eq rec.pool_key # tags untouched

      moved = db.update_asset(rec.id, tags: {"art-style" => "Silver", "race" => "ape"})
      moved.pool_key.should eq "portrait.silver.ape"
      db.load_tags(rec.id).should eq({"art-style" => "silver", "race" => "ape"})
      db.custom_traits(rec.id).should eq ["race"]
      db.get("portrait", {"art-style" => "silver", "race" => "ape"}, touch: false).not_nil!.id.should eq rec.id
      String.new(db.read(moved)).should eq "p" # same object

      other = db.store("portrait", {"art-style" => "golden", "race" => "elf"}, bytes: "e".to_slice,
        content_type: "image/webp")
      expect_raises(ArgumentError, /already has the key portrait.silver.ape/) do
        db.update_asset(other.id, tags: {"art-style" => "silver", "race" => "ape"})
      end
      db.load_tags(other.id).should eq({"art-style" => "golden", "race" => "elf"}) # nothing changed
      expect_raises(ArgumentError, /No asset/) { db.update_asset(999_i64, flagged: true) }
    end
  end

  it "serializes records, metadata and registrations as JSON" do
    with_db("dd-browse-json") do |db|
      db.register_type("backdrop", pool_traits: %w[art-style rating], pool: true)
      rec = db.store("backdrop", {"art-style" => "golden", "rating" => "pg"}, bytes: "b".to_slice,
        content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original", width: 64))
      json = JSON.parse(rec.to_json)
      json["asset_type"].should eq "backdrop"
      json["pool_key"].should eq "backdrop.golden.pg"
      JSON.parse(db.get_with_meta_by_id(rec.id, touch: false).not_nil![1].not_nil!.to_json)["width"].should eq 64
      JSON.parse(db.registration("backdrop").to_json)["pool_traits"].should eq ["art-style", "rating"]
    end
  end
end

describe "DataDungeon::DB read-only" do
  it "reads, but refuses every write" do
    with_db("dd-read-only") do |db, dir|
      db.register_type("backdrop", pool_traits: %w[art-style rating], pool: true)
      rec = store_backdrop(db, "golden", "pg", "a")

      ro = open_read_only(dir)
      begin
        ro.read_only?.should be_true
        ro.asset_types.should eq({"backdrop" => 1})
        ro.get_by_id(rec.id).not_nil!.id.should eq rec.id # touching is skipped, not refused
        ro.find_asset_by_id(rec.id).not_nil!.use_count.should eq 0
        String.new(ro.read(rec)).should eq "a"
        ro.list_assets("backdrop").size.should eq 1
        ro.check_consistency.clean?.should be_true

        expect_raises(DataDungeon::ReadOnlyError) { store_backdrop(ro, "silver", "pg", "b") }
        expect_raises(DataDungeon::ReadOnlyError) { ro.update_asset(rec.id, flagged: true) }
        expect_raises(DataDungeon::ReadOnlyError) { ro.delete_asset(rec.id) }
        expect_raises(DataDungeon::ReadOnlyError) { ro.register_type("voice", pool_traits: %w[line]) }
        expect_raises(DataDungeon::ReadOnlyError) { ro.vacuum(delete_orphan_objects: true) }
        ro.connection.scalar("PRAGMA query_only").should eq 1 # SQLite refuses writes too
      ensure
        ro.close
      end
      db.find_asset_by_id(rec.id).not_nil!.flagged.should be_false
    end
  end

  it "refuses a missing database, or one that needs upgrading" do
    dir = File.tempname("dd-read-only-old")
    Dir.mkdir_p(dir)
    expect_raises(DataDungeon::ReadOnlyError, /No database/) { open_read_only(dir) }
    File.exists?(File.join(dir, "assets.db")).should be_false

    raw = ::DB.open("sqlite3://#{File.join(dir, "assets.db")}")
    raw.exec("CREATE TABLE assets (id INTEGER PRIMARY KEY, asset_type TEXT, canonical_key TEXT)")
    raw.close
    expect_raises(DataDungeon::ReadOnlyError, /needs upgrading/) { open_read_only(dir) }
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
