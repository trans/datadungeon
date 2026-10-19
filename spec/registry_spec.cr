require "spec"
require "file_utils"
require "../src/data_dungeon"

private def open_db(dir : String) : DataDungeon::DB
  DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
end

private def with_db(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = open_db(dir)
  yield db, dir
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

# Most important first; the group is the first three.
PORTRAIT_TRAITS = %w[art_style rating gender race hair_color facial_hair]
PORTRAIT_GROUP  = %w[art_style rating gender]

private def register_portraits(db : DataDungeon::DB) : Nil
  db.register_type("portrait", pool_traits: PORTRAIT_TRAITS, group_traits: PORTRAIT_GROUP,
    labels: {"hair_color" => "hair"})
end

private def portrait(**overrides) : Hash(String, String)
  traits = {"art_style" => "golden", "gender" => "f", "hair_color" => "red", "race" => "human", "rating" => "pg"}
  overrides.each { |key, value| traits[key.to_s] = value }
  traits
end

private def store_portrait(db : DataDungeon::DB, traits : Hash(String, String), bytes : String, custom = [] of String)
  db.store("portrait", traits, bytes: bytes.to_slice, content_type: "image/webp", custom: custom)
end

# An asset of a type nobody has registered, as a store from before 0.12 could
# hold one: written straight into the tables, since storing now needs a
# registered type.
private def store_legacy(db : DataDungeon::DB, asset_type : String, tags : Hash(String, String),
                         made_at : String = "2026-01-01 00:00:00") : Int64
  conn = db.connection
  conn.exec("INSERT INTO assets (asset_type, media, content_type, file_path, created_at, made_at) " \
            "VALUES (?, 'image', 'image/webp', ?, ?, ?)", asset_type, "#{asset_type}/#{Random::Secure.hex(4)}.webp",
    made_at, made_at)
  id = conn.scalar("SELECT last_insert_rowid()").as(Int64)
  tags.each do |key, value|
    conn.exec("INSERT INTO asset_tags (asset_id, asset_type, tag_key, tag_value) VALUES (?, ?, ?, ?)",
      id, asset_type, key, value)
  end
  id
end

describe DataDungeon::TraitKey do
  it "lists DataDungeon's asset types, each a name a type can have, in media a store knows" do
    names = DataDungeon::DB::STANDARD_TYPES.map(&.name)
    names.first(3).should eq %w[drop plug placard]
    names.uniq.should eq names
    names.each { |name| name.should match DataDungeon::DB::TYPE_NAME }
    DataDungeon::DB::STANDARD_TYPES.flat_map(&.media).uniq.sort.should eq %w[audio data font image model text video]
    DataDungeon::DB.standard_type?("speech").should be_true
    DataDungeon::DB.standard_type?("automaton").should be_true # the Bard's graph (mj; Thomas, 2026-10-19)
    DataDungeon::DB.standard_type?("owl_scene").should be_false
  end

  it "starts with the type, then the trait values in order, with an empty segment for an absent trait" do
    traits = %w[art_style rating gender race]
    values = {"art_style" => "golden", "rating" => "pg", "gender" => "f", "race" => "human"}
    DataDungeon::TraitKey.key("portrait", traits, values).should eq "portrait.golden.pg.f.human"
    DataDungeon::TraitKey.key("portrait", traits, values.reject("rating")).should eq "portrait.golden..f.human"
    DataDungeon::TraitKey.prefix("portrait", traits, values, 2).should eq "portrait.golden.pg."
    DataDungeon::TraitKey.prefix("portrait", traits, values, 0).should eq "portrait."
  end

  it "suffixes labelled traits so their values read unambiguously" do
    traits = %w[race skin hair_length hair_texture hair_color]
    values = {"race" => "human", "skin" => "tan", "hair_length" => "long", "hair_texture" => "straight", "hair_color" => "black"}
    labels = {"skin" => "skin", "hair_length" => "hair", "hair_texture" => "hair", "hair_color" => "hair"}
    DataDungeon::TraitKey.key("hero", traits, values, labels).should eq "hero.human.tan-skin.long-hair.straight-hair.black-hair"
    DataDungeon::TraitKey.key("hero", traits, values.reject("hair_texture"), labels).should eq "hero.human.tan-skin.long-hair..black-hair"
    DataDungeon::TraitKey.prefix("hero", traits, values, 3, labels).should eq "hero.human.tan-skin.long-hair."
  end

  it "normalizes a set: members normalized, deduplicated, sorted" do
    DataDungeon::TraitKey.normalize_set("Troll dead, trapdoor open").should eq "trapdoor-open,troll-dead"
    DataDungeon::TraitKey.normalize_set("sword, Lantern,  sword").should eq "lantern,sword"
    DataDungeon::TraitKey.normalize_set("lantern").should eq "lantern"
    DataDungeon::TraitKey.normalize_set(" , ,").should be_nil
  end

  it "normalizes values for matching, never leaving a separator in them" do
    DataDungeon::TraitKey.normalize("  Giant\t APE ").should eq "giant-ape"
    DataDungeon::TraitKey.normalize("St. Bernard").should eq "st-bernard"
    DataDungeon::TraitKey.normalize("red, gold").should eq "red-gold"
    DataDungeon::TraitKey.normalize("Straße").should eq "strasse"
    DataDungeon::TraitKey.normalize("e\u0301lan").should eq "élan" # composed form
    DataDungeon::TraitKey.normalize(" ., ").should be_nil
    DataDungeon::TraitKey.normalize("Zork III: The Dungeon Master").should eq "zork-iii-the-dungeon-master"
    DataDungeon::TraitKey.normalize("Zork III \u2013 The Dungeon Master").should eq "zork-iii-the-dungeon-master"
    DataDungeon::TraitKey.normalize("Dragon's Lair").should eq "dragons-lair"
    DataDungeon::TraitKey.normalize("Dragon\u2019s Lair").should eq "dragons-lair"
    DataDungeon::TraitKey.normalize("#FF0000").should eq "ff0000"
    DataDungeon::TraitKey.normalize("so_very!").should eq "so-very"
    DataDungeon::TraitKey.normalize("東京 タワー").should eq "東京-タワー"
    DataDungeon::TraitKey.normalize("!?!").should be_nil
  end
end

describe "DataDungeon::DB type registry" do
  it "rejects malformed registrations" do
    with_db("dd-reg-invalid") do |db|
      expect_raises(ArgumentError, /must not be empty/) { db.register_type("t", pool_traits: [] of String) }
      expect_raises(ArgumentError, /lowercase/) { db.register_type("t", pool_traits: %w[Hair]) }
      expect_raises(ArgumentError, /lowercase/) { db.register_type("t", pool_traits: %w[hair-]) }
      expect_raises(ArgumentError, /lowercase/) { db.register_type("t", pool_traits: %w[hair--color]) }
      expect_raises(ArgumentError, /twice/) { db.register_type("t", pool_traits: %w[race race]) }
      expect_raises(ArgumentError, /asset type/) { db.register_type("hero.shot", pool_traits: %w[race]) }
      expect_raises(ArgumentError, /first pool traits/) do
        db.register_type("t", pool_traits: %w[race rating], group_traits: %w[rating])
      end
      expect_raises(ArgumentError, /not a pool trait/) { db.register_type("t", pool_traits: %w[race], labels: {"skin" => "skin"}) }
      expect_raises(ArgumentError, /lowercase words/) { db.register_type("t", pool_traits: %w[skin], labels: {"skin" => "Skin"}) }
      db.registration("t").should be_nil
    end
  end

  it "derives keys from normalized trait tags, in the registered order" do
    with_db("dd-reg-keys") do |db|
      register_portraits(db)
      rec = store_portrait(db, portrait(art_style: "Golden", race: " Human ").merge({"note" => "Keep As Is"}), "a")

      rec.key.should eq "portrait.golden.pg.f.human.red-hair." # facial_hair absent
      rec.key.should eq db.key_for("portrait", portrait)
      db.group_key_for("portrait", portrait).should eq "portrait.golden.pg.f."
      db.group_key_for("portrait", portrait, 4).should eq "portrait.golden.pg.f.human."
      db.load_tags(rec.id).should eq portrait.merge({"note" => "Keep As Is"}) # traits normalized, other tags not

      db.key_for("portrait", portrait(facial_hair: "Braided Beard")).should eq "portrait.golden.pg.f.human.red-hair.braided-beard"
      expect_raises(ArgumentError, /not traits/) { db.key_for("portrait", portrait.merge({"note" => "x"})) }
    end
  end

  it "rejects a custom flag on a tag the asset lacks, leaving no object" do
    with_db("dd-reg-explicit") do |db|
      register_portraits(db)
      expect_raises(ArgumentError, /no tag/) { store_portrait(db, portrait, "a", custom: %w[skin]) }
      db.storage.not_nil!.list_keys.should be_empty
    end
  end

  it "pools interchangeable assets and finds them by traits or by key" do
    with_db("dd-reg-pool") do |db|
      register_portraits(db)
      a = store_portrait(db, portrait, "a")
      b = store_portrait(db, portrait(hair_color: "Red"), "b")
      other = store_portrait(db, portrait(hair_color: "blue"), "c")

      a.id.should_not eq b.id
      db.find_pool("portrait", portrait).map(&.id).should eq [a.id, b.id]
      db.find_pool(a.key.not_nil!).map(&.id).should eq [a.id, b.id] # the key alone
      db.find_pool("portrait", portrait(hair_color: "blue")).map(&.id).should eq [other.id]
    end
  end

  it "finds a group by its leading traits, at any depth, without matching part of a value" do
    with_db("dd-reg-prefix") do |db|
      register_portraits(db)
      human = store_portrait(db, portrait, "a")
      elf = store_portrait(db, portrait(race: "elf"), "b")
      store_portrait(db, portrait(gender: "fem"), "c") # "f" must not match "fem"
      store_portrait(db, portrait(rating: "r"), "d")

      db.find_group("portrait", portrait).map(&.id).should eq [human.id, elf.id]
      db.find_group("portrait", portrait, 4).map(&.id).should eq [human.id]
      db.find_group("portrait.golden.pg.f.").map(&.id).should eq [human.id, elf.id]
      db.find_group("portrait", portrait, 0).size.should eq 4 # the whole type
      expect_raises(ArgumentError, /must end with/) { db.find_group("portrait.golden.pg.f") }
    end
  end

  it "keeps types apart by the key alone" do
    with_db("dd-reg-types") do |db|
      db.register_type("portrait", pool_traits: %w[art_style rating])
      db.register_type("tile", pool_traits: %w[art_style rating])
      traits = {"art_style" => "golden", "rating" => "pg"}
      portrait = db.store("portrait", traits, bytes: "a".to_slice, content_type: "image/webp")
      tile = db.store("tile", traits, bytes: "b".to_slice, content_type: "image/webp")

      portrait.key.should eq "portrait.golden.pg"
      tile.key.should eq "tile.golden.pg"
      db.find_pool("portrait.golden.pg").map(&.id).should eq [portrait.id]
      db.find_group("tile.golden.").map(&.id).should eq [tile.id]
    end
  end

  it "keys room pictures by state and items, finding a set seen before in any order" do
    with_db("dd-reg-sets") do |db|
      db.register_type("room", pool_traits: %w[room art_style rating state items],
        group_traits: %w[room art_style rating], labels: {"room" => "room"},
        sets: %w[state items])
      scene = ->(state : String?, items : String?) do
        traits = {"room" => "17", "art_style" => "golden", "rating" => "pg"}
        traits["state"] = state if state
        traits["items"] = items if items
        traits
      end
      bare = db.store("room", scene.call("troll dead", nil), bytes: "a".to_slice, content_type: "image/webp")
      lantern = db.store("room", scene.call("troll dead", "Lantern"), bytes: "b".to_slice, content_type: "image/webp")
      both = db.store("room", scene.call("Troll dead", "sword, lantern"), bytes: "c".to_slice, content_type: "image/webp")
      alive = db.store("room", scene.call("troll alive", "lantern"), bytes: "d".to_slice, content_type: "image/webp")

      bare.key.should eq "room.17-room.golden.pg.troll-dead."
      lantern.key.should eq "room.17-room.golden.pg.troll-dead.lantern"
      both.key.should eq "room.17-room.golden.pg.troll-dead.lantern,sword"
      db.load_tags(both.id)["items"].should eq "lantern,sword"

      # Picking things up and dropping them again finds what was drawn before.
      db.find_pool("room", scene.call("troll dead", nil)).map(&.id).should eq [bare.id]
      db.find_pool("room", scene.call("troll dead", "LANTERN, Sword")).map(&.id).should eq [both.id]
      db.find_pool("room", scene.call("troll dead", "sword")).should be_empty # never drawn

      # This room in this state, whatever is lying around.
      db.find_group("room", scene.call("troll dead", nil), 4).map(&.id).should eq [bare.id, lantern.id, both.id]
      db.find_pool("room", scene.call("troll dead", "sword"), custom: %w[items]).map(&.id)
        .should eq [bare.id, lantern.id, both.id]
      db.find_assets_by_tags("room", {"items" => "sword,lantern"}).map(&.id).should eq [both.id]
      db.find_group("room", scene.call(nil, nil)).map(&.id).should eq [bare.id, lantern.id, both.id, alive.id]
    end
  end

  it "rejects malformed sets and keeps them across reopening" do
    with_db("dd-reg-sets-invalid") do |db, dir|
      expect_raises(ArgumentError, /not a pool trait/) { db.register_type("t", pool_traits: %w[room], sets: %w[items]) }
      expect_raises(ArgumentError, /can't be labelled/) do
        db.register_type("t", pool_traits: %w[items], labels: {"items" => "item"}, sets: %w[items])
      end
      db.register_type("room", pool_traits: %w[room items], sets: %w[items])
      db.close
      reopened = open_db(dir)
      begin
        reopened.registration("room").not_nil!.sets.should eq %w[items]
        reopened.store("room", {"room" => "1", "items" => "b, a"}, bytes: "x".to_slice, content_type: "image/webp")
          .key.should eq "room.1.a,b"
      ensure
        reopened.close
      end
    end
  end

  it "validates facets and keeps them across reopening" do
    with_db("dd-reg-facets") do |db, dir|
      expect_raises(ArgumentError, /lowercase words/) { db.register_type("t", pool_traits: %w[race], facets: {"Hair" => %w[race]}) }
      expect_raises(ArgumentError, /names no tags/) { db.register_type("t", pool_traits: %w[race], facets: {"hair" => [] of String}) }
      expect_raises(ArgumentError, /twice/) { db.register_type("t", pool_traits: %w[race], facets: {"hair" => %w[race race]}) }
      db.register_type("hero", pool_traits: %w[race], facets: {"identity" => %w[race skin description]})
      db.close
      reopened = open_db(dir)
      begin
        reopened.registration("hero").not_nil!.facets.should eq({"identity" => %w[race skin description]})
      ensure
        reopened.close
      end
    end
  end

  it "keeps every take of a key and gets the newest" do
    with_db("dd-reg-takes") do |db|
      db.register_type("voice", pool_traits: %w[bit beat voice])
      tags = {"bit" => "b1", "beat" => "0", "voice" => "fable"}
      first = db.store("voice", tags, bytes: "v1".to_slice, content_type: "audio/mpeg")
      second = db.store("voice", tags.merge({"voice" => "Fable"}), bytes: "v2".to_slice, content_type: "audio/mpeg")

      second.id.should_not eq first.id
      second.key.should eq first.key
      db.find_pool("voice", tags).map(&.id).should eq [first.id, second.id]
      got = db.get("voice", tags, touch: false).not_nil!
      File.read(db.path_for(got)).should eq "v2"
      db.get_with_meta("voice", tags, touch: false).not_nil![0].id.should eq second.id
      db.get(first.key.not_nil!, touch: false).not_nil!.id.should eq second.id # the key alone
      db.get_with_meta(first.key.not_nil!, touch: false).not_nil![0].id.should eq second.id
    end
  end

  it "finds by prefix at a labelled trait without matching part of a value" do
    with_db("dd-reg-labelled") do |db|
      db.register_type("hero", pool_traits: %w[race hair_length hair_texture hair_color], group_traits: %w[race],
        labels: {"hair_length" => "hair", "hair_texture" => "hair", "hair_color" => "hair"})
      hero = {"race" => "human", "hair_length" => "long", "hair_texture" => "straight", "hair_color" => "black"}
      long = db.store("hero", hero, bytes: "a".to_slice, content_type: "image/webp")
      curly = db.store("hero", hero.merge({"hair_texture" => "curly"}), bytes: "b".to_slice, content_type: "image/webp")
      db.store("hero", hero.merge({"hair_length" => "longer"}), bytes: "c".to_slice, content_type: "image/webp")

      long.key.should eq "hero.human.long-hair.straight-hair.black-hair"
      db.find_group("hero", hero, 2).map(&.id).should eq [long.id, curly.id] # "long" never matches "longer"
      db.find_group("hero.human.long-hair.").map(&.id).should eq [long.id, curly.id]
      db.find_pool("hero", hero, custom: %w[hair_texture]).map(&.id).should eq [long.id, curly.id]
    end
  end

  it "keys custom values like any other, counts them, and promotes them" do
    with_db("dd-reg-custom") do |db|
      register_portraits(db)
      a = store_portrait(db, portrait(race: "Ape"), "a", custom: %w[race])
      b = store_portrait(db, portrait(race: "ape"), "b", custom: %w[race])
      store_portrait(db, portrait(race: "lizard"), "c", custom: %w[race])

      db.custom_traits(a.id).should eq %w[race]
      db.find_pool("portrait", portrait(race: "ape")).map(&.id).should eq [a.id, b.id]
      db.custom_values("portrait", "race").should eq({"ape" => 2, "lizard" => 1})

      db.promote("portrait", "race", "APE").should eq 2
      db.custom_traits(a.id).should be_empty
      db.custom_values("portrait", "race").should eq({"lizard" => 1})
      db.find_asset_by_id(a.id).not_nil!.key.should eq a.key # promotion changes no key
    end
  end

  it "finds the pool with custom traits free, the group, or both" do
    with_db("dd-reg-group") do |db|
      register_portraits(db)
      human = store_portrait(db, portrait, "a")
      ape = store_portrait(db, portrait(race: "ape"), "b", custom: %w[race])
      blue = store_portrait(db, portrait(hair_color: "blue"), "c")    # other hair
      male = store_portrait(db, portrait(gender: "m"), "d")           # other group
      beard = store_portrait(db, portrait(facial_hair: "beard"), "e") # has a trait the request lacks

      request = portrait(race: "gorilla")
      db.find_pool("portrait", request).should be_empty # race must match too
      db.find_pool("portrait", request, custom: %w[race]).map(&.id).should eq [human.id, ape.id]
      db.find_group("portrait", request).map(&.id).should eq [human.id, ape.id, blue.id, beard.id]

      found = db.find("portrait", request, custom: %w[race])
      found.pool.map(&.id).should eq [human.id, ape.id]
      found.group.map(&.id).should eq [blue.id, beard.id]
      found.all.map(&.id).should eq [human.id, ape.id, blue.id, beard.id]

      # A custom trait inside the group narrows by the traits before it.
      db.find_pool("portrait", portrait, custom: %w[gender]).map(&.id).should eq [human.id, male.id]
    end
  end

  it "finds without a group for a type that has none" do
    with_db("dd-reg-nogroup") do |db|
      db.register_type("voice", pool_traits: %w[bit voice])
      rec = db.store("voice", {"bit" => "b1", "voice" => "fable"}, bytes: "v".to_slice, content_type: "audio/mpeg")
      found = db.find("voice", {"bit" => "b1", "voice" => "fable"})
      found.pool.map(&.id).should eq [rec.id]
      found.group.should be_empty
      expect_raises(ArgumentError, /no group traits/) { db.find_group("voice", {"bit" => "b1"}) }
      db.find_group("voice", {"bit" => "b1"}, 1).map(&.id).should eq [rec.id]
    end
  end

  it "re-derives keys and normalizes tags when a type is registered or changes" do
    with_db("dd-reg-rekey") do |db|
      # Stored before 0.12, unregistered.
      old = db.find_asset_by_id(store_legacy(db, "portrait", portrait(art_style: "Golden"))).not_nil!
      old.key.should be_nil

      register_portraits(db)
      rekeyed = db.find_asset_by_id(old.id).not_nil!
      rekeyed.key.should eq "portrait.golden.pg.f.human.red-hair."
      db.load_tags(old.id)["art_style"].should eq "golden"

      # Same definition again: nothing changes.
      register_portraits(db)
      db.find_asset_by_id(old.id).not_nil!.key.should eq rekeyed.key

      # A new label is a new definition.
      db.register_type("portrait", pool_traits: PORTRAIT_TRAITS, group_traits: PORTRAIT_GROUP,
        labels: {"hair_color" => "hair-color"}, rekey: true)
      db.find_asset_by_id(old.id).not_nil!.key.should eq "portrait.golden.pg.f.human.red-hair-color."

      # Fewer traits in another order: keys follow the new definition.
      db.register_type("portrait", pool_traits: %w[race art_style rating], group_traits: %w[race],
        rekey: true)
      db.find_asset_by_id(old.id).not_nil!.key.should eq "portrait.human.golden.pg"
    end
  end

  it "refuses to change a registration unless asked to re-key" do
    with_db("dd-reg-guard") do |db|
      register_portraits(db)
      rec = store_portrait(db, portrait, "a")
      register_portraits(db) # the same definition: nothing to do

      expect_raises(ArgumentError, /registered differently.*rekey: true/) do
        db.register_type("portrait", pool_traits: %w[race art_style])
      end
      db.registration("portrait").not_nil!.pool_traits.should eq PORTRAIT_TRAITS
      db.find_asset_by_id(rec.id).not_nil!.key.should eq rec.key

      db.register_type("portrait", pool_traits: %w[race art_style], rekey: true)
      db.find_asset_by_id(rec.id).not_nil!.key.should eq "portrait.human.golden"

      # What keys don't hold changes without re-keying.
      db.register_type("portrait", pool_traits: %w[race art_style], scales: {"race" => %w[elf human orc]}, weights: {"race" => 2.0})
      db.registration("portrait").not_nil!.weights.should eq({"race" => 2.0})
      db.find_asset_by_id(rec.id).not_nil!.key.should eq "portrait.human.golden"
    end
  end

  it "gives assets the same key when a registration makes theirs equal" do
    with_db("dd-reg-collide") do |db|
      tags = {"bit" => "b1", "voice" => "fable"}
      older = store_legacy(db, "voice", tags, "2026-01-01 00:00:00")
      newer = store_legacy(db, "voice", tags.merge({"voice" => "FABLE"}), "2026-06-01 00:00:00")

      db.register_type("voice", pool_traits: %w[bit voice])
      db.find_asset(db.key_for("voice", tags)).not_nil!.id.should eq newer # no object to serve, so not get
      db.find_asset_by_id(older).not_nil!.key.should eq "voice.b1.fable"
      db.find_pool("voice", tags).map(&.id).should eq [older, newer]
      db.load_tags(older).should eq tags
    end
  end

  it "keeps registrations across reopening and re-keys an older key format" do
    with_db("dd-reg-persist") do |db, dir|
      register_portraits(db)
      rec = store_portrait(db, portrait, "a")
      db.close

      reopened = open_db(dir)
      begin
        reopened.registration("portrait").not_nil!.pool_traits.should eq PORTRAIT_TRAITS
        store_portrait(reopened, portrait, "b").key.should eq rec.key

        # Simulate keys written in an older format.
        reopened.connection.exec("UPDATE asset_keys SET key = 'stale'")
        reopened.connection.exec("UPDATE asset_types SET key_scheme = 0")
      ensure
        reopened.close
      end

      db = open_db(dir)
      db.find_asset_by_id(rec.id).not_nil!.key.should eq rec.key
    end
  end

  it "normalizes tag filters for registered traits" do
    with_db("dd-reg-filters") do |db|
      register_portraits(db)
      rec = store_portrait(db, portrait, "a")
      db.find_assets_by_tags("portrait", {"race" => "HUMAN"}).map(&.id).should eq [rec.id]
      db.count_pool_assets("portrait", {"art_style" => " Golden"}).should eq 1
    end
  end

  it "takes dashes in trait names, keyed and embedded like underscores" do
    with_db("dd-reg-dashes") do |db|
      db.register_type("portrait", pool_traits: %w[art-style hair_color], labels: {"hair_color" => "hair"},
        facets: {"look" => %w[art-style]})
      rec = db.store("portrait", {"art-style" => "Golden", "hair_color" => "red"}, bytes: "a".to_slice,
        content_type: "image/webp")
      rec.key.should eq "portrait.golden.red-hair"
      db.load_tags(rec.id)["art-style"].should eq "golden"
    end
  end

  it "renames a tag on a type's assets and in its registration, keeping keys" do
    with_db("dd-reg-rename-tag") do |db, dir|
      register_portraits(db)
      a = store_portrait(db, portrait, "a")
      b = store_portrait(db, portrait(hair_color: "black"), "b")
      db.register_type("venue", pool_traits: %w[art_style])
      db.store("venue", {"art_style" => "golden"}, bytes: "v".to_slice, content_type: "image/webp")

      db.rename_tag("portrait", "hair_color", "hair-color").should eq 2
      db.rename_tag("portrait", "art_style", "art-style").should eq 2

      type = db.registration("portrait").not_nil!
      type.pool_traits.should eq %w[art-style rating gender race hair-color facial_hair]
      type.group_traits.should eq %w[art-style rating gender]
      type.labels.should eq({"hair-color" => "hair"})
      db.find_asset_by_id(a.id).not_nil!.key.should eq a.key
      db.load_tags(b.id)["hair-color"].should eq "black"
      dashed = portrait(hair_color: "black").transform_keys(&.tr("_", "-"))
      db.find_pool("portrait", dashed).map(&.id).should eq [b.id]
      db.find_assets_by_tags("venue", {"art_style" => "golden"}).size.should eq 1 # other types untouched
      db.close

      reopened = open_db(dir)
      begin
        reopened.registration("portrait").not_nil!.pool_traits.first.should eq "art-style"
        reopened.find_pool("portrait", dashed).map(&.id).should eq [b.id]
      ensure
        reopened.close
      end
    end
  end

  it "fixes keys when a type is registered under the new trait name before the rename" do
    with_db("dd-reg-rename-late") do |db|
      db.register_type("backdrop", pool_traits: %w[art_style rating])
      rec = db.store("backdrop", {"art_style" => "golden", "rating" => "pg"}, bytes: "b".to_slice,
        content_type: "image/webp")
      db.register_type("backdrop", pool_traits: %w[art-style rating], rekey: true)
      db.find_asset_by_id(rec.id).not_nil!.key.should eq "backdrop..pg" # its tag isn't art-style yet

      db.rename_tag("backdrop", "art_style", "art-style").should eq 1
      db.find_asset_by_id(rec.id).not_nil!.key.should eq "backdrop.golden.pg"
    end
  end

  it "refuses a tag rename onto a tag an asset already has, changing nothing" do
    with_db("dd-reg-rename-clash") do |db|
      db.register_type("venue", pool_traits: %w[style])
      rec = db.store("venue", {"style" => "golden", "art-style" => "silver"}, bytes: "v".to_slice,
        content_type: "image/webp")
      expect_raises(ArgumentError, /already have a art-style tag/) { db.rename_tag("venue", "style", "art-style") }
      db.load_tags(rec.id).should eq({"style" => "golden", "art-style" => "silver"})
    end
  end

  it "renames a type, re-deriving its keys under the new name" do
    with_db("dd-reg-rename-type") do |db, dir|
      db.register_type("banter_script", pool_traits: %w[character line])
      rec = db.store("banter_script", {"character" => "wizard", "line" => "1"}, bytes: "w".to_slice,
        content_type: "text/plain")

      db.rename_type("banter_script", "banter-script").should eq 1
      db.registration("banter_script").should be_nil
      moved = db.get("banter-script", {"character" => "wizard", "line" => "1"}, touch: false).not_nil!
      moved.id.should eq rec.id
      moved.key.should eq "banter-script.wizard.1"
      db.find_assets_by_tags("banter-script", {"character" => "wizard"}).map(&.id).should eq [rec.id]
      db.close

      reopened = open_db(dir)
      begin
        reopened.registration("banter-script").not_nil!.pool_traits.should eq %w[character line]
        reopened.registration("banter_script").should be_nil
      ensure
        reopened.close
      end
    end
  end

  it "merges a renamed type into an existing one, under that one's registration" do
    with_db("dd-reg-merge-type") do |db|
      db.register_type("backdrop", pool_traits: %w[art-style rating])
      db.register_type("room", pool_traits: %w[game room art-style rating])
      seed = db.store("backdrop", {"art-style" => "golden", "rating" => "pg"}, bytes: "s".to_slice,
        content_type: "image/webp")
      room = db.store("room", {"game" => "zork1", "room" => "west-of-house", "art-style" => "golden",
                               "rating" => "pg"}, bytes: "r".to_slice, content_type: "image/webp")
      store_legacy(db, "background", {"art-style" => "golden", "rating" => "pg"}) # unregistered

      db.rename_type("room", "backdrop").should eq 1
      db.rename_type("background", "backdrop").should eq 1
      db.registration("room").should be_nil
      db.registration("backdrop").not_nil!.pool_traits.should eq %w[art-style rating]
      pool = db.find_pool("backdrop", {"art-style" => "golden", "rating" => "pg"})
      pool.size.should eq 3
      pool.map(&.key).uniq.should eq ["backdrop.golden.pg"]
      db.load_tags(room.id)["room"].should eq "west-of-house" # extra tags stay
      pool.map(&.id).should contain seed.id
    end
  end

  it "renames an unregistered type's assets, stored before 0.12" do
    with_db("dd-reg-rename-plain") do |db|
      id = store_legacy(db, "hero_shot", {"style" => "golden"})
      db.rename_type("hero_shot", "heroshot").should eq 1
      db.find_assets_by_tags("heroshot", {"style" => "golden"}).map(&.id).should eq [id]
      db.find_asset_by_id(id).not_nil!.key.should be_nil
      expect_raises(ArgumentError, /asset type/) { db.rename_type("heroshot", "hero.shot") }
    end
  end
end
