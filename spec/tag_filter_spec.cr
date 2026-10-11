require "spec"
require "file_utils"
require "../src/data_dungeon"

private def with_db(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  # Traits these specs don't filter by, so tag filters start from tag rows.
  {"tile", "backdrop", "decree"}.each { |type| db.register_type(type, pool_traits: %w[name]) }
  yield db
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

private def put(db : DataDungeon::DB, type : String, tags : Hash(String, String), bytes : String, text : String? = nil)
  if text
    db.store(type, tags, bytes: bytes.to_slice, content_type: "text/plain", text: DataDungeon::TextMeta.new(content: text))
  else
    db.store(type, tags, bytes: bytes.to_slice, content_type: "image/webp")
  end
end

describe "DataDungeon::DB tag filters" do
  it "finds assets of the type carrying every filter tag" do
    with_db("dd-tags-basic") do |db|
      both = put(db, "tile", {"style" => "golden", "room" => "attic", "extra" => "x"}, "a")
      put(db, "tile", {"style" => "golden", "room" => "cellar"}, "b")    # one tag differs
      put(db, "tile", {"style" => "golden"}, "c")                        # one tag missing
      put(db, "backdrop", {"style" => "golden", "room" => "attic"}, "d") # another type
      second = put(db, "tile", {"room" => "attic", "style" => "golden"}, "e")

      filter = {"style" => "golden", "room" => "attic"}
      db.find_assets_by_tags("tile", filter).map(&.id).should eq [both.id, second.id]
      db.count_pool_assets("tile", filter).should eq 2
      db.find_assets_by_tags("tile", {"style" => "golden", "room" => "nowhere"}).should be_empty
      db.count_pool_assets("tile", {"room" => "nowhere"}).should eq 0
      db.find_assets_by_tags("tile", {} of String => String).should be_empty
      db.count_pool_assets("tile", {} of String => String).should eq 4
    end
  end

  it "applies connection settings to every pooled connection" do
    with_db("dd-tags-fk") do |db|
      rec = put(db, "tile", {"room" => "attic"}, "a")
      db.connection.using_connection do |first|
        first.scalar("PRAGMA foreign_keys").should eq 1
        db.connection.using_connection do |second| # a second connection, while the first is held
          second.scalar("PRAGMA foreign_keys").should eq 1
          second.scalar("PRAGMA busy_timeout").should eq 5000
          second.exec("DELETE FROM assets WHERE id = ?", rec.id)
        end
      end
      db.connection.scalar("SELECT COUNT(*) FROM asset_tags").should eq 0
    end
  end

  it "picks a random text among the matches" do
    with_db("dd-tags-random") do |db|
      put(db, "decree", {"quest" => "zork", "tone" => "grim"}, "a", text: "grim one")
      put(db, "decree", {"quest" => "zork", "tone" => "jolly"}, "b", text: "jolly one")
      db.random_pool_text("decree", {"quest" => "zork", "tone" => "grim"}).should eq "grim one"
      db.random_pool_text("decree", {"quest" => "zork", "tone" => "sad"}).should be_nil
      %w[grim\ one jolly\ one].should contain db.random_pool_text("decree", {"quest" => "zork"})
    end
  end

  it "uses a registered type's key prefix, and keys an asset an older store left without one" do
    with_db("dd-tags-registered") do |db|
      db.register_type("portrait", pool_traits: %w[art_style rating gender race])
      a = put(db, "portrait", {"art_style" => "golden", "rating" => "pg", "gender" => "f", "race" => "human"}, "a")
      b = put(db, "portrait", {"art_style" => "golden", "rating" => "pg", "gender" => "f", "race" => "elf"}, "b")
      put(db, "portrait", {"art_style" => "golden", "rating" => "pg", "gender" => "fem", "race" => "elf"}, "c")

      filter = {"art_style" => "Golden", "rating" => "pg", "gender" => "f"}
      db.find_assets_by_tags("portrait", filter).map(&.id).should eq [a.id, b.id]
      db.find_assets_by_tags("portrait", filter.merge({"race" => "elf"})).map(&.id).should eq [b.id]
      db.find_assets_by_tags("portrait", {"race" => "elf", "gender" => "f"}).map(&.id).should eq [b.id] # not leading

      # Before 0.11 an asset could lose its key to another (a single-best
      # collision); opening such a store keys it again.
      db.connection.exec("DELETE FROM asset_keys WHERE asset_id = ?", a.id)
      db.connection.exec("UPDATE asset_types SET key_scheme = 3")
      reopened = DataDungeon::DB.new(db.path)
      reopened.find_asset_by_id(a.id).not_nil!.key.should eq "portrait.golden.pg.f.human"
      reopened.find_assets_by_tags("portrait", filter).map(&.id).should eq [a.id, b.id]
      reopened.close
    end
  end
end
