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

private def wording(kind : String, name : String, words : String) : DataDungeon::Recipe::Wording
  DataDungeon::Recipe.wording(kind, name, words)
end

private def version(words : String) : String
  DataDungeon::Recipe.version(words)
end

# DataDungeon's words for silver-comic, as the vocabulary seeds them.
SILVER_WORDS = "Silver Age comic."
SILVER       = DataDungeon::Recipe.wording("style", "dd:silver-comic@#{DataDungeon::Recipe.version(SILVER_WORDS)}", SILVER_WORDS)

# A picture as an app sends it: its prompt, and the wordings in it.
private def picture(subject : String, flavor : String = "Silver Age comic art.",
                    settings = {"camera" => "mj:camera:flare", "model" => "flux-dev", "steps" => 4}) : DataDungeon::Recipe
  DataDungeon::Recipe.new("picture", settings: settings,
    prompt: "Draw one panel. #{SILVER_WORDS} #{flavor} #{subject}",
    wordings: [wording("framing", "overlore:house", "Draw one panel."), SILVER,
               wording("flavor", "overlore:silver-comic", flavor)],
    seed: 7, cost: 0.04, generated_at: Time.utc(2026, 10, 13, 9, 30), references: ["a" * 64])
end

private def flavored(subject : String, name : String, flavor : String) : DataDungeon::Recipe
  DataDungeon::Recipe.new("picture", prompt: "#{SILVER_WORDS} #{flavor} #{subject}",
    wordings: [SILVER, wording("flavor", name, flavor)])
end

private def count(db, table : String) : Int64
  db.connection.scalar("SELECT COUNT(*) FROM #{table}").as(Int64)
end

private def sha(words : String) : String
  Digest::SHA256.hexdigest(words)
end

# Turns a closed store's recipe tables back into 0.13.1's (or 0.13.0's,
# without purposes), empty, with no vocabulary, so a spec can write the
# rows 0.13 left.
private def as_013(raw : ::DB::Database, purposes : Bool = true) : Nil
  %w[named_texts_kept_update named_texts_kept_delete].each { |name| raw.exec("DROP TRIGGER #{name}") }
  %w[vocabulary_values vocabulary_tags recipe_wordings recipes named_texts].each { |table| raw.exec("DROP TABLE #{table}") }
  raw.exec(<<-SQL)
    CREATE TABLE named_texts (
      id      INTEGER PRIMARY KEY,
      field   TEXT NOT NULL,
      owner   TEXT NOT NULL,
      name    TEXT NOT NULL,
      #{purposes ? "purpose TEXT NOT NULL DEFAULT ''," : ""}
      version INTEGER NOT NULL,
      text_id INTEGER NOT NULL REFERENCES texts(id),
      UNIQUE (field, owner, name, #{purposes ? "purpose, " : ""}version),
      UNIQUE (field, owner, name, #{purposes ? "purpose, " : ""}text_id)
    )
  SQL
  raw.exec(<<-SQL)
    CREATE TABLE recipes (
      asset_id       INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
      step           INTEGER NOT NULL,
      form           TEXT NOT NULL,
      settings_id    INTEGER REFERENCES recipe_settings(id),
      seed           INTEGER,
      cost           REAL,
      cost_basis     TEXT,
      generated_at   TEXT,
      sent_as_joined INTEGER NOT NULL DEFAULT 0,
      prompt_sent_id INTEGER REFERENCES texts(id),
      refs           TEXT,
      PRIMARY KEY (asset_id, step)
    ) WITHOUT ROWID
  SQL
  raw.exec("CREATE INDEX idx_recipes_settings ON recipes(settings_id)")
  raw.exec(<<-SQL)
    CREATE TABLE recipe_fields (
      asset_id INTEGER NOT NULL,
      step     INTEGER NOT NULL,
      field    TEXT NOT NULL,
      text_id  INTEGER NOT NULL REFERENCES texts(id),
      named_id INTEGER REFERENCES named_texts(id),
      PRIMARY KEY (asset_id, step, field),
      FOREIGN KEY (asset_id, step) REFERENCES recipes(asset_id, step) ON DELETE CASCADE
    ) WITHOUT ROWID
  SQL
end

# The id of these words in a raw store's texts, added if they're new.
private def raw_text(raw : ::DB::Database, words : String) : Int64
  raw.exec("INSERT OR IGNORE INTO texts (hash, text) VALUES (?, ?)", sha(words), words)
  raw.scalar("SELECT id FROM texts WHERE hash = ?", sha(words)).as(Int64)
end

# A 0.13 recipe step and its fields ({field => {words, named_texts id}}).
private def raw_step(raw : ::DB::Database, asset : Int64, step : Int32, form : String,
                     fields : Hash(String, {String, Int64?}), sent : String? = nil, as_joined : Bool = false,
                     refs : String? = nil) : Nil
  raw.exec("INSERT INTO recipes (asset_id, step, form, sent_as_joined, prompt_sent_id, refs) VALUES (?, ?, ?, ?, ?, ?)",
    asset, step, form, as_joined ? 1 : 0, sent.try { |words| raw_text(raw, words) }, refs)
  fields.each do |field, (words, named)|
    raw.exec("INSERT INTO recipe_fields (asset_id, step, field, text_id, named_id) VALUES (?, ?, ?, ?, ?)",
      asset, step, field, raw_text(raw, words), named)
  end
end

private def raw_named(raw : ::DB::Database, field : String, owner : String, name : String, purpose : String,
                      version : Int32, words : String, purposes : Bool = true) : Int64
  if purposes
    raw.exec("INSERT INTO named_texts (field, owner, name, purpose, version, text_id) VALUES (?, ?, ?, ?, ?, ?)",
      field, owner, name, purpose, version, raw_text(raw, words))
  else
    raw.exec("INSERT INTO named_texts (field, owner, name, version, text_id) VALUES (?, ?, ?, ?, ?)",
      field, owner, name, version, raw_text(raw, words))
  end
  raw.scalar("SELECT last_insert_rowid()").as(Int64)
end

describe DataDungeon::Recipe do
  it "stores a picture's recipe and reads it back: what was sent, and the wordings in it" do
    with_db("dd-recipe") do |db|
      rec = store_panel(db, "a", picture("A tall elf with red braids."))
      rec.has_recipe?.should be_true

      got = db.recipe(rec.id).not_nil!
      got.form.should eq "picture"
      got.prompt.should eq "Draw one panel. Silver Age comic. Silver Age comic art. A tall elf with red braids."
      got.instructions.should be_nil
      got.wordings.map(&.kind).should eq %w[framing style flavor] # in the order given
      got.wordings.map(&.name).should eq ["overlore:house@#{version("Draw one panel.")}", SILVER.name,
                                          "overlore:silver-comic@#{version("Silver Age comic art.")}"]
      got.wordings[2].text.should eq "Silver Age comic art."
      got.settings.should eq({"camera" => "mj:camera:flare", "model" => "flux-dev", "steps" => 4})
      got.seed.should eq 7
      got.cost.should eq 0.04
      got.generated_at.should eq Time.utc(2026, 10, 13, 9, 30)
      got.references.should eq ["a" * 64]

      plain = store_panel(db, "b")
      plain.has_recipe?.should be_false
      db.recipe(plain.id).should be_nil
    end
  end

  it "versions a wording by its words, the same in every store, and finds the assets using it" do
    with_db("dd-recipe-names") do |db|
      first = store_panel(db, "a", picture("A", flavor: "Silver Age comic art."))
      second = store_panel(db, "b", picture("B", flavor: "Silver Age comic art, heavy inks."))
      again = store_panel(db, "c", picture("C", flavor: "Silver Age comic art."))

      inked = version("Silver Age comic art, heavy inks.")
      inked.should eq Digest::SHA256.hexdigest("Silver Age comic art, heavy inks.")[0, 10]
      db.recipe(second.id).not_nil!.wordings[2].name.should eq "overlore:silver-comic@#{inked}"
      db.recipe(again.id).not_nil!.wordings[2].name.should eq db.recipe(first.id).not_nil!.wordings[2].name
      db.with_text("flavor", "overlore:silver-comic").should eq [first.id, second.id, again.id]
      db.with_text("flavor", "overlore:silver-comic@#{version("Silver Age comic art.")}").should eq [first.id, again.id]
      db.with_text("framing", "overlore:silver-comic").should be_empty # names belong to a kind
      db.with_text("style", "dd:silver-comic").should eq [first.id, second.id, again.id]
      db.named_texts("flavor", "overlore").should eq [{"silver-comic", version("Silver Age comic art."), "Silver Age comic art."},
                                                      {"silver-comic", inked, "Silver Age comic art, heavy inks."}]
      wrong = DataDungeon::Recipe.new("picture", prompt: "Silver Age comic. Silver Age comic art.",
        wordings: [SILVER, wording("flavor", "overlore:silver-comic@#{inked}", "Silver Age comic art.")])
      expect_raises(ArgumentError, /version #{version("Silver Age comic art.")}, not #{inked}/) { store_panel(db, "d", wrong) }
    end

    with_db("dd-recipe-names-elsewhere") do |db|
      other = store_panel(db, "a", picture("A", flavor: "Silver Age comic art, heavy inks."))
      db.recipe(other.id).not_nil!.wordings[2].name.should eq "overlore:silver-comic@#{version("Silver Age comic art, heavy inks.")}"
    end
  end

  it "files a style's wordings by purpose" do
    with_db("dd-recipe-purpose") do |db|
      figure = store_panel(db, "a", flavored("An elf.", "overlore:silver-comic/figure", "Silver Age comic art, one figure."))
      place = store_panel(db, "b", flavored("A hall.", "overlore:silver-comic/place", "Silver Age comic art, a wide room."))
      inked = store_panel(db, "c", flavored("A dwarf.", "overlore:silver-comic/figure", "Silver Age comic art, heavy inks."))
      bare = store_panel(db, "d", flavored("A cat.", "overlore:silver-comic", "Silver Age comic art."))

      db.recipe(figure.id).not_nil!.wordings[1].name.should eq "overlore:silver-comic/figure@#{version("Silver Age comic art, one figure.")}"
      db.recipe(bare.id).not_nil!.wordings[1].name.should eq "overlore:silver-comic@#{version("Silver Age comic art.")}" # a purpose is optional
      db.with_text("flavor", "overlore:silver-comic").should eq [figure.id, place.id, inked.id, bare.id]
      db.with_text("flavor", "overlore:silver-comic/figure").should eq [figure.id, inked.id]
      db.with_text("flavor", "overlore:silver-comic/figure@#{version("Silver Age comic art, heavy inks.")}").should eq [inked.id]
      db.list_assets(texts: {"flavor" => "overlore:silver-comic/place"}).map(&.id).should eq [place.id]
      db.named_texts("flavor", "overlore").map(&.[0]).should eq ["silver-comic", "silver-comic/figure", "silver-comic/figure",
                                                                 "silver-comic/place"] # oldest first within each
    end
  end

  it "lets any app use a store's wordings, and only its owner add one" do
    dir = File.tempname("dd-recipe-owner")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    overlore = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    overlore.register_type("panel", pool_traits: %w[art-style])
    store_panel(overlore, "a", picture("A"))
    overlore.close

    owl = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "owl")
    used = store_panel(owl, "b", picture("B")) # Overlore's wordings, as they are
    owl.recipe(used.id).not_nil!.wordings[2].name.should start_with "overlore:silver-comic@"
    expect_raises(ArgumentError, /overlore:silver-comic is overlore's/) do
      store_panel(owl, "c", picture("C", flavor: "Owl's own take on silver."))
    end
    expect_raises(ArgumentError, /isn't DataDungeon's words/) do
      store_panel(owl, "d", DataDungeon::Recipe.new("picture", prompt: "Silver, more or less.",
        wordings: [wording("style", "dd:silver-comic", "Silver, more or less.")]))
    end
    owl.find_assets_by_tags("panel", {"art-style" => "silver-comic"}).size.should eq 2 # the refused stores left nothing
  ensure
    owl.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "stores each text and each set of settings once" do
    with_db("dd-recipe-once") do |db|
      a = store_panel(db, "a", picture("A dwarf.", settings: {"steps" => 4, "model" => "flux-dev"}),
        description: "A dwarf.")
      store_panel(db, "b", picture("A dwarf.", settings: {"model" => "flux-dev", "steps" => 4}),
        description: "A dwarf.")

      count(db, "recipe_settings").should eq 1 # the keys' order doesn't matter
      db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = ?", picture("A dwarf.").prompt).as(Int64).should eq 1
      db.connection.scalar("SELECT COUNT(*) FROM texts WHERE text = 'A dwarf.'").as(Int64).should eq 1
      db.find_asset_by_id(a.id).not_nil!.description.should eq "A dwarf."
    end
  end

  it "stores speech and text with their instructions, and a recipe made in steps" do
    with_db("dd-recipe-forms") do |db|
      speech = DataDungeon::Recipe.new("speech", settings: {"model" => "gpt-4o-mini-tts", "voice" => "fable"},
        prompt: "Sit down, bard.", instructions: "Gruff, tired.",
        wordings: [wording("style", "overlore:veteran", "Gruff, tired.")], cost: 0.001)
      line = db.store("line", {"voice" => "fable"}, bytes: "mp3".to_slice, content_type: "audio/mpeg", recipe: speech)
      got = db.recipe(line.id).not_nil!
      got.prompt.should eq "Sit down, bard."
      got.instructions.should eq "Gruff, tired."
      got.wordings.map(&.name).should eq ["overlore:veteran@#{version("Gruff, tired.")}"]
      db.with_text("style", "overlore:veteran").should eq [line.id]

      chat = DataDungeon::Recipe.new("text", prompt: "The hall, from the door.", instructions: "Describe a room in one sentence.")
      decree = db.store("line", {"voice" => "none"}, bytes: "words".to_slice, content_type: "text/plain", recipe: chat)
      db.recipe(decree.id).not_nil!.instructions.should eq "Describe a room in one sentence."

      edit = picture("A rain-soaked street.")
      matte = DataDungeon::Recipe.new("", settings: {"tool" => "overlore:matte", "version" => 2},
        references: ["b" * 64, "c" * 64])
      layer = store_panel(db, "layer", DataDungeon::Recipe.in_steps([edit, matte]))
      steps = db.recipe(layer.id).not_nil!.steps
      steps.size.should eq 2
      steps[0].prompt.should eq edit.prompt
      steps[0].wordings.size.should eq 3
      steps[1].form.should eq ""
      steps[1].prompt.should be_nil
      steps[1].references.should eq ["b" * 64, "c" * 64]
    end
  end

  it "refuses a recipe that isn't in the standard shape, before storing anything" do
    with_db("dd-recipe-check") do |db|
      bad = [
        DataDungeon::Recipe.new("painting"),
        DataDungeon::Recipe.new("picture", prompt: ""),
        DataDungeon::Recipe.new("picture", prompt: "A.", instructions: "Paint it."),
        DataDungeon::Recipe.new("picture", references: ["not-a-hash"]),
        DataDungeon::Recipe.new("", prompt: "A."),
        DataDungeon::Recipe.new("picture", prompt: "A dwarf.", wordings: [wording("flavor", "overlore:silver-comic", "Bold inks.")]),
        DataDungeon::Recipe.new("picture", wordings: [SILVER]),
        DataDungeon::Recipe.new("picture", prompt: "A.", wordings: [wording("flavor", "silver", "A.")]),
        DataDungeon::Recipe.new("picture", prompt: "A.", wordings: [wording("flavor", "overlore:silver-comic/", "A.")]),
        DataDungeon::Recipe.new("picture", prompt: "A.", wordings: [wording("flavor", "overlore:silver-comic/Figure", "A.")]),
        DataDungeon::Recipe.new("picture", prompt: "A.", wordings: [wording("flavor", "overlore:silver-comic/a/b", "A.")]),
        DataDungeon::Recipe.new("picture", prompt: "A.", wordings: [wording("flavor", "overlore:silver-comic@2", "A.")]),
        DataDungeon::Recipe.new("picture", prompt: "A.", wordings: [wording("Flavor", "overlore:silver-comic", "A.")]),
        DataDungeon::Recipe.new("picture", prompt: "A.", wordings: [wording("flavor", "overlore:silver-comic", "")]),
      ]
      bad.each do |recipe|
        expect_raises(ArgumentError) { store_panel(db, "a", recipe) }
      end
      expect_raises(ArgumentError, /isn't in what was sent/) { bad[5].check }
      count(db, "assets").should eq 0
      Dir.glob(File.join(db.storage.not_nil!.as(DataDungeon::LocalStorage).root, "**", "*.webp")).should be_empty
    end
  end

  it "takes a picture's style from the vocabulary, and the app's own words as its flavor" do
    with_db("dd-recipe-styles") do |db|
      db.style_text("silver-comic").should eq SILVER
      store_panel(db, "a", picture("A dwarf.")).has_recipe?.should be_true
      own = DataDungeon::Recipe.new("picture", prompt: "Silver Age comic art. A dwarf.",
        wordings: [wording("style", "overlore:silver-comic", "Silver Age comic art.")])
      expect_raises(ArgumentError, /a picture's style is DataDungeon's words/) { store_panel(db, "b", own) }
      lonely = DataDungeon::Recipe.new("picture", prompt: "Bold inks. A dwarf.",
        wordings: [wording("flavor", "overlore:silver-comic", "Bold inks.")])
      expect_raises(ArgumentError, /a flavor adds to a style/) { store_panel(db, "c", lonely) }
      golden = DataDungeon::Recipe.new("picture", prompt: "Silver Age comic. Bold golden inks.",
        wordings: [SILVER, wording("flavor", "overlore:golden-comic", "Bold golden inks.")])
      expect_raises(ArgumentError, /is a flavor of golden-comic, but this picture's style is silver-comic/) { store_panel(db, "d", golden) }
      expect_raises(ArgumentError, /isn't a standard art style/) { db.style_text("kiddy-cartoon") }
      # A voice's style is its own: the art styles are pictures'.
      speech = DataDungeon::Recipe.new("speech", prompt: "Hello.", instructions: "Warm.",
        wordings: [wording("style", "overlore:host", "Warm.")])
      db.store("line", {"voice" => "fable"}, bytes: "mp3".to_slice, content_type: "audio/mpeg", recipe: speech).has_recipe?.should be_true
    end
  end

  it "takes a rating's words from the vocabulary, for every form" do
    with_db("dd-recipe-ratings") do |db|
      words = "Suitable for older children: mild peril and action, kept clean."
      pg = db.rating_text("pg")
      pg.should eq wording("rating", "dd:pg@#{version(words)}", words)
      id = store_panel(db, "a", DataDungeon::Recipe.new("picture", prompt: "#{words} #{SILVER_WORDS} A dwarf.",
        wordings: [pg, SILVER])).id
      db.recipe(id).not_nil!.wordings.should eq [pg, SILVER]
      db.with_text("rating", "dd:pg").should eq [id]
      text = DataDungeon::Recipe.new("text", prompt: "A dwarf's tale.", instructions: "Tell it. #{words}", wordings: [pg])
      db.store("line", {"voice" => "fable"}, bytes: "tale".to_slice, content_type: "text/plain", recipe: text).has_recipe?.should be_true
      reworded = DataDungeon::Recipe.new("picture", prompt: "Kept clean. #{SILVER_WORDS} A dwarf.",
        wordings: [wording("rating", "dd:pg", "Kept clean."), SILVER])
      expect_raises(ArgumentError, /isn't DataDungeon's words/) { store_panel(db, "b", reworded) }
      expect_raises(ArgumentError, /isn't a rating/) { db.rating_text("pg-13") }
    end
  end

  it "never changes or deletes a wording" do
    with_db("dd-recipe-kept") do |db, dir|
      store_panel(db, "a", picture("A dwarf."))
      raw = ::DB.open("sqlite3://#{File.join(dir, "assets.db")}")
      expect_raises(SQLite3::Exception, /a wording never changes/) do
        raw.exec("UPDATE named_texts SET name = 'pixel-16' WHERE owner = 'overlore' AND name = 'silver-comic'")
      end
      expect_raises(SQLite3::Exception, /a wording is never deleted/) do
        raw.exec("DELETE FROM named_texts WHERE owner = 'overlore'")
      end
      raw.close rescue nil
      db.with_text("flavor", "overlore:silver-comic").size.should eq 1
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
      db.recipe(old.id).not_nil!.prompt.should eq picture("An elf.").prompt

      expect_raises(ArgumentError, /has a recipe; pass replace: true/) do
        db.set_recipe(old.id, picture("An old elf."))
      end
      db.recipe(old.id).not_nil!.prompt.should eq picture("An elf.").prompt # untouched
      db.set_recipe(old.id, picture("An old elf."), replace: true)
      db.recipe(old.id).not_nil!.prompt.should eq picture("An old elf.").prompt
      count(db, "recipes").should eq 2
      count(db, "recipe_wordings").should eq 6 # the replaced recipe's went with it
      expect_raises(ArgumentError, /No asset/) { db.set_recipe(999, picture("X")) }
    end
  end

  it "won't let a text an asset or a recipe uses be deleted" do
    with_db("dd-recipe-keep") do |db, dir|
      store_panel(db, "a", picture("A dwarf."), description: "A small room.")
      raw = ::DB.open("sqlite3://#{File.join(dir, "assets.db")}?foreign_keys=on")
      ["A small room.", picture("A dwarf.").prompt.not_nil!, "Silver Age comic art."].each do |words|
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

  it "seeds the shared vocabulary once, with each art style's and rating's words" do
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
      styles.find!(&.value.==("silver-comic")).wording.should eq SILVER
      rating = vocabulary[1]
      rating.kind.should eq "scale"
      rating.values.map(&.value).should eq %w[g pg r x]
      rating.values.map(&.wording.not_nil!.kind).uniq.should eq ["rating"]
      rating.values[2].wording.should eq db.rating_text("r")
      rating.values[3].wording.not_nil!.text.should eq "For adults only."

      named = count(db, "named_texts")
      db.close
      db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"), consumer: "overlore")
      count(db, "named_texts").should eq named # nothing new on a second open
      db.style_text("silver-comic").name.should eq SILVER.name
      read_only = DataDungeon::DB.new(File.join(dir, "assets.db"), read_only: true)
      read_only.vocabulary.size.should eq 2
      read_only.close
    end
  end

  it "moves a 0.13 store's recipes to what was sent, each named field a wording" do
    dir = File.tempname("dd-recipe-from-013")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.register_type("panel", pool_traits: %w[art-style])
    db.register_type("line", pool_traits: %w[voice])
    joined, sent, filled, bare, layer = %w[a b c d e].map { |bytes| store_panel(db, bytes).id }
    line = db.store("line", {"voice" => "fable"}, bytes: "mp3".to_slice, content_type: "audio/mpeg").id
    decree = db.store("line", {"voice" => "none"}, bytes: "words".to_slice, content_type: "text/plain").id
    db.close

    raw = ::DB.open("sqlite3://#{path}")
    as_013(raw)
    place1 = raw_named(raw, "style", "overlore", "silver-comic", "place", 1, "Silver Age comic art.")
    place2 = raw_named(raw, "style", "overlore", "silver-comic", "place", 2, "Silver Age comic art, heavy inks.")
    veteran = raw_named(raw, "style", "overlore", "veteran", "", 1, "Gruff, tired.")
    ids = raw.query_all("SELECT id FROM named_texts ORDER BY id", as: Int64)
    picture_fields = {"preamble" => {"Draw one panel.", nil}, "description" => {"A long hall.", nil},
                      "style" => {"Silver Age comic art.", place1}, "rules" => {"No text.", nil}}
    raw_step(raw, joined, 0, "picture", picture_fields.merge({"subject" => {"A dwarf.", nil}}), sent: "x", as_joined: true)
    raw.exec("UPDATE recipes SET prompt_sent_id = NULL WHERE asset_id = ?", joined) # 0.13 kept none when it was the join
    raw_step(raw, sent, 0, "picture", {"style" => {"Silver Age comic art, heavy inks.", place2}},
      sent: "A misty hall, in heavy inks.")
    raw_step(raw, filled, 0, "picture", {"subject" => {"An elf.", nil}, "theme" => {"", nil}})
    raw_step(raw, bare, 0, "picture", {} of String => {String, Int64?})
    raw_step(raw, layer, 0, "picture", {"subject" => {"A street.", nil}})
    raw_step(raw, layer, 1, "", {} of String => {String, Int64?}, refs: %(["#{"b" * 64}"]))
    raw_step(raw, line, 0, "speech", {"style" => {"Gruff, tired.", veteran}, "text" => {"Sit down, bard.", nil}})
    raw_step(raw, decree, 0, "text", {"instructions" => {"Write a decree.", nil}, "description" => {"The king's.", nil}})
    raw.close

    expect_raises(DataDungeon::ReadOnlyError, /open it read-write once/) do
      DataDungeon::DB.new(path, read_only: true)
    end
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    got = db.recipe(joined).not_nil!
    got.prompt.should eq "Draw one panel. A dwarf. A long hall. Silver Age comic art. No text." # 0.13's order
    got.wordings.map(&.name).should eq ["overlore:silver-comic/place@#{version("Silver Age comic art.")}"]
    got.wordings[0].kind.should eq "style"
    db.recipe(sent).not_nil!.prompt.should eq "A misty hall, in heavy inks." # as sent, not its fields
    db.recipe(filled).not_nil!.prompt.should eq "An elf."                    # its fields joined, as 0.13 read it
    db.recipe(bare).not_nil!.prompt.should be_nil                            # settings only
    steps = db.recipe(layer).not_nil!.steps
    steps.map(&.prompt).should eq ["A street.", nil]
    steps[1].references.should eq ["b" * 64]
    speech = db.recipe(line).not_nil!
    {speech.prompt, speech.instructions}.should eq({"Sit down, bard.", "Gruff, tired."})
    speech.wordings.map(&.name).should eq ["overlore:veteran@#{version("Gruff, tired.")}"]
    text = db.recipe(decree).not_nil!
    {text.prompt, text.instructions}.should eq({"The king's.", "Write a decree."})

    db.connection.query_all("SELECT id FROM named_texts WHERE owner = 'overlore' ORDER BY id", as: Int64).should eq ids
    db.with_text("style", "overlore:silver-comic/place@#{version("Silver Age comic art, heavy inks.")}").should eq [sent]
    columns = db.connection.query_all("SELECT name FROM pragma_table_info('recipes')", as: String)
    columns.should contain "prompt_id"
    columns.should_not contain "sent_as_joined"
    columns.should_not contain "prompt_sent_id"
    count(db, "recipe_fields").should eq 13 # kept as they were
    db.connection.query_all("PRAGMA foreign_key_check", &.read(::DB::Any)).should be_empty
    db.style_text("silver-comic").should eq SILVER # the vocabulary, seeded after
    db.recipe(store_panel(db, "f", picture("An orc.")).id).not_nil!.wordings.size.should eq 3
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "names words a stored recipe was sent, checking only the new wordings" do
    dir = File.tempname("dd-recipe-add-wordings")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.register_type("panel", pool_traits: %w[art-style])
    old, layer = %w[a b].map { |bytes| store_panel(db, bytes).id }
    db.close

    raw = ::DB.open("sqlite3://#{path}")
    as_013(raw)
    place = raw_named(raw, "style", "overlore", "silver-comic", "place", 1, "Silver Age comic art.")
    raw_step(raw, old, 0, "picture", {"style" => {"Silver Age comic art.", place}, "rules" => {"Kept clean.", nil}})
    raw_step(raw, layer, 0, "picture", {"subject" => {"A street.", nil}})
    raw_step(raw, layer, 1, "", {} of String => {String, Int64?})
    raw.close

    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    stored = db.recipe(old).not_nil!
    pg = wording("rating", "overlore:pg", "Kept clean.")
    # Its style is an app's, from before 0.14, so the recipe as a whole isn't one a store takes now.
    expect_raises(ArgumentError, /a picture's style is DataDungeon's words/) { db.set_recipe(old, stored, replace: true) }
    db.add_wordings(old, [pg, pg]).should eq 1
    db.recipe(old).not_nil!.wordings.should eq stored.wordings + [wording("rating", "overlore:pg@#{version("Kept clean.")}", "Kept clean.")]
    db.with_text("rating", "overlore:pg").should eq [old]
    db.add_wordings(old, [pg]).should eq 0 # named already
    expect_raises(ArgumentError, /isn't in what was sent/) { db.add_wordings(old, [wording("rating", "overlore:r", "Gory.")]) }
    expect_raises(ArgumentError, /a picture's style is DataDungeon's words/) do
      db.add_wordings(old, [wording("style", "overlore:silver-comic", "Silver Age comic art.")])
    end
    expect_raises(ArgumentError, /is owl's/) { db.add_wordings(old, [wording("rating", "owl:pg", "Kept clean.")]) }
    db.add_wordings(layer, [wording("subject", "overlore:street", "A street.")]).should eq 1
    expect_raises(ArgumentError, /a step without a form/) { db.add_wordings(layer, [pg], step: 1) }
    expect_raises(ArgumentError, /has no recipe step 2/) { db.add_wordings(layer, [pg], step: 2) }
    expect_raises(ArgumentError, /has no recipe step 0/) { db.add_wordings(store_panel(db, "c").id, [pg]) }
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "versions a 0.13.0 store's named texts, which had no purposes" do
    dir = File.tempname("dd-recipe-from-0130")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.register_type("panel", pool_traits: %w[art-style])
    first, second = %w[a b].map { |bytes| store_panel(db, bytes).id }
    db.close
    raw = ::DB.open("sqlite3://#{path}")
    as_013(raw, purposes: false)
    silver1 = raw_named(raw, "style", "overlore", "silver", "", 1, "Silver Age comic art.", purposes: false)
    silver2 = raw_named(raw, "style", "overlore", "silver", "", 2, "Silver Age comic art, heavy inks.", purposes: false)
    raw_step(raw, first, 0, "picture", {"style" => {"Silver Age comic art.", silver1}})
    raw_step(raw, second, 0, "picture", {"style" => {"Silver Age comic art, heavy inks.", silver2}})
    raw.close

    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.recipe(second).not_nil!.wordings.map(&.name).should eq ["overlore:silver@#{version("Silver Age comic art, heavy inks.")}"]
    db.with_text("style", "overlore:silver@#{version("Silver Age comic art.")}").should eq [first]
    db.connection.query_all("PRAGMA foreign_key_check", &.read(::DB::Any)).should be_empty
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "leaves a 0.13 store as it was when its recipes don't read back the same" do
    dir = File.tempname("dd-recipe-from-013-refused")
    Dir.mkdir_p(dir)
    path = File.join(dir, "assets.db")
    db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    db.register_type("line", pool_traits: %w[voice])
    line = db.store("line", {"voice" => "fable"}, bytes: "mp3".to_slice, content_type: "audio/mpeg").id
    db.close
    raw = ::DB.open("sqlite3://#{path}")
    as_013(raw)
    # Speech with a prompt_sent of its own: 0.14 has nowhere to keep it.
    raw_step(raw, line, 0, "speech", {"text" => {"Hello.", nil}}, sent: "Hello there.")
    raw.close

    expect_raises(Exception, /left 1 different; the store is unchanged/) do
      DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), consumer: "overlore")
    end
    raw = ::DB.open("sqlite3://#{path}")
    raw.query_all("SELECT name FROM pragma_table_info('recipes')", as: String).should contain "prompt_sent_id"
    raw.query_all("SELECT name FROM pragma_table_info('named_texts')", as: String).should contain "field"
    raw.close
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps a cost's basis, and a whole prompt" do
    with_db("dd-recipe-cost") do |db|
      priced = DataDungeon::Recipe.new("picture", prompt: "A.", cost: 0.04, cost_basis: "reported: runware")
      db.recipe(store_panel(db, "a", priced).id).not_nil!.cost_basis.should eq "reported: runware"
      expect_raises(ArgumentError, /no cost/) do
        store_panel(db, "b", DataDungeon::Recipe.new("picture", cost_basis: "estimated"))
      end

      # An old record: the settings and the whole prompt, with no wordings.
      old = store_panel(db, "c")
      whole = "A misty valley at dawn. Style: painterly fantasy. No text, no watermark."
      db.set_recipe(old.id, DataDungeon::Recipe.new("picture", settings: {"steps" => 20}, prompt: whole))
      got = db.recipe(old.id).not_nil!
      got.wordings.should be_empty
      got.prompt.should eq whole
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

  it "lists the assets with a file, or using a wording" do
    with_db("dd-recipe-list") do |db|
      first = store_panel(db, "a", picture("A", flavor: "Silver Age comic art."))
      second = store_panel(db, "b", picture("B", flavor: "Silver Age comic art, heavy inks."))
      plain = store_panel(db, "c")
      db.list_assets(file_hash: plain.file_hash).map(&.id).should eq [plain.id]
      db.list_assets(texts: {"flavor" => "overlore:silver-comic"}).map(&.id).should eq [second.id, first.id]
      inked = "overlore:silver-comic@#{version("Silver Age comic art, heavy inks.")}"
      db.list_assets("panel", texts: {"flavor" => inked}).map(&.id).should eq [second.id]
      db.count_assets(texts: {"framing" => "overlore:house", "flavor" => "overlore:silver-comic@#{version("Silver Age comic art.")}"}).should eq 1
      expect_raises(ArgumentError, /owner:name/) { db.list_assets(texts: {"style" => "silver"}) }
    end
  end
end
