require "spec"
require "file_utils"
require "../src/data_dungeon"

private def with_db(name : String, consumer : String? = "overlore", &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"), consumer: consumer)
  db.register_type("panel", pool_traits: %w[art-style])
  db.register_type("line", pool_traits: %w[voice])
  yield db, dir
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

private def store_panel(db, bytes : String, recipe : DataDungeon::Recipe? = nil, description : String? = nil,
                        generation : String? = nil) : DataDungeon::AssetRecord
  db.store("panel", {"art-style" => "silver-comic"}, bytes: bytes.to_slice, content_type: "image/webp",
    image: DataDungeon::ImageMeta.new(compression: "original"), recipe: recipe, description: description,
    generation: generation)
end

# DataDungeon's words for silver-comic, as the vocabulary seeds them.
SILVER = DataDungeon::Recipe.named("datadungeon:silver-comic@1", "Silver Age comic.")

private def picture(subject : String, flavor : String = "Silver Age comic art.", sent : String? = nil,
                    settings = {"camera" => "mj:camera:flare", "model" => "flux-dev", "steps" => 4}) : DataDungeon::Recipe
  DataDungeon::Recipe.new("picture", settings: settings,
    fields: {"framing" => DataDungeon::Recipe.named("overlore:house", "Draw one panel."),
             "style"   => SILVER,
             "flavor"  => DataDungeon::Recipe.named("overlore:silver-comic", flavor),
             "subject" => DataDungeon::Recipe.text(subject)},
    prompt_sent: sent, seed: 7, cost: 0.04, generated_at: Time.utc(2026, 10, 13, 9, 30),
    references: ["a" * 64])
end

# A picture as 0.13 made it, in its field order: the app's wording in style.
private def old_picture(subject : String, style : String = "Silver Age comic art.", sent : String? = nil) : DataDungeon::Recipe
  DataDungeon::Recipe.new("picture",
    fields: {"framing" => DataDungeon::Recipe.named("overlore:house", "Draw one panel."),
             "subject" => DataDungeon::Recipe.text(subject),
             "style"   => DataDungeon::Recipe.named("overlore:silver", style)},
    prompt_sent: sent, order: 1)
end

private def count(db, table : String) : Int64
  db.connection.scalar("SELECT COUNT(*) FROM #{table}").as(Int64)
end

# Turns a closed store's recipes back into 0.13's: no field order, framing
# called preamble, and no vocabulary (nor DataDungeon's style words).
private def as_013(path : String) : Nil
  raw = ::DB.open("sqlite3://#{path}")
  raw.exec("ALTER TABLE recipes DROP COLUMN field_order")
  raw.exec("UPDATE recipe_fields SET field = 'preamble' WHERE field = 'framing'")
  raw.exec("UPDATE named_texts SET field = 'preamble' WHERE field = 'framing'")
  raw.exec("DROP TABLE vocabulary_values")
  raw.exec("DROP TABLE vocabulary_tags")
  raw.exec("DELETE FROM named_texts WHERE owner = 'datadungeon'") # none of these recipes uses them
  raw.close
end

describe DataDungeon::Recipe do
  it "stores a picture's recipe and reads it back, named texts with their versions" do
    with_db("dd-recipe") do |db|
      rec = store_panel(db, "a", picture("A tall elf with red braids."))
      rec.has_recipe?.should be_true

      got = db.recipe(rec.id).not_nil!
      got.form.should eq "picture"
      got.fields.keys.should eq %w[framing style flavor subject] # in joining order
      got.order.should eq 2
      got.fields["subject"].text.should eq "A tall elf with red braids."
      got.fields["subject"].name.should be_nil
      got.fields["style"].name.should eq "datadungeon:silver-comic@1"
      got.fields["flavor"].name.should eq "overlore:silver-comic@1"
      got.fields["framing"].name.should eq "overlore:house@1"
      got.settings.should eq({"camera" => "mj:camera:flare", "model" => "flux-dev", "steps" => 4})
      got.seed.should eq 7
      got.cost.should eq 0.04
      got.generated_at.should eq Time.utc(2026, 10, 13, 9, 30)
      got.references.should eq ["a" * 64]
      got.prompt_sent.should be_nil # none was given

      plain = store_panel(db, "b")
      plain.has_recipe?.should be_false
      db.recipe(plain.id).should be_nil
    end
  end

  it "keeps what a picture's provider was sent only when it differs from the fields joined" do
    with_db("dd-recipe-sent") do |db|
      joined = "Draw one panel. Silver Age comic. Silver Age comic art. A dwarf."
      same = store_panel(db, "a", picture("A dwarf.", sent: joined))
      other = store_panel(db, "b", picture("A dwarf.", sent: "#{joined} Wide shot."))

      db.recipe(same.id).not_nil!.joined.should eq joined
      db.recipe(same.id).not_nil!.prompt_sent.should eq joined
      db.recipe(other.id).not_nil!.prompt_sent.should eq "#{joined} Wide shot."
      db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = ?", joined).as(Int64).should eq 0
    end
  end

  it "numbers a name's wordings in the order first seen, and finds the assets using them" do
    with_db("dd-recipe-names") do |db|
      first = store_panel(db, "a", picture("A", flavor: "Silver Age comic art."))
      second = store_panel(db, "b", picture("B", flavor: "Silver Age comic art, heavy inks."))
      again = store_panel(db, "c", picture("C", flavor: "Silver Age comic art."))

      db.recipe(second.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic@2"
      db.recipe(again.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic@1"
      db.with_text("flavor", "overlore:silver-comic").should eq [first.id, second.id, again.id]
      db.with_text("flavor", "overlore:silver-comic@1").should eq [first.id, again.id]
      db.with_text("framing", "overlore:silver-comic").should be_empty # names belong to a field
      db.with_text("style", "datadungeon:silver-comic").should eq [first.id, second.id, again.id]
      db.named_texts("flavor", "overlore").should eq [{"silver-comic", 1, "Silver Age comic art."},
                                                      {"silver-comic", 2, "Silver Age comic art, heavy inks."}]
      expect_raises(ArgumentError, /version 1, not 2/) do
        store_panel(db, "d", DataDungeon::Recipe.new("picture",
          fields: {"style" => SILVER, "flavor" => DataDungeon::Recipe.named("overlore:silver-comic@2", "Silver Age comic art.")}))
      end
    end
  end

  it "files a style's wordings by purpose, each purpose numbering its own" do
    with_db("dd-recipe-purpose") do |db|
      styled = ->(subject : String, name : String, words : String) do
        DataDungeon::Recipe.new("picture", fields: {"subject" => DataDungeon::Recipe.text(subject), "style" => SILVER,
                                                    "flavor" => DataDungeon::Recipe.named(name, words)})
      end
      figure = store_panel(db, "a", styled.call("An elf.", "overlore:silver-comic/figure", "Silver Age comic art, one figure."))
      place = store_panel(db, "b", styled.call("A hall.", "overlore:silver-comic/place", "Silver Age comic art, a wide room."))
      inked = store_panel(db, "c", styled.call("A dwarf.", "overlore:silver-comic/figure", "Silver Age comic art, heavy inks."))
      bare = store_panel(db, "d", styled.call("A cat.", "overlore:silver-comic", "Silver Age comic art."))

      db.recipe(figure.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic/figure@1"
      db.recipe(place.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic/place@1"
      db.recipe(inked.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic/figure@2"
      db.recipe(bare.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic@1" # a purpose is optional

      db.with_text("flavor", "overlore:silver-comic").should eq [figure.id, place.id, inked.id, bare.id]
      db.with_text("flavor", "overlore:silver-comic/figure").should eq [figure.id, inked.id]
      db.with_text("flavor", "overlore:silver-comic/figure@2").should eq [inked.id]
      db.list_assets(texts: {"flavor" => "overlore:silver-comic/place"}).map(&.id).should eq [place.id]
      db.named_texts("flavor", "overlore").map { |(name, version, _)| {name, version} }.should eq [
        {"silver-comic", 1}, {"silver-comic/figure", 1}, {"silver-comic/figure", 2}, {"silver-comic/place", 1},
      ]
      expect_raises(ArgumentError, /version 2, not 1/) do
        store_panel(db, "e", styled.call("An orc.", "overlore:silver-comic/figure@1", "Silver Age comic art, heavy inks."))
      end
    end
  end

  it "lets any app use a named wording, and only its owner add one" do
    dir = File.tempname("dd-recipe-owner")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    overlore = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    overlore.register_type("panel", pool_traits: %w[art-style])
    store_panel(overlore, "a", picture("A"))
    overlore.close

    owl = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "owl")
    used = store_panel(owl, "b", picture("B")) # Overlore's wordings, as they are
    owl.recipe(used.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic@1"
    owl.recipe(used.id).not_nil!.fields["style"].name.should eq "datadungeon:silver-comic@1" # DataDungeon's, for every app
    expect_raises(ArgumentError, /overlore:silver-comic is overlore's/) do
      store_panel(owl, "c", picture("C", flavor: "Owl's own take on silver."))
    end
    expect_raises(ArgumentError, %r{overlore:silver-comic/figure is overlore's}) do
      store_panel(owl, "d", DataDungeon::Recipe.new("picture",
        fields: {"style" => SILVER, "flavor" => DataDungeon::Recipe.named("overlore:silver-comic/figure", "Owl's own figure.")}))
    end
    owl.find_assets_by_tags("panel", {"art-style" => "silver-comic"}).size.should eq 2 # the refused store left nothing
  ensure
    owl.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "stores each wording and each set of settings once" do
    with_db("dd-recipe-once") do |db|
      a = store_panel(db, "a", picture("A dwarf.", settings: {"steps" => 4, "model" => "flux-dev"}),
        description: "A dwarf.")
      store_panel(db, "b", picture("A dwarf.", settings: {"model" => "flux-dev", "steps" => 4}),
        description: "A dwarf.")

      count(db, "recipe_settings").should eq 1 # the keys' order doesn't matter
      db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = 'A dwarf.'").as(Int64).should eq 1
      db.find_asset_by_id(a.id).not_nil!.description.should eq "A dwarf." # the asset's and the recipe's, one row
    end
  end

  it "stores speech and chat text, and a recipe made in steps" do
    with_db("dd-recipe-forms") do |db|
      speech = DataDungeon::Recipe.new("speech", settings: {"model" => "gpt-4o-mini-tts", "voice" => "fable"},
        fields: {"style" => DataDungeon::Recipe.named("overlore:veteran", "Gruff, tired."),
                 "text"  => DataDungeon::Recipe.text("Sit down, bard.")}, cost: 0.001)
      line = db.store("line", {"voice" => "fable"}, bytes: "mp3".to_slice, content_type: "audio/mpeg", recipe: speech)
      db.recipe(line.id).not_nil!.fields.keys.should eq %w[style text]

      edit = picture("A rain-soaked street.")
      matte = DataDungeon::Recipe.new("", settings: {"tool" => "overlore:matte", "version" => 2},
        references: ["b" * 64, "c" * 64])
      layer = store_panel(db, "layer", DataDungeon::Recipe.in_steps([edit, matte]))
      got = db.recipe(layer.id).not_nil!
      got.steps.size.should eq 2
      got.steps[0].fields["subject"].text.should eq "A rain-soaked street."
      got.steps[1].form.should eq ""
      got.steps[1].references.should eq ["b" * 64, "c" * 64]
    end
  end

  it "refuses a recipe that isn't in the standard shape, before storing anything" do
    with_db("dd-recipe-check") do |db|
      bad = [
        DataDungeon::Recipe.new("picture", fields: {"mood" => DataDungeon::Recipe.text("Grim.")}),
        DataDungeon::Recipe.new("painting"),
        DataDungeon::Recipe.new("picture", fields: {"subject" => DataDungeon::Recipe.text("")}),
        DataDungeon::Recipe.new("picture", references: ["not-a-hash"]),
        DataDungeon::Recipe.new("", fields: {"subject" => DataDungeon::Recipe.text("A.")}),
        DataDungeon::Recipe.new("picture", fields: {"flavor" => DataDungeon::Recipe.named("silver", "A.")}),
        DataDungeon::Recipe.new("picture", fields: {"flavor" => DataDungeon::Recipe.named("overlore:silver-comic/", "A.")}),
        DataDungeon::Recipe.new("picture", fields: {"flavor" => DataDungeon::Recipe.named("overlore:silver-comic/Figure", "A.")}),
        DataDungeon::Recipe.new("picture", fields: {"flavor" => DataDungeon::Recipe.named("overlore:silver-comic/a/b", "A.")}),
        DataDungeon::Recipe.new("picture", fields: {"preamble" => DataDungeon::Recipe.text("Draw one panel.")}),
        DataDungeon::Recipe.new("picture", fields: {"subject" => DataDungeon::Recipe.text("A.")}, order: 3),
      ]
      bad.each do |recipe|
        expect_raises(ArgumentError) { store_panel(db, "a", recipe) }
      end
      count(db, "assets").should eq 0
      Dir.glob(File.join(db.storage.not_nil!.as(DataDungeon::LocalStorage).root, "**", "*.webp")).should be_empty
    end
  end

  it "gives an asset a recipe, keeping its old record and any recipe unless told otherwise" do
    with_db("dd-recipe-set") do |db|
      old = store_panel(db, "a", generation: %({"prompt":"an elf"}))
      dropped = store_panel(db, "b", generation: %({"prompt":"a dwarf"}))
      old.generation.should eq %({"prompt":"an elf"})

      db.set_recipe(old.id, picture("An elf."))
      db.set_recipe(dropped.id, picture("A dwarf."), drop_generation: true)
      db.find_asset_by_id(old.id).not_nil!.generation.should eq %({"prompt":"an elf"}) # kept
      db.find_asset_by_id(dropped.id).not_nil!.generation.should be_nil
      db.recipe(old.id).not_nil!.fields["subject"].text.should eq "An elf."

      expect_raises(ArgumentError, /has a recipe; pass replace: true/) do
        db.set_recipe(old.id, picture("An old elf."))
      end
      db.recipe(old.id).not_nil!.fields["subject"].text.should eq "An elf." # untouched
      db.set_recipe(old.id, picture("An old elf."), replace: true)
      db.recipe(old.id).not_nil!.fields["subject"].text.should eq "An old elf."
      count(db, "recipes").should eq 2
      expect_raises(ArgumentError, /No asset/) { db.set_recipe(999, picture("X")) }
    end
  end

  it "won't let a text an asset or a recipe uses be deleted" do
    with_db("dd-recipe-keep") do |db, dir|
      store_panel(db, "a", picture("A dwarf."), description: "A small room.")
      raw = ::DB.open("sqlite3://#{File.join(dir, "assets.db")}?foreign_keys=on")
      ["A small room.", "A dwarf.", "Silver Age comic art."].each do |words|
        expect_raises(SQLite3::Exception, /FOREIGN KEY/) do
          raw.exec("DELETE FROM texts WHERE text = ?", words)
        end
      end
      # The driver reports a refused statement's error again when it
      # finalizes the cached statement.
      expect_raises(SQLite3::Exception, /FOREIGN KEY/) { raw.close }
      db.find_assets_by_tags("panel", {"art-style" => "silver-comic"}).first.description.should eq "A small room."
    end
  end

  it "moves a 0.12 store's descriptions into texts and its generation records aside" do
    dir = File.tempname("dd-recipe-migrate")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"))
    db.register_type("panel", pool_traits: %w[art-style])
    a = store_panel(db, "a")
    b = store_panel(db, "b")
    db.close
    raw = ::DB.open("sqlite3://#{path}")
    raw.exec("ALTER TABLE assets ADD COLUMN generation TEXT")
    raw.exec("ALTER TABLE assets ADD COLUMN description TEXT")
    raw.exec("DROP INDEX idx_assets_description")
    raw.exec("ALTER TABLE assets DROP COLUMN description_id")
    raw.exec("UPDATE assets SET description = 'A room.', generation = ? WHERE id = ?", %({"prompt":"a room"}), a.id)
    raw.exec("UPDATE assets SET description = 'A room.' WHERE id = ?", b.id)
    raw.close

    expect_raises(DataDungeon::ReadOnlyError, /open it read-write once/) do
      DataDungeon::DB.new(path, read_only: true)
    end
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"))
    columns = db.connection.query_all("SELECT name FROM pragma_table_info('assets')", as: String)
    columns.should contain "description_id"
    columns.should_not contain "description"
    columns.should_not contain "generation"
    db.find_asset_by_id(a.id).not_nil!.description.should eq "A room."
    db.find_asset_by_id(a.id).not_nil!.generation.should eq %({"prompt":"a room"})
    db.find_asset_by_id(b.id).not_nil!.generation.should be_nil
    db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = 'A room.'").as(Int64).should eq 1
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "changes a description and marks an asset permanent" do
    with_db("dd-recipe-update") do |db|
      rec = store_panel(db, "a", description: "A room.")
      rec.permanent.should be_false
      updated = db.update_asset(rec.id, description: "A larger room.", permanent: true)
      updated.description.should eq "A larger room."
      updated.permanent.should be_true
      db.update_asset(rec.id, permanent: false).permanent.should be_false
    end
  end

  it "joins a picture's fields in its order: rules first, directives last" do
    with_db("dd-recipe-order") do |db|
      fields = {"directives" => "Keep the door as it is.", "light" => "Lit from the left.", "staging" => "Seen from the left.",
                "flavor" => "Bold inks.", "theme" => "Autumn.", "description" => "A long hall.", "subject" => "A dwarf.",
                "framing" => "A wide shot.", "rules" => "No text unless the description asks for it."}
      words = fields.transform_values { |text| DataDungeon::Recipe.text(text) }.merge({"style" => SILVER})
      sent = "No text unless the description asks for it. A wide shot. Silver Age comic. Bold inks. Autumn. A dwarf. " \
             "A long hall. Seen from the left. Lit from the left. Keep the door as it is."
      recipe = DataDungeon::Recipe.new("picture", fields: words, prompt_sent: sent)
      recipe.joined.should eq sent
      rec = store_panel(db, "a", recipe)
      got = db.recipe(rec.id).not_nil!
      got.fields.keys.should eq %w[rules framing style flavor theme subject description staging light directives]
      got.prompt_sent.should eq sent
      db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = ?", sent).as(Int64).should eq 0

      # A prompt made in 0.13's order is kept in it.
      old = {"rules" => "No text.", "staging" => "Seen from the left.", "style" => "Silver Age comic art.",
             "theme" => "Autumn.", "description" => "A long hall.", "subject" => "A dwarf.", "framing" => "Draw one panel."}
      then_sent = "Draw one panel. A dwarf. A long hall. Seen from the left. Autumn. Silver Age comic art. No text."
      converted = DataDungeon::Recipe.new("picture", fields: old.transform_values { |text| DataDungeon::Recipe.text(text) },
        prompt_sent: then_sent, order: 1)
      got = db.recipe(store_panel(db, "b", converted).id).not_nil!
      got.order.should eq 1
      got.fields.keys.should eq %w[framing subject description staging theme style rules]
      got.prompt_sent.should eq then_sent
      db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = ?", then_sent).as(Int64).should eq 0
    end
  end

  it "won't join a prompt that would leave out words it was given" do
    preamble = DataDungeon::Recipe.new("picture", fields: {"preamble" => DataDungeon::Recipe.text("Change only this:"),
                                                           "subject"  => DataDungeon::Recipe.text("A lamp.")})
    expect_raises(ArgumentError, /not preamble \(0.14 renamed preamble framing\)/) { preamble.joined }
    flavor = DataDungeon::Recipe.new("picture", fields: {"flavor" => DataDungeon::Recipe.text("Bold inks.")}, order: 1)
    expect_raises(ArgumentError, /not flavor/) { flavor.joined } # 0.13's order had none
    DataDungeon::Recipe.new("", references: ["a" * 64]).joined.should eq ""
  end

  it "takes a picture's style from the vocabulary, and the app's own words as its flavor" do
    with_db("dd-recipe-styles") do |db|
      db.style_text("silver-comic").should eq SILVER
      db.style_text("silver-comic").name.should eq "datadungeon:silver-comic@1"
      expect_raises(ArgumentError, /isn't a standard art style/) { db.style_text("silver") }

      styled = ->(style : DataDungeon::Recipe::Text?, flavor : DataDungeon::Recipe::Text?) do
        fields = {"subject" => DataDungeon::Recipe.text("A hall.")}
        style.try { |words| fields["style"] = words }
        flavor.try { |words| fields["flavor"] = words }
        DataDungeon::Recipe.new("picture", fields: fields)
      end
      place = DataDungeon::Recipe.named("overlore:silver-comic/place", "Bold inks, a wide room.")
      ok = store_panel(db, "a", styled.call(db.style_text("silver-comic"), place))
      store_panel(db, "b", styled.call(SILVER, DataDungeon::Recipe.text("Bold inks."))) # plain words are the app's
      store_panel(db, "c", styled.call(SILVER, nil))
      store_panel(db, "d", styled.call(nil, nil)) # a picture needn't have a style
      db.with_text("style", "datadungeon:silver-comic").size.should eq 3
      db.recipe(ok.id).not_nil!.fields.keys.should eq %w[style flavor subject]

      refused = [
        {styled.call(DataDungeon::Recipe.text("Silver Age comic."), nil), /DataDungeon's words/},
        {styled.call(DataDungeon::Recipe.named("overlore:silver-comic", "Silver Age comic."), nil), /DataDungeon's words/},
        {styled.call(DataDungeon::Recipe.named("datadungeon:silver-comic", "Silver age comics."), nil), /DataDungeon's words/},
        {styled.call(DataDungeon::Recipe.named("datadungeon:silver-comic@2", "Silver Age comic."), nil), /DataDungeon's words/},
        {styled.call(DataDungeon::Recipe.named("datadungeon:silver", "Silver Age comic."), nil), /DataDungeon's words/},
        {styled.call(nil, place), /a flavor adds to a style/},
        {styled.call(SILVER, DataDungeon::Recipe.named("overlore:golden-comic/place", "Bold inks.")), /is a flavor of golden-comic/},
      ]
      before = count(db, "assets")
      refused.each do |(recipe, message)|
        expect_raises(ArgumentError, message) { store_panel(db, "x", recipe) }
      end
      expect_raises(ArgumentError, /DataDungeon's words/) do
        db.set_recipe(ok.id, styled.call(DataDungeon::Recipe.text("Silver."), nil), replace: true)
      end
      count(db, "assets").should eq before
      db.recipe(ok.id).not_nil!.fields["flavor"].name.should eq "overlore:silver-comic/place@1" # untouched

      # 0.13's order had the app's wording in style, and isn't checked.
      store_panel(db, "e", old_picture("A cat.")).has_recipe?.should be_true
    end
  end

  it "seeds the shared vocabulary once, with each art style's words" do
    with_db("dd-recipe-vocabulary") do |db, dir|
      vocabulary = db.vocabulary
      vocabulary.map(&.name).should eq %w[art-style rating]
      vocabulary.map(&.title).should eq ["Art Style", "Rating"]
      styles = vocabulary[0].values
      styles.map(&.value).first(3).should eq %w[golden-comic silver-comic modern-comic]
      styles.size.should eq 14
      pixel = styles.find!(&.value.==("pixel-16"))
      pixel.title.should eq "16-Bit Pixel"
      pixel.family.should eq "pixel"
      styles.find!(&.value.==("silver-comic")).style.should eq SILVER
      rating = vocabulary[1]
      rating.kind.should eq "scale"
      rating.values.map(&.value).should eq %w[g pg r x]
      rating.values.all?(&.style.nil?).should be_true

      named = count(db, "named_texts")
      db.close
      db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"), consumer: "overlore")
      count(db, "named_texts").should eq named # nothing new on a second open
      db.style_text("silver-comic").name.should eq "datadungeon:silver-comic@1"
      read_only = DataDungeon::DB.new(File.join(dir, "assets.db"), read_only: true)
      read_only.vocabulary.size.should eq 2
      read_only.close
    end
  end

  it "keeps a 0.13 store's recipes in the order they were sent, renaming preamble framing" do
    dir = File.tempname("dd-recipe-order-migrate")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.register_type("panel", pool_traits: %w[art-style])
    joined = "Draw one panel. A dwarf. Silver Age comic art."
    same = store_panel(db, "a", old_picture("A dwarf.", sent: joined))
    other = store_panel(db, "b", old_picture("An elf.", sent: "An elf, drawn."))
    plain = store_panel(db, "c", old_picture("A cat."))
    before = [same, other, plain].map { |rec| db.recipe(rec.id).not_nil! }
    db.close
    as_013(path)

    expect_raises(DataDungeon::ReadOnlyError, /open it read-write once/) do
      DataDungeon::DB.new(path, read_only: true)
    end
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    [same, other, plain].zip(before).each do |(rec, was)|
      got = db.recipe(rec.id).not_nil!
      got.order.should eq 1
      got.prompt_sent.should eq was.prompt_sent
      got.fields.should eq was.fields
    end
    db.recipe(same.id).not_nil!.prompt_sent.should eq joined # rebuilt from its fields, as sent
    db.connection.scalar("SELECT COUNT(*) FROM recipe_fields WHERE field = 'preamble'").as(Int64).should eq 0
    db.with_text("framing", "overlore:house").should eq [same.id, other.id, plain.id]
    db.connection.query_all("PRAGMA foreign_key_check", &.read(::DB::Any)).should be_empty
    db.recipe(store_panel(db, "d", picture("An orc.")).id).not_nil!.order.should eq 2
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps a cost's basis, and a whole prompt whose parts are lost" do
    with_db("dd-recipe-cost") do |db|
      priced = DataDungeon::Recipe.new("picture", fields: {"subject" => DataDungeon::Recipe.text("A.")},
        cost: 0.04, cost_basis: "reported: runware")
      db.recipe(store_panel(db, "a", priced).id).not_nil!.cost_basis.should eq "reported: runware"
      expect_raises(ArgumentError, /no cost/) do
        store_panel(db, "b", DataDungeon::Recipe.new("picture", cost_basis: "estimated"))
      end

      # An old record: the settings and the whole prompt, not its parts.
      old = store_panel(db, "c")
      whole = "A misty valley at dawn. Style: painterly fantasy. No text, no watermark."
      db.set_recipe(old.id, DataDungeon::Recipe.new("picture", settings: {"steps" => 20}, prompt_sent: whole))
      got = db.recipe(old.id).not_nil!
      got.fields.should be_empty
      got.prompt_sent.should eq whole
      got.settings.should eq({"steps" => 20})
    end
  end

  it "clears a description, and changes a shared one here or everywhere" do
    with_db("dd-recipe-shared") do |db|
      a = store_panel(db, "a", description: "A room.")
      b = store_panel(db, "b", description: "A room.")
      c = store_panel(db, "c", description: "A room.")
      d = store_panel(db, "d", description: "A hall.")
      hash = Digest::SHA256.hexdigest("A room.")
      a.description_hash.should eq hash
      db.list_assets(description_hash: hash).map(&.id).should eq [c.id, b.id, a.id]
      db.count_assets(description_hash: hash).should eq 3

      db.update_asset(a.id, description: "A room!").description.should eq "A room!" # this one alone
      db.find_asset_by_id(b.id).not_nil!.description.should eq "A room."
      db.update_asset(b.id, description: "The room.", everywhere: true)
      [b, c].each { |rec| db.find_asset_by_id(rec.id).not_nil!.description.should eq "The room." }
      db.find_asset_by_id(a.id).not_nil!.description.should eq "A room!"
      db.find_asset_by_id(d.id).not_nil!.description.should eq "A hall."
      db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = 'A room.'").as(Int64).should eq 1 # kept

      cleared = db.update_asset(d.id, description: "")
      cleared.description.should be_nil
      cleared.description_hash.should be_nil
      store_panel(db, "e", description: "").description.should be_nil
      expect_raises(ArgumentError, /none was given/) { db.update_asset(a.id, everywhere: true) }
    end
  end

  it "gives a 0.13.0 store's named texts a purpose, keeping every recipe's names" do
    dir = File.tempname("dd-recipe-purpose-migrate")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.register_type("panel", pool_traits: %w[art-style])
    first = store_panel(db, "a", old_picture("A", style: "Silver Age comic art."))
    second = store_panel(db, "b", old_picture("B", style: "Silver Age comic art, heavy inks."))
    db.close
    as_013(path)
    raw = ::DB.open("sqlite3://#{path}") # named_texts as 0.13.0 made it
    raw.exec(<<-SQL)
      CREATE TABLE named_texts_old (
        id      INTEGER PRIMARY KEY,
        field   TEXT NOT NULL,
        owner   TEXT NOT NULL,
        name    TEXT NOT NULL,
        version INTEGER NOT NULL,
        text_id INTEGER NOT NULL REFERENCES texts(id),
        UNIQUE (field, owner, name, version),
        UNIQUE (field, owner, name, text_id)
      )
    SQL
    raw.exec("INSERT INTO named_texts_old SELECT id, field, owner, name, version, text_id FROM named_texts")
    raw.exec("DROP TABLE named_texts")
    raw.exec("ALTER TABLE named_texts_old RENAME TO named_texts")
    ids = raw.query_all("SELECT id FROM named_texts ORDER BY id", as: Int64)
    raw.close
    ids.size.should eq 3 # house@1, silver@1, silver@2

    expect_raises(DataDungeon::ReadOnlyError, /open it read-write once/) do
      DataDungeon::DB.new(path, read_only: true)
    end
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.connection.query_all("SELECT name FROM pragma_table_info('named_texts')", as: String).should contain "purpose"
    db.connection.query_all("SELECT id FROM named_texts WHERE owner = 'overlore' ORDER BY id", as: Int64).should eq ids
    db.connection.query_all("PRAGMA foreign_key_check", &.read(::DB::Any)).should be_empty
    db.recipe(second.id).not_nil!.fields["style"].name.should eq "overlore:silver@2"
    db.with_text("style", "overlore:silver@1").should eq [first.id]
    figure = store_panel(db, "c", DataDungeon::Recipe.new("picture", order: 1,
      fields: {"style" => DataDungeon::Recipe.named("overlore:silver/figure", "Silver Age comic art, heavy inks.")}))
    db.recipe(figure.id).not_nil!.fields["style"].name.should eq "overlore:silver/figure@1" # its own numbering
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "lists the assets with a file, or using a named text" do
    with_db("dd-recipe-list") do |db|
      first = store_panel(db, "a", picture("A", flavor: "Silver Age comic art."))
      second = store_panel(db, "b", picture("B", flavor: "Silver Age comic art, heavy inks."))
      plain = store_panel(db, "c")
      db.list_assets(file_hash: plain.file_hash).map(&.id).should eq [plain.id]
      db.list_assets(texts: {"flavor" => "overlore:silver-comic"}).map(&.id).should eq [second.id, first.id]
      db.list_assets("panel", texts: {"flavor" => "overlore:silver-comic@2"}).map(&.id).should eq [second.id]
      db.count_assets(texts: {"framing" => "overlore:house", "flavor" => "overlore:silver-comic@1"}).should eq 1
      expect_raises(ArgumentError, /owner:name/) { db.list_assets(texts: {"style" => "silver"}) }
    end
  end
end
