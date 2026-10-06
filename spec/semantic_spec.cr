require "spec"
require "file_utils"
require "../src/data_dungeon/semantic"

describe DataDungeon::SemanticIndex do
  it "indexes descriptions and selected tags, filters results, and keeps search read-only" do
    dir = File.tempname("dd-semantic")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
    index = DataDungeon::SemanticIndex.new(
      db, service: "mock", chunking_max_tokens: 50,
      semantic_tag_keys: ["hair_color"]
    )

    red = db.store("portrait", {"hair_color" => "red", "rating" => "pg"},
      pool_key: "red-portrait", bytes: "red-image".to_slice,
      content_type: "image/webp", description: "A human adventurer", generated: true)
    blue = db.store("portrait", {"hair_color" => "blue", "rating" => "r"},
      pool_key: "blue-portrait", bytes: "blue-image".to_slice,
      content_type: "image/webp", description: "A human mage")
    audio = db.store("audio", {"hair_color" => "blue"}, bytes: "audio".to_slice,
      content_type: "audio/ogg", description: "A spoken greeting")

    index.process_queue.should eq 3
    text = db.connection.query_one(
      "SELECT t.content FROM memo_texts t JOIN memo_sources s ON s.id = t.source_id WHERE s.source_type = 'asset' AND s.external_int = ?",
      red.id, as: String
    )
    text.should eq "A human adventurer\nhair color: red"
    text.should_not contain "rating"

    found = index.search("adventurer", asset_type: "portrait", tags: {"hair_color" => "red"}, min_score: 0.0)
    found.map(&.asset.id).should eq [red.id]
    index.search("adventurer", asset_type: "portrait").size.should eq 2 # no cutoff by default
    index.search("mage", asset_type: "portrait", tags: {"hair_color" => "blue"}, min_score: 0.0)
      .map(&.asset.id).should eq [blue.id]
    index.search("mage", asset_type: "portrait", tags: {"hair_color" => "red' OR 1=1 --"}, min_score: 0.0)
      .should be_empty
    index.search("spoken greeting", media: "audio", min_score: 0.0)
      .map(&.asset.id).should eq [audio.id]

    db.connection.scalar("SELECT COUNT(*) FROM memo_query_cache").as(Int64).should eq 0
    db.connection.scalar("SELECT SUM(match_count) FROM memo_chunks").as(Int64).should eq 0
    db.find_asset_by_id(red.id).not_nil!.use_count.should eq 0

    updated = db.store("portrait", {"hair_color" => "black"},
      pool_key: "red-portrait", bytes: "red-image".to_slice,
      content_type: "image/webp", description: "A wandering knight", generated: true)
    updated.id.should eq red.id
    index.process_queue.should eq 1
    new_text = db.connection.query_one(
      "SELECT t.content FROM memo_texts t JOIN memo_sources s ON s.id = t.source_id WHERE s.external_int = ?",
      red.id, as: String
    )
    new_text.should eq "A wandering knight\nhair color: black"

    db.delete_asset(red.id)
    index.search("knight", asset_type: "portrait", min_score: 0.0)
      .map(&.asset.id).should_not contain red.id
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "backfills assets stored before the index is attached and removes queued deletes" do
    dir = File.tempname("dd-semantic-backfill")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
    old = db.store("scene", bytes: "scene".to_slice, content_type: "image/webp",
      description: "A moonlit castle")
    index = DataDungeon::SemanticIndex.new(db, service: "mock", chunking_max_tokens: 50)
    index.backfill.should eq 1
    index.process_queue.should eq 1
    index.backfill.should eq 0
    index.search("castle", asset_type: "scene", min_score: 0.0)
      .map(&.asset.id).should eq [old.id]

    fresh = db.store("scene", bytes: "another".to_slice, content_type: "image/webp",
      description: "A forest clearing")
    db.delete_asset(fresh.id)
    index.memo.queue_stats.pending.should eq 0
    index.process_queue.should eq 0
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "finds an asset whose exact tag is too rare for the first neighbor batch" do
    dir = File.tempname("dd-semantic-rare")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"))
    index = DataDungeon::SemanticIndex.new(db, service: "mock", chunking_max_tokens: 50)

    ids = [] of Int64
    540.times do |i|
      ids << db.store_asset("portrait", "image", "image/webp", "portrait/#{i}.webp",
        tags: {"group" => "common"}, description: "Distinct portrait #{i} in a meadow")
    end
    index.process_queue.should eq 540

    nearest = index.memo.search("a traveler", limit: 512, min_score: 0.0, include_text: false)
    nearest_ids = nearest.compact_map(&.source_id.as?(Int64)).to_set
    rare = ids.find { |id| !nearest_ids.includes?(id) }.not_nil!
    db.connection.exec("UPDATE asset_tags SET tag_value = 'rare' WHERE asset_id = ? AND tag_key = 'group'", rare)

    index.search("a traveler", asset_type: "portrait", tags: {"group" => "rare"}, min_score: 0.0)
      .map(&.asset.id).should eq [rare]
    db.connection.scalar("SELECT SUM(match_count) FROM memo_chunks").as(Int64).should eq 0
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "ranks only one pool, or one key prefix, of a registered type" do
    dir = File.tempname("dd-semantic-pool")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
    db.register_type("picture", pool_traits: %w[portrait rating state], pool: true)
    index = DataDungeon::SemanticIndex.new(db, service: "mock", chunking_max_tokens: 50)
    picture = ->(portrait : String, state : String, scene : String) do
      db.store("picture", {"portrait" => portrait, "rating" => "pg", "state" => state},
        bytes: scene.to_slice, content_type: "image/webp", description: scene)
    end
    fights = picture.call("1", "troll-alive", "the hero fights a troll")
    flees = picture.call("1", "troll-alive", "the hero runs from a troll")
    stands = picture.call("1", "troll-dead", "the hero stands over a troll")
    picture.call("2", "troll-alive", "another hero fights a troll")
    index.process_queue.should eq 4

    pool = db.pool_key_for("picture", {"portrait" => "1", "rating" => "pg", "state" => "troll-alive"})
    index.search("troll", pool_key: pool).map(&.asset.id).sort.should eq [fights.id, flees.id]
    portrait_one = db.group_key_for("picture", {"portrait" => "1"}, 1)
    index.search("troll", key_prefix: portrait_one).map(&.asset.id).sort
      .should eq [fights.id, flees.id, stands.id]
    index.search("troll", key_prefix: portrait_one, asset_type: "picture", tags: {"state" => "troll-dead"})
      .map(&.asset.id).should eq [stands.id]
    expect_raises(ArgumentError, /must end with/) { index.search("troll", key_prefix: "picture.1") }
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "saves processed vectors and recovers an index file lost before restart" do
    dir = File.tempname("dd-semantic-repair")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"))
    closed = false
    reopened : DataDungeon::DB? = nil
    index = DataDungeon::SemanticIndex.new(db, service: "mock", chunking_max_tokens: 50)
    asset = db.store_asset("scene", "image", "image/webp", "scene/castle.webp",
      description: "A castle on a hill")
    index.process_queue.should eq 1
    path = index.memo.index_path
    File.exists?(path).should be_true
    db.close
    closed = true

    # Memo keeps each vector in the database and rebuilds a missing index
    # file from them on open, so nothing needs embedding again.
    File.delete(path)
    reopened = DataDungeon::DB.new(File.join(dir, "assets.db"))
    repair = DataDungeon::SemanticIndex.new(reopened, service: "mock", chunking_max_tokens: 50)
    repair.memo.index_recovery.rebuilt.should eq 1
    repair.backfill.should eq 0
    repair.search("castle", asset_type: "scene", min_score: 0.0)
      .map(&.asset.id).should eq [asset]
  ensure
    reopened.try(&.close)
    db.try(&.close) unless closed
    FileUtils.rm_rf(dir) if dir
  end
end
