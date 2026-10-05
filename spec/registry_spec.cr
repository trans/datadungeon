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
  db.register_type("portrait", pool_traits: PORTRAIT_TRAITS, group_traits: PORTRAIT_GROUP, pool: true,
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

describe DataDungeon::TraitKey do
  it "joins trait values in order, with an empty segment for an absent trait" do
    traits = %w[art_style rating gender race]
    values = {"art_style" => "golden", "rating" => "pg", "gender" => "f", "race" => "human"}
    DataDungeon::TraitKey.key(traits, values).should eq "golden.pg.f.human"
    DataDungeon::TraitKey.key(traits, values.reject("rating")).should eq "golden..f.human"
    DataDungeon::TraitKey.prefix(traits, values, 2).should eq "golden.pg."
    DataDungeon::TraitKey.prefix(traits, values, 0).should eq ""
  end

  it "suffixes labelled traits so their values read unambiguously" do
    traits = %w[race skin hair_length hair_texture hair_color]
    values = {"race" => "human", "skin" => "tan", "hair_length" => "long", "hair_texture" => "straight", "hair_color" => "black"}
    labels = {"skin" => "skin", "hair_length" => "hair", "hair_texture" => "hair", "hair_color" => "hair"}
    DataDungeon::TraitKey.key(traits, values, labels).should eq "human.tan-skin.long-hair.straight-hair.black-hair"
    DataDungeon::TraitKey.key(traits, values.reject("hair_texture"), labels).should eq "human.tan-skin.long-hair..black-hair"
    DataDungeon::TraitKey.prefix(traits, values, 3, labels).should eq "human.tan-skin.long-hair."
  end

  it "normalizes values for matching, never leaving a separator in them" do
    DataDungeon::TraitKey.normalize("  Giant\t APE ").should eq "giant-ape"
    DataDungeon::TraitKey.normalize("St. Bernard").should eq "st-bernard"
    DataDungeon::TraitKey.normalize("red, gold").should eq "red-gold"
    DataDungeon::TraitKey.normalize("Straße").should eq "strasse"
    DataDungeon::TraitKey.normalize("e\u0301lan").should eq "élan" # composed form
    DataDungeon::TraitKey.normalize(" ., ").should be_nil
  end
end

describe "DataDungeon::DB type registry" do
  it "rejects malformed registrations" do
    with_db("dd-reg-invalid") do |db|
      expect_raises(ArgumentError, /must not be empty/) { db.register_type("t", pool_traits: [] of String) }
      expect_raises(ArgumentError, /lowercase/) { db.register_type("t", pool_traits: %w[Hair]) }
      expect_raises(ArgumentError, /twice/) { db.register_type("t", pool_traits: %w[race race]) }
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

      rec.pool_key.should eq "golden.pg.f.human.red-hair." # facial_hair absent
      rec.pool_key.should eq db.pool_key_for("portrait", portrait)
      db.group_key_for("portrait", portrait).should eq "golden.pg.f."
      db.group_key_for("portrait", portrait, 4).should eq "golden.pg.f.human."
      rec.pool.should be_true
      db.load_tags(rec.id).should eq portrait.merge({"note" => "Keep As Is"}) # traits normalized, other tags not

      db.pool_key_for("portrait", portrait(facial_hair: "Braided Beard")).should eq "golden.pg.f.human.red-hair.braided-beard"
      expect_raises(ArgumentError, /not traits/) { db.pool_key_for("portrait", portrait.merge({"note" => "x"})) }
    end
  end

  it "rejects an explicit key or pool flag for a registered type, leaving no object" do
    with_db("dd-reg-explicit") do |db|
      register_portraits(db)
      expect_raises(ArgumentError, /derives its pool_key/) do
        db.store("portrait", portrait, pool_key: "mine", bytes: "a".to_slice, content_type: "image/webp")
      end
      expect_raises(ArgumentError, /registration/) do
        db.store("portrait", portrait, pool: false, bytes: "a".to_slice, content_type: "image/webp")
      end
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
      db.find_pool("portrait", a.pool_key.not_nil!).map(&.id).should eq [a.id, b.id]
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
      db.find_group("portrait", "golden.pg.f.").map(&.id).should eq [human.id, elf.id]
      db.find_group("portrait", portrait, 0).size.should eq 4 # the whole type
      expect_raises(ArgumentError, /must end with/) { db.find_group("portrait", "golden.pg.f") }
    end
  end

  it "keeps one best asset per key for a single-best type" do
    with_db("dd-reg-single") do |db|
      db.register_type("voice", pool_traits: %w[bit beat voice])
      tags = {"bit" => "b1", "beat" => "0", "voice" => "fable"}
      first = db.store("voice", tags, bytes: "v1".to_slice, content_type: "audio/mpeg")
      second = db.store("voice", tags.merge({"voice" => "Fable"}), bytes: "v2".to_slice, content_type: "audio/mpeg")

      second.id.should eq first.id
      second.pool.should be_false
      got = db.get("voice", tags, touch: false).not_nil!
      File.read(db.path_for(got)).should eq "v2"
      db.get_with_meta("voice", tags, touch: false).not_nil![0].id.should eq first.id
    end
  end

  it "finds by prefix at a labelled trait without matching part of a value" do
    with_db("dd-reg-labelled") do |db|
      db.register_type("hero", pool_traits: %w[race hair_length hair_texture hair_color], group_traits: %w[race],
        labels: {"hair_length" => "hair", "hair_texture" => "hair", "hair_color" => "hair"}, pool: true)
      hero = {"race" => "human", "hair_length" => "long", "hair_texture" => "straight", "hair_color" => "black"}
      long = db.store("hero", hero, bytes: "a".to_slice, content_type: "image/webp")
      curly = db.store("hero", hero.merge({"hair_texture" => "curly"}), bytes: "b".to_slice, content_type: "image/webp")
      db.store("hero", hero.merge({"hair_length" => "longer"}), bytes: "c".to_slice, content_type: "image/webp")

      long.pool_key.should eq "human.long-hair.straight-hair.black-hair"
      db.find_group("hero", hero, 2).map(&.id).should eq [long.id, curly.id] # "long" never matches "longer"
      db.find_group("hero", "human.long-hair.").map(&.id).should eq [long.id, curly.id]
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
      db.find_asset_by_id(a.id).not_nil!.pool_key.should eq a.pool_key # promotion changes no key
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

  it "finds an unregistered pool by its explicit key" do
    with_db("dd-reg-explicit-pool") do |db|
      c = db.store("decree", {"quest" => "zork"}, pool_key: "zork", pool: true, bytes: "c".to_slice, content_type: "text/plain")
      d = db.store("decree", {"quest" => "zork"}, pool_key: "zork", pool: true, bytes: "d".to_slice, content_type: "text/plain")
      db.find_pool("decree", "zork").map(&.id).should eq [c.id, d.id]
      db.find_asset("decree", "zork").should be_nil # single-best lookup skips pools
    end
  end

  it "re-derives keys and normalizes tags when a type is registered or changes" do
    with_db("dd-reg-rekey") do |db|
      # Stored before registration, with an app-supplied key.
      old = db.store("portrait", portrait(art_style: "Golden"), pool_key: "legacy-key",
        bytes: "a".to_slice, content_type: "image/webp")

      register_portraits(db)
      rekeyed = db.find_asset_by_id(old.id).not_nil!
      rekeyed.pool_key.should eq "golden.pg.f.human.red-hair."
      rekeyed.pool.should be_true
      db.load_tags(old.id)["art_style"].should eq "golden"

      # Same definition again: nothing changes.
      register_portraits(db)
      db.find_asset_by_id(old.id).not_nil!.pool_key.should eq rekeyed.pool_key

      # A new label is a new definition.
      db.register_type("portrait", pool_traits: PORTRAIT_TRAITS, group_traits: PORTRAIT_GROUP, pool: true,
        labels: {"hair_color" => "hair-color"})
      db.find_asset_by_id(old.id).not_nil!.pool_key.should eq "golden.pg.f.human.red-hair-color."

      # Fewer traits in another order: keys follow the new definition.
      db.register_type("portrait", pool_traits: %w[race art_style rating], group_traits: %w[race], pool: true)
      db.find_asset_by_id(old.id).not_nil!.pool_key.should eq "human.golden.pg"
    end
  end

  it "lets the most recently used asset keep a key that now collides" do
    with_db("dd-reg-collide") do |db|
      tags = {"bit" => "b1", "voice" => "fable"}
      stale = db.store("voice", tags, pool_key: "k1", bytes: "1".to_slice, content_type: "audio/mpeg")
      fresh = db.store("voice", tags.merge({"voice" => "FABLE"}), pool_key: "k2", bytes: "2".to_slice, content_type: "audio/mpeg")
      db.connection.exec("UPDATE assets SET last_used_at = '2026-01-01 00:00:00' WHERE id = ?", stale.id)
      db.connection.exec("UPDATE assets SET last_used_at = '2026-06-01 00:00:00' WHERE id = ?", fresh.id)

      db.register_type("voice", pool_traits: %w[bit voice])
      db.get("voice", tags, touch: false).not_nil!.id.should eq fresh.id
      kept = db.find_asset_by_id(stale.id).not_nil!
      kept.pool_key.should be_nil # row and tags kept, key given up
      db.load_tags(stale.id).should eq tags
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
        store_portrait(reopened, portrait, "b").pool_key.should eq rec.pool_key

        # Simulate keys written in an older format.
        reopened.connection.exec("UPDATE assets SET pool_key = 'stale'")
        reopened.connection.exec("UPDATE asset_types SET key_scheme = 0")
      ensure
        reopened.close
      end

      db = open_db(dir)
      db.find_asset_by_id(rec.id).not_nil!.pool_key.should eq rec.pool_key
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
end
