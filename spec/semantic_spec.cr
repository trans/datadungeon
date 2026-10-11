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
    db.register_type("portrait", pool_traits: %w[hair_color rating])
    db.register_type("audio", pool_traits: %w[hair_color])

    red = db.store("portrait", {"hair_color" => "red", "rating" => "pg"}, bytes: "red-image".to_slice,
      content_type: "image/webp", description: "A human adventurer", generated: true)
    blue = db.store("portrait", {"hair_color" => "blue", "rating" => "r"}, bytes: "blue-image".to_slice,
      content_type: "image/webp", description: "A human mage")
    audio = db.store("audio", {"hair_color" => "blue"}, bytes: "audio".to_slice,
      content_type: "audio/ogg", description: "A spoken greeting")

    index.process_queue.should eq 3
    text = db.connection.query_one(
      "SELECT t.content FROM memo_sources s JOIN memo_contents t ON t.id = s.content_id WHERE s.source_type = 'asset' AND s.external_int = ?",
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

    db.update_asset(red.id, tags: {"hair_color" => "black"}, description: "A wandering knight")
    index.process_queue.should eq 1
    new_text = db.connection.query_one(
      "SELECT t.content FROM memo_sources s JOIN memo_contents t ON t.id = s.content_id WHERE s.external_int = ?",
      red.id, as: String
    )
    new_text.should eq "A wandering knight\nhair color: black"

    db.retire(red.id)
    index.search("knight", asset_type: "portrait", min_score: 0.0)
      .map(&.asset.id).should_not contain red.id
    db.reinstate(red.id)
    index.process_queue.should eq 1
    index.search("knight", asset_type: "portrait", min_score: 0.0)
      .map(&.asset.id).should contain red.id

    db.delete_asset(red.id)
    index.search("knight", asset_type: "portrait", min_score: 0.0)
      .map(&.asset.id).should_not contain red.id
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "embeds a dashed tag name like an underscored one, so renaming it re-embeds nothing" do
    dir = File.tempname("dd-semantic-dash")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
    index = DataDungeon::SemanticIndex.new(db, service: "mock", chunking_max_tokens: 50,
      semantic_tag_keys: ["hair_color", "hair-color"])
    db.register_type("portrait", pool_traits: %w[hair_color])
    rec = db.store("portrait", {"hair_color" => "red"}, bytes: "p".to_slice,
      content_type: "image/webp", description: "A human adventurer")
    index.process_queue.should eq 1

    db.rename_tag("portrait", "hair_color", "hair-color").should eq 1
    index.process_queue.should eq 0
    db.connection.query_one(
      "SELECT t.content FROM memo_sources s JOIN memo_contents t ON t.id = s.content_id WHERE s.source_type = 'asset' AND s.external_int = ?",
      rec.id, as: String
    ).should eq "A human adventurer\nhair color: red"
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "backfills assets stored before the index is attached and removes queued deletes" do
    dir = File.tempname("dd-semantic-backfill")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
    db.register_type("scene", pool_traits: %w[place])
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
    db.register_type("portrait", pool_traits: %w[group])

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
    db.register_type("picture", pool_traits: %w[portrait rating state])
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

    pool = db.key_for("picture", {"portrait" => "1", "rating" => "pg", "state" => "troll-alive"})
    index.search("troll", key: pool).map(&.asset.id).sort.should eq [fights.id, flees.id]
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

  it "embeds a registered type's facets separately and ranks them alone or together" do
    dir = File.tempname("dd-semantic-facets")
    Dir.mkdir_p(dir)
    db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
    db.register_type("hero", pool_traits: %w[race hair_color],
      facets: {"identity" => %w[race skin], "hair" => %w[hair_color customization]})
    index = DataDungeon::SemanticIndex.new(db, service: "mock", chunking_max_tokens: 50)
    hero = ->(tags : Hash(String, String), bytes : String) do
      db.store("hero", tags, bytes: bytes.to_slice, content_type: "image/webp", description: "a hero")
    end
    ape = hero.call({"race" => "ape", "skin" => "purple", "hair_color" => "red", "customization" => "braided"}, "a")
    elf = hero.call({"race" => "elf", "skin" => "pale", "hair_color" => "black"}, "b")
    bald = hero.call({"race" => "human"}, "c") # nothing for the hair facet
    index.process_queue.should eq 8            # 3 asset embeddings, 3 identities, 2 hair

    text = ->(source_type : String, id : Int64) do
      db.connection.query_one?(
        "SELECT t.content FROM memo_sources s JOIN memo_contents t ON t.id = s.content_id WHERE s.source_type = ? AND s.external_int = ?",
        source_type, id, as: String)
    end
    text.call("hero.identity", ape.id).should eq "race: ape\nskin: purple"
    text.call("hero.hair", ape.id).should eq "hair color: red\ncustomization: braided"
    text.call("hero.hair", bald.id).should be_nil

    # One facet: the matching text ranks first; assets without the facet never appear.
    top = index.search("race: elf\nskin: pale", asset_type: "hero", facet: "identity").first
    top.asset.id.should eq elf.id
    top.score.should be_close(1.0, 0.01)
    index.search("hair color: red", asset_type: "hero", facet: "hair").map(&.asset.id).sort.should eq [ape.id, elf.id]

    # Together: every facet must be present, and the weakest one scores.
    queries = {"identity" => "race: elf\nskin: pale", "hair" => "hair color: black"}
    found = index.search_facets(queries, asset_type: "hero")
    found.map(&.asset.id).sort.should eq [ape.id, elf.id]
    found.first.asset.id.should eq elf.id
    found.each do |hit|
      hit.facet_scores.keys.sort.should eq %w[hair identity]
      hit.score.should eq hit.facet_scores.values.min
    end

    expect_raises(ArgumentError, /registered asset_type/) { index.search("x", facet: "hair") }
    expect_raises(ArgumentError, /no facet/) { index.search("x", asset_type: "hero", facet: "body") }

    # Deleting an asset removes its embedding and every facet's.
    chunks = ->(id : Int64) do
      db.connection.scalar(
        "SELECT COUNT(*) FROM memo_chunks c JOIN memo_sources s ON s.id = c.source_id WHERE s.external_int = ?", id)
    end
    chunks.call(ape.id).should eq 3
    db.delete_asset(ape.id)
    chunks.call(ape.id).should eq 0
    %w[asset hero.identity hero.hair].each { |source_type| text.call(source_type, ape.id).should be_nil }

    # Dropping a facet removes its sources at the next backfill.
    db.register_type("hero", pool_traits: %w[race hair_color],
      facets: {"identity" => %w[race skin]}, rekey: true)
    index.backfill
    text.call("hero.hair", elf.id).should be_nil
    text.call("hero.identity", elf.id).should eq "race: elf\nskin: pale"
    expect_raises(ArgumentError, /no facet/) { index.search("x", asset_type: "hero", facet: "hair") }
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
    db.register_type("scene", pool_traits: %w[place])
    asset = db.store_asset("scene", "image", "image/webp", "scene/castle.webp",
      description: "A castle on a hill")
    index.process_queue.should eq 1
    path = index.memo.index_path
    db.close # saves the index, whatever Memo's save policy had scheduled
    closed = true
    File.exists?(path).should be_true

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
