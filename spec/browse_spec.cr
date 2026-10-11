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

# Types registered with a trait the specs don't use, so their tags stay as
# given.
private def register_plain(db : DataDungeon::DB, *types : String) : Nil
  types.each { |type| db.register_type(type, pool_traits: %w[name]) }
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
      db.register_type("backdrop", pool_traits: %w[art-style rating])
      db.register_type("voice", pool_traits: %w[line])
      store_backdrop(db, "golden", "pg", "a")
      store_backdrop(db, "silver", "pg", "b")
      # An unregistered type's asset, as a store from before 0.12 could hold.
      db.connection.exec("INSERT INTO assets (asset_type, media, content_type, file_path, created_at, made_at) " \
                         "VALUES ('legacy', 'image', 'image/webp', 'l.webp', '2026-01-01', '2026-01-01')")

      db.asset_types.should eq({"backdrop" => 2, "legacy" => 1, "voice" => 0})
    end
  end

  it "lists a type's tag names and each one's values, most frequent first" do
    with_db("dd-browse-tags") do |db|
      db.register_type("backdrop", pool_traits: %w[art-style rating])
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
      db.register_type("backdrop", pool_traits: %w[art-style rating])
      a = store_backdrop(db, "golden", "pg", "a")
      b = store_backdrop(db, "silver", "pg", "b")
      c = store_backdrop(db, "golden", "pg", "c")

      db.list_assets("backdrop").map(&.id).should eq [c.id, b.id, a.id]
      db.list_assets("backdrop", limit: 2).map(&.id).should eq [c.id, b.id]
      db.list_assets("backdrop", limit: 2, before: b.id).map(&.id).should eq [a.id]
      db.list_assets("backdrop", limit: 2, offset: 2).map(&.id).should eq [a.id]
      db.list_assets("backdrop", {"art-style" => "Golden"}).map(&.id).should eq [c.id, a.id]
      db.count_assets("backdrop", {"art-style" => "golden"}).should eq 2
      db.list_assets("backdrop", {"art-style" => "bronze"}).should be_empty
    end
  end

  it "lists across types, and searches by words in any order" do
    with_db("dd-browse-search") do |db|
      db.register_type("front", pool_traits: %w[venue attraction look])
      db.register_type("sprite", pool_traits: %w[venue attraction look scale])
      db.register_type("portrait", pool_traits: %w[hair skin], labels: {"hair" => "hair", "skin" => "skin"})
      front = db.store("front", {"venue" => "boardwalk", "attraction" => "cattacula", "look" => "night"},
        bytes: "f".to_slice, content_type: "image/webp")
      sprite = db.store("sprite", {"venue" => "boardwalk", "attraction" => "cattacula", "look" => "night", "scale" => "32"},
        bytes: "s".to_slice, content_type: "image/webp")
      register_plain(db, "room")
      room = db.store("room", {"room" => "west-of-house", "note" => "Giant Ape"}, bytes: "r".to_slice,
        content_type: "image/webp")
      red_hair = db.store("portrait", {"hair" => "red", "skin" => "tan"}, bytes: "h".to_slice, content_type: "image/webp")
      red_skin = db.store("portrait", {"hair" => "black", "skin" => "red"}, bytes: "k".to_slice, content_type: "image/webp")

      db.list_assets.map(&.id).should eq [red_skin.id, red_hair.id, room.id, sprite.id, front.id]
      db.list_assets(limit: 2, before: room.id).map(&.id).should eq [sprite.id, front.id]
      db.list_assets(nil, {"venue" => "boardwalk"}).map(&.id).should eq [sprite.id, front.id]

      db.list_assets(q: "boardwalk cattacula front").map(&.id).should eq [front.id]
      db.list_assets(q: "catt* night").map(&.id).should eq [sprite.id, front.id]
      db.list_assets(q: "catt night").should be_empty # whole words unless asked
      db.list_assets(q: "boardwalk.cattacula.front.night").map(&.id).should eq [front.id]
      db.list_assets("sprite", q: "night").map(&.id).should eq [sprite.id]
      db.list_assets(q: "night", limit: 1).map(&.id).should eq [sprite.id]
      db.list_assets(q: "night", limit: 1, before: sprite.id).map(&.id).should eq [front.id]
      db.list_assets(q: "house").map(&.id).should eq [room.id] # a part of west-of-house
      db.list_assets(q: "west-of*").map(&.id).should eq [room.id]
      db.list_assets(q: "giant ape").map(&.id).should eq [room.id] # an unkeyed tag, as given
      db.list_assets(q: "red").map(&.id).should eq [red_skin.id, red_hair.id]
      db.list_assets(q: "red-hair").map(&.id).should eq [red_hair.id] # only as keys spell it
      db.list_assets(q: %("quoted" OR night)).should be_empty         # words, never query syntax
      db.count_assets(q: "night").should eq 2
      db.count_assets.should eq 5

      db.update_asset(front.id, tags: {"venue" => "boardwalk", "attraction" => "cattacula", "look" => "day"})
      db.list_assets(q: "night").map(&.id).should eq [sprite.id]
      db.rename_type("front", "facade")
      db.list_assets(q: "facade day").map(&.id).should eq [front.id]
      db.delete_asset(sprite.id)
      db.list_assets(q: "cattacula").map(&.id).should eq [front.id]
    end
  end

  it "walks the newest assets for common words, matching as the index does" do
    with_db("dd-browse-walk") do |db|
      register_plain(db, "prop")
      ids = (1..300).map do |i|
        tags = {"look" => i.even? ? "night" : "day", "thing" => "lamp_#{i % 3}", "venue" => i % 10 == 0 ? "west-of-house" : "midway"}
        db.store("prop", tags, bytes: "p#{i}".to_slice, content_type: "image/webp").id
      end
      newest = ids.reverse
      newest_where = ->(test : Int32 -> Bool) { (1..300).select { |i| test.call(i) }.map { |i| ids[i - 1] }.reverse }
      night = newest_where.call(->(i : Int32) { i.even? })

      # Common words with a short page: the walk is cheaper, and agrees with the index.
      db.list_assets(q: "night", limit: 3).map(&.id).should eq night.first(3)
      db.list_assets(q: "nig*", limit: 3, offset: 3).map(&.id).should eq night[3, 3]
      db.list_assets(q: "nig", limit: 3).should be_empty
      db.list_assets(q: "night", limit: 2, before: night[1]).map(&.id).should eq night[2, 2]
      db.list_assets("prop", {"look" => "night"}, q: "lamp_0", limit: 2).map(&.id)
        .should eq newest_where.call(->(i : Int32) { i.even? && i % 3 == 0 }).first(2)
      db.list_assets(q: "lamp_*", limit: 1).map(&.id).should eq [newest.first] # _ is a letter here, not a wildcard
      db.list_assets(q: "lamp%", limit: 1).map(&.id).should eq [newest.first]  # % separates words, as in the index
      db.list_assets(q: "lamp_1", limit: 1).map(&.id).should eq [ids[297]]     # 298 % 3 == 1
      db.list_assets(q: "house night", limit: 2).map(&.id).should eq newest_where.call(->(i : Int32) { i % 10 == 0 }).first(2)
      db.count_assets(q: "night").should eq 150
      rare = db.store("prop", {"look" => "night", "thing" => "lamp_rare", "venue" => "midway"},
        bytes: "rare".to_slice, content_type: "image/webp")
      db.list_assets(q: "night lamp_rare").map(&.id).should eq [rare.id] # the rare word drives
      db.count_assets(q: "night lamp_rare").should eq 1
      db.delete_asset(rare.id)

      terms = ->(term : String) { db.connection.query_one("SELECT docs FROM asset_search_terms WHERE term = ?", term, as: Int64) }
      terms.call("").should eq 300
      terms.call("night").should eq 150
      db.update_asset(night.first, tags: {"look" => "day", "thing" => "lamp_9", "venue" => "midway"})
      db.delete_asset(night[1])
      terms.call("").should eq 299
      terms.call("night").should eq 148
      db.connection.query_one?("SELECT docs FROM asset_search_terms WHERE term = 'lamp_9'", as: Int64).should eq 1
    end
  end

  it "links assets to assets and to names, filters by them, and drops them with the asset" do
    with_db("dd-browse-links") do |db|
      db.register_type("portrait", pool_traits: %w[hair])
      register_plain(db, "panel", "prop")
      portrait = db.store("portrait", {"hair" => "red"}, bytes: "p".to_slice, content_type: "image/webp")
      picture = db.store("panel", {"scene" => "beach"}, bytes: "q".to_slice, content_type: "image/webp")
      prop = db.store("prop", {"thing" => "gangway"}, bytes: "g".to_slice, content_type: "image/webp")

      db.link(picture.id, "derived-from", portrait.id)
      db.link(prop.id, "used-by", "boardwalk")
      db.link(prop.id, "used-by", "park-map")
      db.link(prop.id, "used-by", "boardwalk") # twice changes nothing

      db.links_from(prop.id).map(&.to_name).should eq ["boardwalk", "park-map"]
      db.links_to(portrait.id, "derived-from").map(&.from_id).should eq [picture.id]
      db.links_to("boardwalk").map(&.from_id).should eq [prop.id]
      db.list_assets(links: {"used-by" => "boardwalk"}).map(&.id).should eq [prop.id]
      db.list_assets("prop", links: {"used-by" => "park-map"}).map(&.id).should eq [prop.id]
      db.list_assets(unlinked: "used-by").map(&.id).should eq [picture.id, portrait.id]

      db.unlink(prop.id, "used-by", "park-map").should be_true
      db.unlink(prop.id, "used-by", "park-map").should be_false
      db.links_from(prop.id).map(&.to_name).should eq ["boardwalk"]
      expect_raises(ArgumentError, /lowercase words/) { db.link(prop.id, "Used By", "x") }
      expect_raises(ArgumentError, /No asset/) { db.link(prop.id, "derived-from", 999_i64) }

      db.delete_asset(portrait.id)
      db.links_from(picture.id).should be_empty # the link went with its target
    end
  end

  it "keeps data on a link, and filters names by a user and what's under it" do
    with_db("dd-browse-link-data") do |db|
      register_plain(db, "prop")
      lamp = db.store("prop", {"thing" => "lamp"}, bytes: "l".to_slice, content_type: "image/webp")
      sign = db.store("prop", {"thing" => "sign"}, bytes: "s".to_slice, content_type: "image/webp")
      bench = db.store("prop", {"thing" => "bench"}, bytes: "b".to_slice, content_type: "image/webp")
      db.link(lamp.id, "used-by", "boardwalk.holidayland", %({"at":[0.2,0.7],"layer":2}))
      db.link(sign.id, "used-by", "boardwalk")
      db.link(bench.id, "used-by", "boardwalk-annex")

      placed = db.links_from(lamp.id).first
      placed.data.not_nil!["layer"].as_i.should eq 2
      db.link(lamp.id, "used-by", "boardwalk.holidayland") # no data: kept
      db.links_from(lamp.id).first.data.not_nil!["at"].as_a.size.should eq 2
      db.link(lamp.id, "used-by", "boardwalk.holidayland", %({"layer":3}))
      db.links_from(lamp.id).first.data.should eq JSON.parse(%({"layer":3}))
      db.links_from(sign.id).first.data.should be_nil

      db.list_assets(links: {"used-by" => "boardwalk.holidayland"}).map(&.id).should eq [lamp.id]
      db.list_assets(links: {"used-by" => "boardwalk.*"}).map(&.id).should eq [sign.id, lamp.id]
      db.list_assets(links: {"used-by" => "boardwalk*"}).map(&.id).should eq [bench.id, sign.id, lamp.id]
      db.count_assets(links: {"used-by" => "board*"}).should eq 3
      db.links_to("boardwalk.*", "used-by").map(&.from_id).should eq [lamp.id, sign.id]
      db.links_to("boardwalk.*", "derived-from").should be_empty

      expect_raises(ArgumentError, /must be JSON/) { db.link(sign.id, "used-by", "x", "{nope") }
      expect_raises(ArgumentError, /can't hold '\*'/) { db.link(sign.id, "used-by", "x*") }
      expect_raises(ArgumentError, /needs a name before/) { db.links_to(".*") }
    end
  end

  it "makes a supersedes link by superseding" do
    with_db("dd-browse-link-supersede") do |db|
      register_plain(db, "prop")
      old = db.store("prop", {"thing" => "lamp"}, bytes: "1".to_slice, content_type: "image/webp")
      redo = db.store("prop", {"thing" => "lamp"}, bytes: "2".to_slice, content_type: "image/webp")
      db.link(redo.id, "supersedes", old.id)
      db.find_asset_by_id(old.id).not_nil!.retired?.should be_true
      expect_raises(ArgumentError, /not a name/) { db.link(redo.id, "supersedes", "lamp") }
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
      updated.key.should eq rec.key # tags untouched

      moved = db.update_asset(rec.id, tags: {"art-style" => "Silver", "race" => "ape"})
      moved.key.should eq "portrait.silver.ape"
      db.load_tags(rec.id).should eq({"art-style" => "silver", "race" => "ape"})
      db.custom_traits(rec.id).should eq ["race"]
      db.get("portrait", {"art-style" => "silver", "race" => "ape"}, touch: false).should be_nil # flagged: out of play
      db.update_asset(rec.id, flagged: false)
      db.get("portrait", {"art-style" => "silver", "race" => "ape"}, touch: false).not_nil!.id.should eq rec.id
      String.new(db.read(moved)).should eq "p" # same object

      other = db.store("portrait", {"art-style" => "golden", "race" => "elf"}, bytes: "e".to_slice,
        content_type: "image/webp")
      db.update_asset(other.id, tags: {"art-style" => "silver", "race" => "ape"}).key.should eq moved.key
      db.find_pool("portrait", {"art-style" => "silver", "race" => "ape"}).map(&.id).should eq [rec.id, other.id]
      expect_raises(ArgumentError, /No asset/) { db.update_asset(999_i64, flagged: true) }
    end
  end

  it "serializes records, metadata and registrations as JSON" do
    with_db("dd-browse-json") do |db|
      db.register_type("backdrop", pool_traits: %w[art-style rating])
      rec = db.store("backdrop", {"art-style" => "golden", "rating" => "pg"}, bytes: "b".to_slice,
        content_type: "image/webp", image: DataDungeon::ImageMeta.new(compression: "original", width: 64))
      json = JSON.parse(rec.to_json)
      json["asset_type"].should eq "backdrop"
      json["key"].should eq "backdrop.golden.pg"
      json["pool_key"].should eq json["key"] # the old name, through 0.12
      JSON.parse(db.get_with_meta_by_id(rec.id, touch: false).not_nil![1].not_nil!.to_json)["width"].should eq 64
      JSON.parse(db.registration("backdrop").to_json)["pool_traits"].should eq ["art-style", "rating"]
    end
  end
end

describe "DataDungeon::DB read-only" do
  it "reads, but refuses every write" do
    with_db("dd-read-only") do |db, dir|
      db.register_type("backdrop", pool_traits: %w[art-style rating])
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
