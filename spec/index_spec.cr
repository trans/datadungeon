require "spec"
require "file_utils"
require "../src/data_dungeon"

# Each consumer keeps its own indexes on a shared type; a lookup by traits
# starts from whichever index range (or tag) is narrowest.
private def open_db(dir : String, consumer : String? = nil) : DataDungeon::DB
  DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"), consumer: consumer)
end

private def with_dir(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  yield dir
ensure
  FileUtils.rm_rf(dir) if dir
end

private def line(db, bit : String, voice : String, bytes : String, fmt = "mp3") : DataDungeon::AssetRecord
  db.store("speech", {"voice" => voice, "bit" => bit, "beat" => "0", "fmt" => fmt},
    bytes: bytes.to_slice, content_type: "audio/mpeg")
end

class DataDungeon::DB
  # Where tag_filter starts reading for voice assets with these tags: a
  # table, or which index's keys.
  def start_for_spec(tags : Hash(String, String)) : String
    from, _, args = tag_filter("speech", normalize_tags("speech", tags)).not_nil!
    table = from.sub(" CROSS JOIN assets a", "")
    return table unless table == "asset_keys k"
    consumer, name = @db.query_one("SELECT consumer, name FROM asset_indexes WHERE id = ?", args[0], as: {String, String})
    consumer.empty? ? "the type's own index" : "#{consumer}'s #{name}"
  end
end

private def keys(db, index : DataDungeon::AssetIndex) : Array(String)
  db.connection.query_all("SELECT key FROM asset_keys WHERE index_id = ? ORDER BY asset_id", index.id, as: String)
end

describe "Indexes per consumer" do
  it "keys every asset of the type, old and new, as their traits change" do
    with_dir("dd-index") do |dir|
      db = open_db(dir, consumer: "cattacula")
      db.register_type("speech", pool_traits: %w[voice bit beat fmt])
      old = line(db, "b1", "fable", "1")

      index = db.register_index("speech", "lines", traits: %w[bit beat voice fmt])
      index.consumer.should eq "cattacula"
      keys(db, index).should eq ["speech.b1.0.fable.mp3"]

      fresh = line(db, "b2", "Onyx", "2")
      keys(db, index).should eq ["speech.b1.0.fable.mp3", "speech.b2.0.onyx.mp3"]
      db.update_asset(fresh.id, tags: {"voice" => "onyx", "bit" => "b3", "beat" => "1", "fmt" => "mp3"})
      keys(db, index).should eq ["speech.b1.0.fable.mp3", "speech.b3.1.onyx.mp3"]
      db.delete_asset(old.id)
      keys(db, index).should eq ["speech.b3.1.onyx.mp3"]
    ensure
      db.try(&.close)
    end
  end

  it "finds by an index's leading traits what the type's own key can't reach" do
    with_dir("dd-index-find") do |dir|
      db = open_db(dir, consumer: "cattacula")
      db.register_type("speech", pool_traits: %w[voice bit beat fmt])
      db.register_index("speech", "lines", traits: %w[bit beat voice fmt])
      a = line(db, "b1", "fable", "1")
      b = line(db, "b1", "onyx", "2")
      line(db, "b2", "fable", "3")
      retired = line(db, "b1", "nova", "4")
      db.retire(retired.id)

      db.list_assets("speech", {"bit" => "b1", "beat" => "0"}).map(&.id).should eq [b.id, a.id]
      db.count_assets("speech", {"bit" => "B1"}).should eq 2
      db.find_assets_by_tags("speech", {"bit" => "b1", "fmt" => "mp3"}).map(&.id).should eq [a.id, b.id]
      db.list_assets("speech", {"bit" => "b9"}).should be_empty
    ensure
      db.try(&.close)
    end
  end

  it "starts from the narrowest range" do
    with_dir("dd-index-plan") do |dir|
      db = open_db(dir, consumer: "park")
      db.register_type("speech", pool_traits: %w[voice bit beat fmt])
      db.register_index("speech", "lines", traits: %w[bit beat voice fmt])
      5.times { |i| line(db, "b1", "fable", "f#{i}") }
      onyx = line(db, "b1", "onyx", "o")
      wav = line(db, "b1", "fable", "w", fmt: "wav")

      db.indexes("speech").map(&.name).should eq ["lines"] # consumers' only
      db.start_for_spec({"bit" => "b1", "voice" => "onyx"}).should eq "the type's own index" # 1
      db.start_for_spec({"bit" => "b1", "beat" => "0"}).should eq "park's lines"             # 7
      db.start_for_spec({"bit" => "b1", "fmt" => "wav"}).should eq "asset_tags x" # the rare tag: 1
      db.list_assets("speech", {"bit" => "b1", "voice" => "onyx"}).map(&.id).should eq [onyx.id]
      db.list_assets("speech", {"bit" => "b1", "fmt" => "wav"}).map(&.id).should eq [wav.id]
    ensure
      db.try(&.close)
    end
  end

  it "changes only on rekey, and only the consumer's own" do
    with_dir("dd-index-own") do |dir|
      cattacula = open_db(dir, consumer: "cattacula")
      cattacula.register_type("speech", pool_traits: %w[voice bit beat fmt])
      line(cattacula, "b1", "fable", "1")
      mine = cattacula.register_index("speech", "lines", traits: %w[bit beat voice fmt])
      cattacula.register_index("speech", "lines", traits: %w[bit beat voice fmt]).id.should eq mine.id # unchanged
      expect_raises(ArgumentError, /cattacula's index lines on speech is bit beat voice fmt: pass rekey: true/) do
        cattacula.register_index("speech", "lines", traits: %w[bit voice])
      end
      changed = cattacula.register_index("speech", "lines", traits: %w[bit voice], rekey: true)
      changed.id.should eq mine.id
      keys(cattacula, changed).should eq ["speech.b1.fable"]

      park = open_db(dir, consumer: "park")
      theirs = park.register_index("speech", "lines", traits: %w[fmt voice])
      theirs.id.should_not eq mine.id
      park.indexes("speech").map { |index| {index.consumer, index.name} }.should eq [{"cattacula", "lines"}, {"park", "lines"}]
      park.unregister_index("speech", "lines").should be_true
      park.unregister_index("speech", "lines").should be_false
      cattacula.indexes("speech").map(&.id).should eq [mine.id]
    ensure
      cattacula.try(&.close)
      park.try(&.close)
    end
  end

  it "keeps the keys of an index another process registered after it opened" do
    with_dir("dd-index-other") do |dir|
      writer = open_db(dir, consumer: "cattacula")
      writer.register_type("speech", pool_traits: %w[voice bit beat fmt])
      reader = open_db(dir, consumer: "park")
      index = reader.register_index("speech", "by-bit", traits: %w[bit])

      line(writer, "b1", "fable", "1") # writer never saw the index registered
      keys(reader, index).should eq ["speech.b1"]
    ensure
      writer.try(&.close)
      reader.try(&.close)
    end
  end

  it "moves indexes with a renamed type or tag" do
    with_dir("dd-index-rename") do |dir|
      db = open_db(dir, consumer: "cattacula")
      db.register_type("speech", pool_traits: %w[voice bit beat fmt])
      line(db, "b1", "fable", "1")
      db.register_index("speech", "lines", traits: %w[bit beat voice fmt])

      db.rename_tag("speech", "bit", "line")
      db.indexes("speech").first.traits.should eq %w[line beat voice fmt]
      db.rename_type("speech", "recording")
      db.indexes("speech").should be_empty
      moved = db.indexes("recording").first
      keys(db, moved).should eq ["recording.b1.0.fable.mp3"]
      db.list_assets("recording", {"line" => "b1"}).size.should eq 1
    ensure
      db.try(&.close)
    end
  end

  it "rejects an index without a consumer, on unknown traits, or misnamed" do
    with_dir("dd-index-bad") do |dir|
      anonymous = open_db(dir)
      anonymous.register_type("speech", pool_traits: %w[voice bit beat fmt])
      expect_raises(ArgumentError, /consumer:/) { anonymous.register_index("speech", "lines", traits: %w[bit]) }
      anonymous.close

      db = open_db(dir, consumer: "cattacula")
      expect_raises(ArgumentError, /mood are not traits of speech/) { db.register_index("speech", "lines", traits: %w[bit mood]) }
      expect_raises(ArgumentError, /listed twice/) { db.register_index("speech", "lines", traits: %w[bit bit]) }
      expect_raises(ArgumentError, /lowercase words/) { db.register_index("speech", "Lines", traits: %w[bit]) }
      expect_raises(ArgumentError, /not a registered asset type/) { db.register_index("texture", "lines", traits: %w[bit]) }
      expect_raises(ArgumentError, /consumer "Cattacula"/) { open_db(dir, consumer: "Cattacula") }
    ensure
      db.try(&.close)
    end
  end
end
