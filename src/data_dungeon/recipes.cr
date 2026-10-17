require "digest/sha256"
require "json"
require "./recipe"

module DataDungeon
  class DB
    # Every wording, an asset's description or what a recipe's provider was
    # sent, is one row, stored once (DESIGN-recipes.md).
    TEXTS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS texts (
        id   INTEGER PRIMARY KEY,
        hash TEXT NOT NULL UNIQUE,
        text TEXT NOT NULL
      )
    SQL

    # Settings are stored once by hash, as canonical JSON (keys sorted).
    # A named text is one wording of an owner's name, of some kind (`style`,
    # `flavor`, ...), with what it's for (its purpose, empty for none); its
    # version is the start of its words' SHA-256 (Recipe::VERSION_SIZE), so
    # it names the same words in every store. A recipe is a row per step (0
    # for a single recipe), with what its provider was sent, and a row per
    # named wording it used. Before 0.13 an asset's `generation` was
    # free-form JSON on its row; it stays readable in recipe_legacy until
    # its app gives it a recipe. A store from 0.13 also keeps its prompt
    # fields as they were, in recipe_fields, no longer written.
    RECIPE_SCHEMAS = <<-SQL
      CREATE TABLE IF NOT EXISTS recipe_settings (
        id       INTEGER PRIMARY KEY,
        hash     TEXT NOT NULL UNIQUE,
        settings TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS named_texts (
        id      INTEGER PRIMARY KEY,
        kind    TEXT NOT NULL,
        owner   TEXT NOT NULL,
        name    TEXT NOT NULL,
        purpose TEXT NOT NULL DEFAULT '',
        version TEXT NOT NULL,
        text_id INTEGER NOT NULL REFERENCES texts(id),
        UNIQUE (kind, owner, name, purpose, version)
      );
      CREATE TABLE IF NOT EXISTS recipes (
        asset_id        INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        step            INTEGER NOT NULL,
        form            TEXT NOT NULL,
        settings_id     INTEGER REFERENCES recipe_settings(id),
        seed            INTEGER,
        cost            REAL,
        cost_basis      TEXT,
        generated_at    TEXT,
        prompt_id       INTEGER REFERENCES texts(id),
        instructions_id INTEGER REFERENCES texts(id),
        refs            TEXT,
        PRIMARY KEY (asset_id, step)
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS idx_recipes_settings ON recipes(settings_id);
      CREATE TABLE IF NOT EXISTS recipe_wordings (
        asset_id INTEGER NOT NULL,
        step     INTEGER NOT NULL,
        position INTEGER NOT NULL,
        named_id INTEGER NOT NULL REFERENCES named_texts(id),
        PRIMARY KEY (asset_id, step, position),
        FOREIGN KEY (asset_id, step) REFERENCES recipes(asset_id, step) ON DELETE CASCADE
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS idx_recipe_wordings_named ON recipe_wordings(named_id);
      CREATE TABLE IF NOT EXISTS recipe_legacy (
        asset_id   INTEGER PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
        generation TEXT NOT NULL
      )
    SQL

    # A wording never changes and is never deleted, so a name and version
    # mean the same words for as long as the store lasts, in the sqlite3
    # shell too. New words are a new version; a new name is a new wording.
    WORDING_TRIGGERS = [
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS named_texts_kept_update BEFORE UPDATE ON named_texts
        BEGIN SELECT RAISE(ABORT, 'a wording never changes: new words are a new version, a new name a new wording'); END
      SQL
      <<-SQL,
        CREATE TRIGGER IF NOT EXISTS named_texts_kept_delete BEFORE DELETE ON named_texts
        BEGIN SELECT RAISE(ABORT, 'a wording is never deleted: recipes name it'); END
      SQL
    ]

    # A 0.13 picture's prompt fields in the order they were joined, for
    # reading what it was sent (Recipe#joined in 0.13).
    PICTURE_FIELDS_013 = %w[preamble subject description staging theme style rules]

    # The asset's recipe, steps and all, with each wording as
    # `owner:name@version` (`owner:name/purpose@version` with a purpose);
    # nil when it has none.
    def recipe(id : Int64) : Recipe?
      rows = @db.query_all(<<-SQL, id, as: {Int32, String, String?, Int64?, Float64?, String?, String?, String?, String?, String?})
        SELECT r.step, r.form, s.settings, r.seed, r.cost, r.cost_basis, r.generated_at, p.text, i.text, r.refs
        FROM recipes r
        LEFT JOIN recipe_settings s ON s.id = r.settings_id
        LEFT JOIN texts p ON p.id = r.prompt_id
        LEFT JOIN texts i ON i.id = r.instructions_id
        WHERE r.asset_id = ? ORDER BY r.step
      SQL
      return nil if rows.empty?

      wordings = Hash(Int32, Array(Recipe::Wording)).new { |hash, step| hash[step] = [] of Recipe::Wording }
      @db.query_all(<<-SQL, id, as: {Int32, String, String, String, String, String, String}).each do |(step, kind, owner, name, purpose, version, text)|
        SELECT w.step, n.kind, n.owner, n.name, n.purpose, n.version, t.text
        FROM recipe_wordings w
        JOIN named_texts n ON n.id = w.named_id
        JOIN texts t ON t.id = n.text_id
        WHERE w.asset_id = ? ORDER BY w.step, w.position
      SQL
        wordings[step] << Recipe::Wording.new(kind, Recipe::Wording.handle(owner, name, purpose, version), text)
      end

      steps = rows.map do |(step, form, settings, seed, cost, basis, made, prompt, instructions, refs)|
        Recipe.new(form,
          settings: settings.try { |json| JSON.parse(json).as_h } || {} of String => JSON::Any,
          prompt: prompt, instructions: instructions, wordings: wordings[step]? || [] of Recipe::Wording,
          seed: seed, cost: cost, cost_basis: basis,
          generated_at: made.try { |time| Time.parse_utc(time, TIME_FORMAT) },
          references: refs.try { |json| Array(String).from_json(json) } || [] of String)
      end
      steps.size == 1 ? steps.first : Recipe.in_steps(steps)
    end

    # Gives an asset its recipe, for moving an app's old records into
    # recipes. An asset that has a recipe keeps it: replacing one takes
    # `replace: true`. The free-form record the asset was stored with before
    # 0.13 (`generation`) is kept too, unless `drop_generation: true` says
    # the recipe holds everything it said.
    def set_recipe(id : Int64, recipe : Recipe, replace : Bool = false, drop_generation : Bool = false) : Nil
      writable!
      recipe.check
      check_wordings(recipe)
      write_transaction do |conn|
        unless conn.query_one?("SELECT 1 FROM assets WHERE id = ?", id, as: Int32)
          raise ArgumentError.new("No asset #{id}")
        end
        if !replace && conn.query_one?("SELECT 1 FROM recipes WHERE asset_id = ? LIMIT 1", id, as: Int32)
          raise ArgumentError.new("Asset #{id} has a recipe; pass replace: true to replace it")
        end
        conn.exec("DELETE FROM recipes WHERE asset_id = ?", id) if replace # its wordings' rows go with it
        write_recipe(conn, id, recipe)
        conn.exec("DELETE FROM recipe_legacy WHERE asset_id = ?", id) if drop_generation
      end
      @indexer.try(&.enqueue_asset(id))
    end

    # The assets whose recipes used a named wording of a kind, retired ones
    # included, oldest first: `with_text("flavor", "overlore:silver-comic")`
    # for any of its wordings, whatever their purpose,
    # `"overlore:silver-comic/figure"` for one purpose's, and
    # `"overlore:silver-comic/figure@3f9a2c71b0"` for one wording;
    # `with_text("style", "dd:silver-comic")` for every picture given
    # DataDungeon's words for the style. (Before 0.14 an app's wording was
    # the style.)
    def with_text(kind : String, name : String) : Array(Int64)
      sql, args = using_text(kind, name)
      @db.query_all("SELECT DISTINCT asset_id FROM (#{sql}) ORDER BY asset_id", args: args, as: Int64)
    end

    # SQL selecting the `asset_id` of every recipe using a named wording of
    # a kind (any purpose or version; `/purpose` for one purpose,
    # `@version` for one wording), and its arguments.
    private def using_text(kind : String, name : String) : {String, Array(::DB::Any)}
      owner, base, purpose, version = Recipe::Wording.new(kind, name, "").handle
      sql = "SELECT w.asset_id FROM named_texts n JOIN recipe_wordings w ON w.named_id = n.id " \
            "WHERE n.kind = ? AND n.owner = ? AND n.name = ?"
      args = [kind, owner, base] of ::DB::Any
      unless purpose.empty?
        sql += " AND n.purpose = ?"
        args << purpose
      end
      if version
        sql += " AND n.version = ?"
        args << version
      end
      {sql, args}
    end

    # The wordings an owner has of a kind: {name, version, text}, the name
    # with its `/purpose` if it has one, by name and purpose, oldest first.
    def named_texts(kind : String, owner : String) : Array({String, String, String})
      @db.query_all(<<-SQL, kind, owner, as: {String, String, String, String}).map do |(name, purpose, version, text)|
        SELECT n.name, n.purpose, n.version, t.text FROM named_texts n JOIN texts t ON t.id = n.text_id
        WHERE n.kind = ? AND n.owner = ? ORDER BY n.name, n.purpose, n.id
      SQL
        {purpose.empty? ? name : "#{name}/#{purpose}", version, text}
      end
    end

    # Adds an asset's recipe rows; the asset has none.
    private def write_recipe(conn : ::DB::Connection, asset_id : Int64, recipe : Recipe) : Nil
      steps = recipe.steps.empty? ? [recipe] : recipe.steps
      steps.each_with_index do |step, i|
        conn.exec(<<-SQL,
          INSERT INTO recipes (asset_id, step, form, settings_id, seed, cost, cost_basis, generated_at,
                               prompt_id, instructions_id, refs)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
          asset_id, i, step.form, put_settings(conn, step.settings), step.seed, step.cost, step.cost_basis,
          step.generated_at.try(&.to_utc.to_s(TIME_FORMAT)), step.prompt.try { |text| put_text(conn, text) },
          step.instructions.try { |text| put_text(conn, text) },
          step.references.empty? ? nil : step.references.to_json)
        step.wordings.each_with_index do |wording, position|
          owner, name, purpose, _ = wording.handle
          named_id = put_named(conn, wording.kind, owner, name, purpose, put_text(conn, wording.text))
          conn.exec("INSERT INTO recipe_wordings (asset_id, step, position, named_id) VALUES (?, ?, ?, ?)",
            asset_id, i, position, named_id)
        end
      end
    end

    # The id of these words in the texts table, adding them if they're new.
    private def put_text(conn : ::DB::Connection, text : String) : Int64
      hash = Digest::SHA256.hexdigest(text)
      conn.exec("INSERT OR IGNORE INTO texts (hash, text) VALUES (?, ?)", hash, text)
      conn.scalar("SELECT id FROM texts WHERE hash = ?", hash).as(Int64)
    end

    private def put_settings(conn : ::DB::Connection, settings : Hash(String, JSON::Any)) : Int64?
      return nil if settings.empty?
      json = canonical_json(JSON::Any.new(settings))
      hash = Digest::SHA256.hexdigest(json)
      conn.exec("INSERT OR IGNORE INTO recipe_settings (hash, settings) VALUES (?, ?)", hash, json)
      conn.scalar("SELECT id FROM recipe_settings WHERE hash = ?", hash).as(Int64)
    end

    # The named_texts row for this wording of an owner's name and purpose,
    # its version the start of its words' SHA-256. Only the owner adds a
    # wording (DataDungeon adds its own, the art styles' words, with
    # `owned: true`); two wordings of one name whose versions are the same
    # (a 1 in a trillion chance) are refused rather than confused.
    private def put_named(conn : ::DB::Connection, kind : String, owner : String, name : String,
                          purpose : String, text_id : Int64, owned : Bool = false) : Int64
      version = conn.scalar("SELECT hash FROM texts WHERE id = ?", text_id).as(String)[0, Recipe::VERSION_SIZE]
      written = Recipe::Wording.handle(owner, name, purpose, version)
      row = conn.query_one?(<<-SQL, kind, owner, name, purpose, version, as: {Int64, Int64})
        SELECT id, text_id FROM named_texts WHERE kind = ? AND owner = ? AND name = ? AND purpose = ? AND version = ?
      SQL
      if row
        id, stored = row
        raise ArgumentError.new("two wordings of #{written} have the same version: give one another name") unless stored == text_id
        return id
      end
      unless owned || @consumer == owner
        raise ArgumentError.new("#{written} is #{owner}'s: only it adds a wording to it " \
                                "(this DB's consumer is #{@consumer.inspect})")
      end
      conn.exec("INSERT INTO named_texts (kind, owner, name, purpose, version, text_id) VALUES (?, ?, ?, ?, ?, ?)",
        kind, owner, name, purpose, version, text_id)
      conn.scalar("SELECT last_insert_rowid()").as(Int64)
    end

    # Whether a store has these words as this wording: the same kind, name
    # and purpose, any version.
    private def wording?(kind : String, owner : String, name : String, purpose : String, text : String) : Bool
      !@db.query_one?(<<-SQL, kind, owner, name, purpose, text, as: Int32).nil?
        SELECT 1 FROM named_texts n JOIN texts t ON t.id = n.text_id
        WHERE n.kind = ? AND n.owner = ? AND n.name = ? AND n.purpose = ? AND t.text = ?
      SQL
    end

    # The store's checks on a recipe's wordings, before anything is
    # written. A store is its owner's: a wording it hasn't seen is its
    # consumer's to add, and a `dd` one is DataDungeon's words already. A
    # picture's style is DataDungeon's words for an art style (no custom
    # top-level styles, Thomas), and its flavor, the app's own wording, is
    # named for that style (`overlore:silver-comic/place` with
    # `dd:silver-comic`). Recipes stored before 0.14 aren't checked.
    private def check_wordings(recipe : Recipe) : Nil
      (recipe.steps.empty? ? [recipe] : recipe.steps).each do |step|
        step.wordings.each do |wording|
          owner, name, purpose, _ = wording.handle
          next if wording?(wording.kind, owner, name, purpose, wording.text)
          if owner == VOCABULARY_OWNER
            raise ArgumentError.new("#{wording.name} isn't DataDungeon's words: a dd wording comes from the " \
                                    "store (db.style_text)")
          end
          unless owner == @consumer
            raise ArgumentError.new("#{wording.name} is #{owner}'s: a store adds its consumer's own wordings " \
                                    "(this DB's consumer is #{@consumer.inspect})")
          end
        end
        next unless step.form == "picture"
        styles = step.wordings.select(&.kind.==("style"))
        styles.each do |style|
          next if style.handle[0] == VOCABULARY_OWNER
          raise ArgumentError.new("a picture's style is DataDungeon's words for its art style, from " \
                                  "db.style_text(art_style); the app's own words are its flavor (#{style.name})")
        end
        step.wordings.select(&.kind.==("flavor")).each do |flavor|
          raise ArgumentError.new("a flavor adds to a style: give the picture its style too (db.style_text)") if styles.empty?
          named = styles.map(&.handle[1])
          unless named.includes?(flavor.handle[1])
            raise ArgumentError.new("#{flavor.name} is a flavor of #{flavor.handle[1]}, but this picture's style is #{named.join(" and ")}")
          end
        end
      end
    end

    # JSON with every object's keys sorted, so equal settings hash equally.
    private def canonical_json(value : JSON::Any) : String
      JSON.build do |json|
        write_canonical(json, value)
      end
    end

    private def write_canonical(json : JSON::Builder, value : JSON::Any) : Nil
      if hash = value.as_h?
        json.object do
          hash.keys.sort.each do |key|
            json.field(key) { write_canonical(json, hash[key]) }
          end
        end
      elsif array = value.as_a?
        json.array { array.each { |item| write_canonical(json, item) } }
      else
        value.to_json(json)
      end
    end

    # Before 0.13 an asset's description and its free-form `generation`
    # were columns. Descriptions move into texts, each wording once, and
    # the generation records into recipe_legacy as they are, since only
    # each app can read its own. Each column goes only once every value is
    # checked to read back the same from where it moved; otherwise this
    # raises and the open's transaction leaves the store as it was. One way.
    private def migrate_recipes(conn : ::DB::Connection) : Nil
      columns = table_columns(conn, "assets")
      unless columns.has_key?("description_id")
        conn.exec("ALTER TABLE assets ADD COLUMN description_id INTEGER REFERENCES texts(id)")
      end
      if columns.has_key?("description")
        ids = {} of String => Int64
        conn.query_all("SELECT id, description FROM assets WHERE description IS NOT NULL", as: {Int64, String}).each do |(id, text)|
          text_id = ids[text] ||= put_text(conn, text)
          conn.exec("UPDATE assets SET description_id = ? WHERE id = ?", text_id, id)
        end
        lost = conn.scalar(<<-SQL).as(Int64)
          SELECT COUNT(*) FROM assets a LEFT JOIN texts t ON t.id = a.description_id
          WHERE a.description IS NOT t.text
        SQL
        raise "moving descriptions into texts left #{lost} different; the store is unchanged" unless lost == 0
        conn.exec("ALTER TABLE assets DROP COLUMN description")
      end
      if columns.has_key?("generation")
        conn.exec("INSERT INTO recipe_legacy (asset_id, generation) " \
                  "SELECT id, generation FROM assets WHERE generation IS NOT NULL")
        lost = conn.scalar(<<-SQL).as(Int64)
          SELECT COUNT(*) FROM assets a LEFT JOIN recipe_legacy l ON l.asset_id = a.id
          WHERE a.generation IS NOT l.generation
        SQL
        raise "moving generation records left #{lost} different; the store is unchanged" unless lost == 0
        conn.exec("ALTER TABLE assets DROP COLUMN generation")
      end
      # Stores opened by 0.13 before its release lack the cost's basis.
      conn.exec("ALTER TABLE recipes ADD COLUMN cost_basis TEXT") unless table_columns(conn, "recipes").has_key?("cost_basis")
      conn.exec("CREATE INDEX IF NOT EXISTS idx_assets_description ON assets(description_id) WHERE description_id IS NOT NULL")
    end

    # 0.14 keeps what a recipe's provider was sent, and the named wordings
    # that went into it, in place of 0.13's prompt fields (DESIGN-recipes.md).
    # A wording's version becomes the start of its words' SHA-256 and its
    # field its kind; every row is copied with its id, so recipes still point
    # at it, and the copy is compared with the original before the original
    # goes. Each step's prompt is what 0.13 said was sent: its prompt_sent,
    # or else a picture's fields joined in 0.13's order; speech's text, with
    # its style the instructions; a text step's description, with its
    # instructions. Every named field becomes one of its wordings. Each step
    # is compared with its fields before a column goes; otherwise this
    # raises and the open's transaction leaves the store as it was. The
    # fields stay, in recipe_fields. One way. Runs with foreign keys off,
    # inside setup_schema's transaction; true when it rebuilt, so
    # setup_schema checks the references afterwards.
    private def migrate_prompts(conn : ::DB::Connection) : Bool
      return false unless table_columns(conn, "recipes").has_key?("sent_as_joined")
      migrate_wordings(conn)
      conn.exec("ALTER TABLE recipes ADD COLUMN prompt_id INTEGER REFERENCES texts(id)")
      conn.exec("ALTER TABLE recipes ADD COLUMN instructions_id INTEGER REFERENCES texts(id)")

      fields = Hash({Int64, Int32}, Hash(String, {Int64, String, Int64?})).new
      conn.query_all(<<-SQL, as: {Int64, Int32, String, Int64, String, Int64?}).each do |(asset, step, field, text_id, text, named)|
        SELECT f.asset_id, f.step, f.field, f.text_id, t.text, f.named_id FROM recipe_fields f JOIN texts t ON t.id = f.text_id
      SQL
        (fields[{asset, step}] ||= {} of String => {Int64, String, Int64?})[field] = {text_id, text, named}
      end
      steps = conn.query_all("SELECT asset_id, step, form, sent_as_joined, prompt_sent_id FROM recipes",
        as: {Int64, Int32, String, Int32, Int64?})
      expected = {} of {Int64, Int32} => {String?, String?}
      steps.each do |(asset, step, form, _, sent_id)|
        own = fields[{asset, step}]? || {} of String => {Int64, String, Int64?}
        words = ->(field : String) { own[field]?.try(&.[1]) }
        prompt, instructions = case form
                               when "picture"
                                 sent = sent_id.try { |id| conn.scalar("SELECT text FROM texts WHERE id = ?", id).as(String) }
                                 joined = PICTURE_FIELDS_013.compact_map { |field| words.call(field).presence }.join(" ")
                                 {sent || joined.presence, nil}
                               when "speech" then {words.call("text"), words.call("style")}
                               when "text"   then {words.call("description"), words.call("instructions")}
                               else               {nil, nil}
                               end
        expected[{asset, step}] = {prompt, instructions}
        conn.exec("UPDATE recipes SET prompt_id = ?, instructions_id = ? WHERE asset_id = ? AND step = ?",
          prompt.try { |text| put_text(conn, text) }, instructions.try { |text| put_text(conn, text) }, asset, step)
        order = form == "picture" ? PICTURE_FIELDS_013 : %w[style instructions text description]
        named = own.to_a.sort_by { |(field, _)| order.index(field) || order.size }.compact_map { |(_, row)| row[2] }
        named.each_with_index do |named_id, position|
          conn.exec("INSERT INTO recipe_wordings (asset_id, step, position, named_id) VALUES (?, ?, ?, ?)",
            asset, step, position, named_id)
        end
      end

      read = conn.query_all(<<-SQL, as: {Int64, Int32, String?, String?}).to_h { |(asset, step, prompt, instructions)| { {asset, step}, {prompt, instructions} } }
        SELECT r.asset_id, r.step, p.text, i.text FROM recipes r
        LEFT JOIN texts p ON p.id = r.prompt_id LEFT JOIN texts i ON i.id = r.instructions_id
      SQL
      lost = expected.count { |key, sent| read[key]? != sent }
      lost += steps.count { |(asset, step, _, _, sent_id)| sent_id && conn.scalar("SELECT prompt_id FROM recipes WHERE asset_id = ? AND step = ?", asset, step) != sent_id }
      lost += conn.scalar(<<-SQL).as(Int64)
        SELECT (SELECT COUNT(*) FROM recipe_fields WHERE named_id IS NOT NULL)
             - (SELECT COUNT(*) FROM recipe_fields f JOIN recipe_wordings w
                ON w.asset_id = f.asset_id AND w.step = f.step AND w.named_id = f.named_id)
      SQL
      raise "moving #{steps.size} recipe steps to what was sent left #{lost} different; the store is unchanged" unless lost == 0
      conn.exec("ALTER TABLE recipes DROP COLUMN sent_as_joined")
      conn.exec("ALTER TABLE recipes DROP COLUMN prompt_sent_id")
      true
    end

    # Rebuilds named_texts with versions from their words and fields as
    # kinds (from 0.13.1's, or 0.13.0's without purposes).
    private def migrate_wordings(conn : ::DB::Connection) : Nil
      columns = table_columns(conn, "named_texts")
      return if columns.has_key?("kind")
      purpose = columns.has_key?("purpose") ? "n.purpose" : "''"
      rows = conn.query_all(<<-SQL, as: {Int64, String, String, String, String, Int32, Int64, String})
        SELECT n.id, n.field, n.owner, n.name, #{purpose}, n.version, n.text_id, t.hash
        FROM named_texts n JOIN texts t ON t.id = n.text_id
      SQL
      rows.group_by { |row| {row[1], row[2], row[3], row[4]} }.each do |(field, owner, name, purpose_of), group|
        versions = group.map(&.[7][0, Recipe::VERSION_SIZE])
        unless versions.uniq.size == versions.size
          raise "two wordings of #{Recipe::Wording.handle(owner, name, purpose_of)} (#{field}) have the same version; " \
                "the store is unchanged"
        end
      end
      schema = RECIPE_SCHEMAS.split(";").find!(&.includes?("named_texts ("))
      conn.exec(schema.sub("IF NOT EXISTS named_texts", "named_texts_migrated"))
      rows.each do |(id, field, owner, name, purpose_of, _, text_id, hash)|
        conn.exec("INSERT INTO named_texts_migrated (id, kind, owner, name, purpose, version, text_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
          id, field, owner, name, purpose_of, hash[0, Recipe::VERSION_SIZE], text_id)
      end
      lost = conn.scalar(<<-SQL).as(Int64)
        SELECT (SELECT COUNT(*) FROM named_texts) - (SELECT COUNT(*) FROM named_texts_migrated)
             + (SELECT COUNT(*) FROM named_texts n LEFT JOIN named_texts_migrated m ON m.id = n.id
                LEFT JOIN texts t ON t.id = n.text_id
                WHERE m.kind IS NOT n.field OR m.owner IS NOT n.owner OR m.name IS NOT n.name
                   OR m.purpose IS NOT #{purpose} OR m.text_id IS NOT n.text_id
                   OR m.version IS NOT substr(t.hash, 1, #{Recipe::VERSION_SIZE}))
      SQL
      raise "copying named texts to version them by their words left #{lost} different; the store is unchanged" unless lost == 0
      conn.exec("DROP TABLE named_texts")
      conn.exec("ALTER TABLE named_texts_migrated RENAME TO named_texts")
    end
  end
end
