require "spec"
require "file_utils"
require "../src/data_dungeon"

# Retiring hides an asset without deleting it: superseded takes, and curio's
# soft delete. Pruning, the application's call, deletes retired assets.
private def with_db(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("voice", pool_traits: %w[bit voice])
  yield db
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

private def take(db, bytes : String, supersedes : Int64? = nil, bit = "b1") : DataDungeon::AssetRecord
  db.store("voice", {"bit" => bit, "voice" => "fable"}, bytes: bytes.to_slice, content_type: "audio/mpeg",
    supersedes: supersedes)
end

# The kept counts, and the same counted afresh from the tables.
private def counts(db) : {Array({String, String, String, Int64, Int64}), Array({String, String, String, Int64, Int64})}
  kept = db.connection.query_all("SELECT * FROM asset_tag_counts ORDER BY 1, 2, 3",
    as: {String, String, String, Int64, Int64})
  fresh = DataDungeon::DB::COUNT_TAGS.flat_map do |sql|
    db.connection.query_all(sql.sub(/\A\s*INSERT INTO[^\n]*\n/, ""), as: {String, String, String, Int64, Int64})
  end
  {kept, fresh.sort}
end

describe "Retiring" do
  it "keeps tag counts right through every kind of write" do
    with_db("dd-tag-counts") do |db|
      a = take(db, "1")
      b = take(db, "2", supersedes: a.id)
      c = take(db, "3", bit: "b2")
      db.register_type("picture", pool_traits: %w[room])
      db.store("picture", {"room" => "attic", "note" => "x"}, bytes: "p".to_slice, content_type: "image/webp")
      db.update_asset(c.id, tags: {"bit" => "b3", "voice" => "onyx"})
      db.retire(c.id)
      db.reinstate(a.id)
      db.update_asset(b.id, tags: {"bit" => "b9", "voice" => "fable"}) # a retired asset's tags
      db.rename_tag("voice", "voice", "speaker")
      db.rename_type("picture", "image")
      db.register_type("image", pool_traits: %w[room])
      db.delete_asset(c.id)
      kept, fresh = counts(db)
      kept.should eq fresh
      kept.should contain({"voice", "", "", 1_i64, 1_i64})
      kept.should contain({"voice", "bit", "b9", 0_i64, 1_i64})

      db.prune("voice")
      kept, fresh = counts(db)
      kept.should eq fresh
      db.asset_types.should eq({"image" => 1, "voice" => 1})
    end
  end

  it "retires an asset with nothing replacing it, and reinstates it" do
    with_db("dd-retire") do |db|
      first = take(db, "1")
      second = take(db, "2")

      db.retire(second.id).should be_true
      db.retire(second.id).should be_false # already retired
      db.get("voice", {"bit" => "b1", "voice" => "fable"}, touch: false).not_nil!.id.should eq first.id
      db.find_pool("voice", {"bit" => "b1", "voice" => "fable"}).map(&.id).should eq [first.id]
      db.find_asset_by_id(second.id).not_nil!.retired_at.should_not be_nil # still there by id

      db.reinstate(second.id).should be_true
      db.reinstate(second.id).should be_false # already current
      db.get("voice", {"bit" => "b1", "voice" => "fable"}, touch: false).not_nil!.id.should eq second.id
    end
  end

  it "lists and counts current assets unless asked for retired ones" do
    with_db("dd-retired-lists") do |db|
      kept = take(db, "1")
      gone = take(db, "2", bit: "b2")
      db.retire(gone.id)

      db.list_assets("voice").map(&.id).should eq [kept.id]
      db.list_assets("voice", retired: true).map(&.id).should eq [gone.id]
      db.list_assets("voice", retired: nil).map(&.id).should eq [gone.id, kept.id]
      db.list_assets("voice", {"bit" => "b2"}).should be_empty
      db.list_assets(q: "b2", retired: true).map(&.id).should eq [gone.id]
      db.count_assets("voice").should eq 1
      db.count_assets("voice", retired: nil).should eq 2
      db.asset_types.should eq({"voice" => 1})
      db.asset_types(retired: true).should eq({"voice" => 1})
      db.tag_values("voice", "bit").should eq({"b1" => 1})
      db.tag_values("voice", "bit", retired: true).should eq({"b2" => 1})
      db.tag_keys("voice", retired: nil).should eq({"bit" => 2, "voice" => 2})
      db.asset_exists?(gone.key.not_nil!).should be_false
      db.find_by_hash(gone.file_hash.not_nil!).map(&.id).should eq [gone.id] # by its bytes, retired or not
    end
  end

  it "reinstates a superseded take over the take that replaced it" do
    with_db("dd-reinstate") do |db|
      original = take(db, "original")
      redo = take(db, "redo", supersedes: original.id)

      db.reinstate(original.id).should be_true
      db.find_asset_by_id(redo.id).not_nil!.retired?.should be_true
      db.get("voice", {"bit" => "b1", "voice" => "fable"}, touch: false).not_nil!.id.should eq original.id
      db.links_from(original.id, "supersedes").map(&.to_id).should eq [redo.id]
      db.links_from(redo.id, "supersedes").should be_empty
    end
  end

  it "reinstates a take over the current one down a chain of takes" do
    with_db("dd-reinstate-chain") do |db|
      t1 = take(db, "1")
      t2 = take(db, "2", supersedes: t1.id)
      t3 = take(db, "3", supersedes: t2.id)

      db.reinstate(t1.id).should be_true
      db.find_pool("voice", {"bit" => "b1", "voice" => "fable"}).map(&.id).should eq [t1.id]
      db.links_from(t1.id, "supersedes").map(&.to_id).should eq [t3.id]
      db.links_to(t1.id, "supersedes").should be_empty
      db.links_from(t3.id, "supersedes").map(&.to_id).should eq [t2.id] # the rest of the history

      db.reinstate(t1.id).should be_false # already current: left as it is
      db.find_asset_by_id(t3.id).not_nil!.retired?.should be_true
    end
  end

  it "copies the old take's links to the new one" do
    with_db("dd-supersede-links") do |db|
      old = take(db, "old")
      db.register_type("picture", pool_traits: %w[room])
      picture = db.store("picture", bytes: "p".to_slice, content_type: "image/webp")
      db.link(old.id, "used-by", "boardwalk")
      db.link(old.id, "derived-from", picture.id)

      redo = take(db, "new", supersedes: old.id)
      db.links_from(redo.id).map { |link| {link.rel, link.to_id || link.to_name} }
        .should eq [{"used-by", "boardwalk"}, {"derived-from", picture.id}, {"supersedes", old.id}]
      db.links_from(old.id).size.should eq 2 # its own kept, hidden with it
    end
  end

  it "supersedes only within a type" do
    with_db("dd-supersede-check") do |db|
      voice = take(db, "v")
      db.register_type("picture", pool_traits: %w[room])
      picture = db.store("picture", bytes: "p".to_slice, content_type: "image/webp")

      expect_raises(ArgumentError, /is a picture/) { db.supersede(picture.id, voice.id) }
      expect_raises(ArgumentError, /itself/) { db.supersede(voice.id, voice.id) }
      expect_raises(ArgumentError, /No asset 999/) { db.supersede(voice.id, 999_i64) }
      db.find_asset_by_id(voice.id).not_nil!.retired?.should be_false
    end
  end

  it "prunes retired assets, keeping the last few of a key or the recent ones" do
    with_db("dd-prune") do |db|
      t1 = take(db, "1")
      t2 = take(db, "2", supersedes: t1.id)
      t3 = take(db, "3", supersedes: t2.id)
      t4 = take(db, "4", supersedes: t3.id)
      other = take(db, "x", bit: "b2")
      db.retire(other.id)
      db.connection.exec("UPDATE assets SET retired_at = '2026-01-01 00:00:00' WHERE id IN (?, ?)", t1.id, t2.id)

      db.prune("voice", keep_last: 1, retired_before: Time.utc(2026, 2, 1)).should eq 2 # t1, t2
      db.find_asset_by_id(t1.id).should be_nil
      db.find_asset_by_id(t3.id).should_not be_nil
      db.find_asset_by_id(other.id).should_not be_nil # each key keeps its last
      db.prune("picture").should eq 0

      db.prune("voice").should eq 2 # t3 and other; t4 is current
      db.find_asset_by_id(t4.id).not_nil!.retired?.should be_false
      db.check_consistency.clean?.should be_true
    end
  end
end
