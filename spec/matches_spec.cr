require "spec"
require "file_utils"
require "../src/data_dungeon/matches"
require "../src/data_dungeon/http"

private def with_store(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  yield db, dir
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

private def portrait(db, n : Int32, **traits) : DataDungeon::AssetRecord
  db.store("portrait", traits.to_h.transform_keys(&.to_s.tr("_", "-")), bytes: "p#{n}".to_slice, content_type: "image/webp")
end

private def register(db, rekey = false)
  db.register_type("portrait", pool_traits: %w[art-style rating race hair skin items],
    scales: {"rating" => %w[G PG R X]}, colors: %w[hair skin], sets: %w[items], rekey: rekey)
end

private def ids(matches : Array(DataDungeon::BestMatch)) : Array(Int64)
  matches.map(&.asset.id)
end

describe DataDungeon::MatchIndex do
  it "keeps scales, colors and weights in the registration, validated and through renames" do
    with_store("dd-match-reg") do |db, dir|
      db.register_type("portrait", pool_traits: %w[style rating hair], scales: {"rating" => %w[G PG R]},
        colors: %w[hair], weights: {"style" => 4.0})
      expect_raises(ArgumentError, /scale size is not a pool trait/) do
        db.register_type("t", pool_traits: %w[a], scales: {"size" => %w[s m]})
      end
      expect_raises(ArgumentError, /at least two values/) { db.register_type("t", pool_traits: %w[a], scales: {"a" => %w[x]}) }
      expect_raises(ArgumentError, /must be positive/) { db.register_type("t", pool_traits: %w[a], weights: {"a" => 0.0}) }
      expect_raises(ArgumentError, /can't be a color/) do
        db.register_type("t", pool_traits: %w[a], scales: {"a" => %w[x y]}, colors: %w[a])
      end
      db.rename_tag("portrait", "hair", "hair-color")
      db.close

      reopened = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
      begin
        type = reopened.registration("portrait").not_nil!
        type.scales.should eq({"rating" => %w[g pg r]}) # normalized like trait values
        type.colors.should eq ["hair-color"]
        type.weights.should eq({"style" => 4.0})
      ensure
        reopened.close
      end
    end
  end

  it "ranks the closest first, weighted, with required traits exact" do
    with_store("dd-match-rank") do |db|
      register(db)
      exact = portrait(db, 1, art_style: "golden", rating: "pg", race: "elf", hair: "red")
      other_race = portrait(db, 2, art_style: "golden", rating: "pg", race: "orc", hair: "red")
      other_hair = portrait(db, 3, art_style: "golden", rating: "pg", race: "elf", hair: "blue")
      other_style = portrait(db, 4, art_style: "silver", rating: "pg", race: "elf", hair: "red")
      index = DataDungeon::MatchIndex.new(db)
      begin
        picks = {"art-style" => "Golden", "rating" => "PG", "race" => "elf", "hair" => "red"}
        found = index.best_matches("portrait", picks)
        found.first.asset.id.should eq exact.id
        found.first.score.should eq 4.0
        ids(found).size.should eq 4

        ids(index.best_matches("portrait", picks, require: %w[art-style])).should_not contain other_style.id
        ids(index.best_matches("portrait", picks, weights: {"race" => 5.0})).last.should eq other_race.id
        ids(index.best_matches("portrait", picks, weights: {"hair" => 5.0})).last.should eq other_hair.id
        ids(index.best_matches("portrait", picks, weights: {"art-style" => 5.0})).last.should eq other_style.id
        index.best_matches("portrait", picks.merge({"race" => "gnome"}), require: %w[race]).should be_empty
        expect_raises(ArgumentError, /not picked/) { index.best_matches("portrait", {"race" => "elf"}, require: %w[hair]) }
        expect_raises(ArgumentError, /Pick at least one/) { index.best_matches("portrait", {"nope" => "x"}) }
        expect_raises(ArgumentError, /not a registered/) { index.best_matches("venue", picks) }
        # Each is one trait off; blue is a hair closer to red than no match at
        # all, and the two exact ties come newest first.
        ids(index.similar(exact.id)).should eq [other_hair.id, other_style.id, other_race.id]
        ids(index.similar(exact.id)).should_not contain exact.id
      ensure
        index.close
      end
    end
  end

  it "counts near values on a scale, alike colors and shared set members as close" do
    with_store("dd-match-near") do |db|
      register(db)
      pg = portrait(db, 1, rating: "PG", race: "elf")
      r = portrait(db, 2, rating: "R", race: "elf")
      x = portrait(db, 3, rating: "X", race: "elf")
      crimson = portrait(db, 4, race: "orc", hair: "crimson")
      navy = portrait(db, 5, race: "orc", hair: "navy")
      hex_red = portrait(db, 6, race: "orc", hair: "#ff1100")
      rainbow = portrait(db, 7, race: "orc", hair: "rainbow")
      kit = portrait(db, 8, race: "gnome", items: "lantern, sword, rope")
      pair = portrait(db, 9, race: "gnome", items: "lantern, sword")
      other = portrait(db, 10, race: "gnome", items: "shield")
      index = DataDungeon::MatchIndex.new(db)
      begin
        ids(index.best_matches("portrait", {"rating" => "g", "race" => "elf"}, require: %w[race])).should eq [pg.id, r.id, x.id]
        ids(index.best_matches("portrait", {"hair" => "red", "race" => "orc"}, require: %w[race], limit: 3))
          .should eq [hex_red.id, crimson.id, navy.id]
        ids(index.best_matches("portrait", {"hair" => "rainbow", "race" => "orc"}, require: %w[race], limit: 1)).should eq [rainbow.id]
        rainbow_score = index.best_matches("portrait", {"hair" => "rainbow"}, require: %w[hair])
        ids(rainbow_score).should eq [rainbow.id] # a name it doesn't know matches only itself
        ids(index.best_matches("portrait", {"items" => "sword, lantern", "race" => "gnome"}, require: %w[race]))
          .should eq [pair.id, kit.id, other.id]

        DataDungeon::MatchIndex.color("dark-salmon").should eq 0xE9967A
        DataDungeon::MatchIndex.color("a52a2a").should eq 0xA52A2A
        DataDungeon::MatchIndex.color("rainbow").should be_nil
      ensure
        index.close
      end
    end
  end

  it "catches up on writes from any connection, and on what changed while closed" do
    with_store("dd-match-catchup") do |db, dir|
      register(db)
      first = portrait(db, 1, race: "elf", hair: "red")
      index = DataDungeon::MatchIndex.new(db)
      begin
        ids(index.best_matches("portrait", {"race" => "elf"})).should eq [first.id]

        other = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store")) # another process
        second = other.store("portrait", {"race" => "elf", "hair" => "red"}, bytes: "p2".to_slice, content_type: "image/webp")
        other.close
        ids(index.best_matches("portrait", {"race" => "elf", "hair" => "red"})).should eq [second.id, first.id]

        db.update_asset(first.id, tags: {"race" => "orc", "hair" => "red"})
        index.best_matches("portrait", {"race" => "elf"}, require: %w[race]).map(&.asset.id).should eq [second.id]
        db.delete_asset(second.id)
        index.best_matches("portrait", {"race" => "elf"}, require: %w[race]).should be_empty
      ensure
        index.close
      end

      File.exists?(File.join(dir, "assets.db.matches", "portrait.usearch.checkpoint")).should be_true
      third = portrait(db, 3, race: "elf", hair: "blue") # written while no index is open
      reopened = DataDungeon::MatchIndex.new(db)
      begin
        ids(reopened.best_matches("portrait", {"race" => "elf"}, require: %w[race])).should eq [third.id]
      ensure
        reopened.close
      end

      fourth = portrait(db, 4, race: "elf", hair: "blue")
      db.connection.exec("DELETE FROM asset_changes") # as if pruned past the checkpoint
      rebuilt = DataDungeon::MatchIndex.new(db)
      begin
        ids(rebuilt.best_matches("portrait", {"race" => "elf"}, require: %w[race])).should eq [fourth.id, third.id]
      ensure
        rebuilt.close
      end
    end
  end

  it "leaves retired assets out, and prefers the newest made among equals" do
    with_store("dd-match-retired") do |db|
      register(db)
      older = db.store("portrait", {"race" => "elf"}, bytes: "1".to_slice, content_type: "image/webp",
        made_at: Time.utc(2026, 1, 1))
      newer = db.store("portrait", {"race" => "elf"}, bytes: "2".to_slice, content_type: "image/webp",
        made_at: Time.utc(2026, 5, 1))
      filed_last = db.store("portrait", {"race" => "elf"}, bytes: "3".to_slice, content_type: "image/webp",
        made_at: Time.utc(2025, 1, 1))
      index = DataDungeon::MatchIndex.new(db)
      begin
        ids(index.best_matches("portrait", {"race" => "elf"})).should eq [newer.id, older.id, filed_last.id]
        db.retire(newer.id)
        ids(index.best_matches("portrait", {"race" => "elf"})).should eq [older.id, filed_last.id]
        db.store("portrait", {"race" => "elf"}, bytes: "4".to_slice, content_type: "image/webp",
          made_at: Time.utc(2024, 1, 1), supersedes: older.id)
        index.best_matches("portrait", {"race" => "elf"}).map(&.asset.id).should_not contain older.id
        db.reinstate(newer.id)
        ids(index.best_matches("portrait", {"race" => "elf"})).first.should eq newer.id
      ensure
        index.close
      end
      rebuilt = DataDungeon::MatchIndex.new(db) # from the saved file, then the tags
      begin
        rebuilt.best_matches("portrait", {"race" => "elf"}).map(&.asset.id).should_not contain older.id
      ensure
        rebuilt.close
      end
    end
  end

  it "leaves flagged assets out, and prefers the highest rating among equals" do
    with_store("dd-match-rating") do |db|
      register(db)
      plain = db.store("portrait", {"race" => "elf"}, bytes: "1".to_slice, content_type: "image/webp",
        made_at: Time.utc(2026, 5, 1))
      loved = db.store("portrait", {"race" => "elf"}, bytes: "2".to_slice, content_type: "image/webp",
        made_at: Time.utc(2026, 1, 1))
      reported = db.store("portrait", {"race" => "elf"}, bytes: "3".to_slice, content_type: "image/webp",
        made_at: Time.utc(2026, 6, 1))
      db.update_asset(loved.id, rating: 2)
      db.update_asset(reported.id, flagged: true)
      index = DataDungeon::MatchIndex.new(db)
      begin
        ids(index.best_matches("portrait", {"race" => "elf"})).should eq [loved.id, plain.id]
        db.update_asset(reported.id, flagged: false) # cleared
        ids(index.best_matches("portrait", {"race" => "elf"})).should eq [loved.id, reported.id, plain.id]
      ensure
        index.close
      end
    end
  end

  it "rebuilds when what the vectors mean changes, and lets one process own the files" do
    with_store("dd-match-rebuild") do |db|
      db.register_type("portrait", pool_traits: %w[rating race])
      pg = portrait(db, 1, rating: "pg", race: "elf")
      r = portrait(db, 2, rating: "r", race: "elf")
      x = portrait(db, 3, rating: "x", race: "elf")
      index = DataDungeon::MatchIndex.new(db)
      begin
        expect_raises(DataDungeon::MatchIndex::InUse) { DataDungeon::MatchIndex.new(db) }
        index.best_matches("portrait", {"rating" => "g"}).map(&.score).uniq.should eq [0.0] # words: no near values

        db.register_type("portrait", pool_traits: %w[rating race], scales: {"rating" => %w[g pg r x]})
        ids(index.best_matches("portrait", {"rating" => "g"})).should eq [pg.id, r.id, x.id]
      ensure
        index.close
      end
    end
  end

  it "follows a type renamed and another joined to it, and clears the old names' files when it opens" do
    with_store("dd-match-rename") do |db|
      %w[owl_scene owl_frame].each { |type| db.register_type(type, pool_traits: %w[rating race]) }
      scene = db.store("owl_scene", {"rating" => "pg", "race" => "elf"}, bytes: "s".to_slice, content_type: "image/webp")
      frame = db.store("owl_frame", {"rating" => "pg", "race" => "orc"}, bytes: "f".to_slice, content_type: "image/webp")
      files = -> { Dir.children("#{db.path}.matches").select(&.ends_with?(".usearch")).sort }
      index = DataDungeon::MatchIndex.new(db)
      begin
        ids(index.best_matches("owl_scene", {"race" => "elf"})).should eq [scene.id]
        ids(index.best_matches("owl_frame", {"race" => "orc"})).should eq [frame.id]
        db.rename_type("owl_scene", "drop")
        ids(index.best_matches("drop", {"race" => "orc"})).should eq [scene.id]
        db.rename_type("owl_frame", "drop") # joins: caught up from the changes logged
        ids(index.best_matches("drop", {"race" => "orc"})).should eq [frame.id, scene.id]
        files.call.should eq %w[drop.usearch owl_frame.usearch owl_scene.usearch]
      ensure
        index.close
      end
      DataDungeon::MatchIndex.new(db).close
      files.call.should eq %w[drop.usearch]
    end
  end

  it "answers best matches and similar assets over the API, when it has a matcher" do
    with_store("dd-match-api") do |db|
      register(db)
      elf = portrait(db, 1, race: "elf", hair: "red")
      orc = portrait(db, 2, race: "orc", hair: "red")
      index = DataDungeon::MatchIndex.new(db)
      begin
        api = DataDungeon::API.new(db, matcher: index)
        get = ->(path : String) do
          io = IO::Memory.new
          response = HTTP::Server::Response.new(io)
          api.call(HTTP::Server::Context.new(HTTP::Request.new("GET", path), response))
          response.close
          HTTP::Client::Response.from_io(io.rewind)
        end
        found = JSON.parse(get.call("/types/portrait/matches?trait.race=elf&trait.hair=red&limit=5").body)["matches"]
        found.as_a.map(&.["asset"]["id"]).should eq [elf.id, orc.id]
        found[0]["score"].should eq 2.0
        found[0]["tags"]["race"].should eq "elf"
        JSON.parse(get.call("/types/portrait/matches?trait.race=elf&require=race").body)["matches"].size.should eq 1
        JSON.parse(get.call("/types/portrait/matches?trait.hair=red&weight.hair=2").body)["matches"][0]["score"].should eq 2.0
        JSON.parse(get.call("/assets/#{elf.id}/similar").body)["matches"].as_a.map(&.["asset"]["id"]).should eq [orc.id]
        get.call("/types/portrait/matches?trait.race=elf&weight.race=x").status_code.should eq 400
        get.call("/types/portrait/matches").status_code.should eq 400

        plain = DataDungeon::API.new(db)
        io = IO::Memory.new
        response = HTTP::Server::Response.new(io)
        plain.call(HTTP::Server::Context.new(HTTP::Request.new("GET", "/types/portrait/matches?trait.race=elf"), response))
        response.close
        HTTP::Client::Response.from_io(io.rewind).status_code.should eq 404
      ensure
        index.close
      end
    end
  end
end
