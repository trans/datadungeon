require "digest/sha256"
require "json"
require "./recipe"

module DataDungeon
  class DB
    # Every wording, an asset's description or a recipe's prompt field, named
    # or not, is one row, stored once (DESIGN-recipes.md).
    TEXTS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS texts (
        id   INTEGER PRIMARY KEY,
        hash TEXT NOT NULL UNIQUE,
        text TEXT NOT NULL
      )
    SQL

    # Settings are stored once by hash, as canonical JSON (keys sorted).
    # A named text is one wording of an owner's name for a prompt field,
    # with what it's for (its purpose, empty for none), numbered per name
    # and purpose in the order its wordings were first seen. A recipe is a row
    # per step (0 for a single recipe), and a row per prompt field it uses.
    # `sent_as_joined` says the provider was sent exactly the fields joined;
    # otherwise `prompt_sent_id` holds what it was sent, if that was given.
    # Before 0.13 an asset's `generation` was free-form JSON on its row; it
    # stays readable in recipe_legacy until its app gives it a recipe.
    RECIPE_SCHEMAS = <<-SQL
      CREATE TABLE IF NOT EXISTS recipe_settings (
        id       INTEGER PRIMARY KEY,
        hash     TEXT NOT NULL UNIQUE,
        settings TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS named_texts (
        id      INTEGER PRIMARY KEY,
        field   TEXT NOT NULL,
        owner   TEXT NOT NULL,
        name    TEXT NOT NULL,
        purpose TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL,
        text_id INTEGER NOT NULL REFERENCES texts(id),
        UNIQUE (field, owner, name, purpose, version),
        UNIQUE (field, owner, name, purpose, text_id)
      );
      CREATE TABLE IF NOT EXISTS recipes (
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
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS idx_recipes_settings ON recipes(settings_id);
      CREATE TABLE IF NOT EXISTS recipe_fields (
        asset_id INTEGER NOT NULL,
        step     INTEGER NOT NULL,
        field    TEXT NOT NULL,
        text_id  INTEGER NOT NULL REFERENCES texts(id),
        named_id INTEGER REFERENCES named_texts(id),
        PRIMARY KEY (asset_id, step, field),
        FOREIGN KEY (asset_id, step) REFERENCES recipes(asset_id, step) ON DELETE CASCADE
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS idx_recipe_fields_text ON recipe_fields(text_id);
      CREATE INDEX IF NOT EXISTS idx_recipe_fields_named ON recipe_fields(named_id) WHERE named_id IS NOT NULL;
      CREATE TABLE IF NOT EXISTS recipe_legacy (
        asset_id   INTEGER PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
        generation TEXT NOT NULL
      )
    SQL

    # The asset's recipe, steps and all, with each named text as
    # `owner:name@version` (`owner:name/purpose@version` with a purpose);
    # nil when it has none.
    def recipe(id : Int64) : Recipe?
      rows = @db.query_all(<<-SQL, id, as: {Int32, String, String?, Int64?, Float64?, String?, String?, Int32, String?, String?})
        SELECT r.step, r.form, s.settings, r.seed, r.cost, r.cost_basis, r.generated_at, r.sent_as_joined, t.text, r.refs
        FROM recipes r
        LEFT JOIN recipe_settings s ON s.id = r.settings_id
        LEFT JOIN texts t ON t.id = r.prompt_sent_id
        WHERE r.asset_id = ? ORDER BY r.step
      SQL
      return nil if rows.empty?

      fields = Hash(Int32, Hash(String, Recipe::Text)).new { |hash, step| hash[step] = {} of String => Recipe::Text }
      @db.query(<<-SQL, id) do |rs|
        SELECT f.step, f.field, t.text, n.owner, n.name, n.purpose, n.version
        FROM recipe_fields f
        JOIN texts t ON t.id = f.text_id
        LEFT JOIN named_texts n ON n.id = f.named_id
        WHERE f.asset_id = ?
      SQL
        rs.each do
          step, field, text = rs.read(Int32), rs.read(String), rs.read(String)
          owner, name, purpose, version = rs.read(String?), rs.read(String?), rs.read(String?), rs.read(Int32?)
          handle = owner && Recipe::Text.handle(owner, name.not_nil!, purpose.not_nil!, version)
          fields[step][field] = Recipe::Text.new(text, handle)
        end
      end

      steps = rows.map do |(step, form, settings, seed, cost, basis, made, as_joined, sent, refs)|
        order = Recipe::FIELDS[form]? || [] of String
        own = fields[step]?.try(&.to_a.sort_by { |(field, _)| order.index(field) || order.size }.to_h) ||
              {} of String => Recipe::Text
        recipe = Recipe.new(form,
          settings: settings.try { |json| JSON.parse(json).as_h } || {} of String => JSON::Any,
          fields: own, seed: seed, cost: cost, cost_basis: basis,
          generated_at: made.try { |time| Time.parse_utc(time, TIME_FORMAT) },
          references: refs.try { |json| Array(String).from_json(json) } || [] of String)
        sent ||= recipe.joined if as_joined == 1
        sent ? recipe.with_prompt_sent(sent) : recipe
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
      write_transaction do |conn|
        unless conn.query_one?("SELECT 1 FROM assets WHERE id = ?", id, as: Int32)
          raise ArgumentError.new("No asset #{id}")
        end
        if !replace && conn.query_one?("SELECT 1 FROM recipes WHERE asset_id = ? LIMIT 1", id, as: Int32)
          raise ArgumentError.new("Asset #{id} has a recipe; pass replace: true to replace it")
        end
        conn.exec("DELETE FROM recipes WHERE asset_id = ?", id) if replace # its fields go with it
        write_recipe(conn, id, recipe)
        conn.exec("DELETE FROM recipe_legacy WHERE asset_id = ?", id) if drop_generation
      end
      @indexer.try(&.enqueue_asset(id))
    end

    # The assets whose recipes use a named text in a prompt field, retired
    # ones included, oldest first: `with_text("style", "overlore:silver-comic")`
    # for any of its wordings, whatever their purpose,
    # `"overlore:silver-comic/figure"` for one purpose's, and
    # `"overlore:silver-comic/figure@2"` for one wording.
    def with_text(field : String, name : String) : Array(Int64)
      sql, args = using_text(field, name)
      @db.query_all("SELECT DISTINCT asset_id FROM (#{sql}) ORDER BY asset_id", args: args, as: Int64)
    end

    # SQL selecting the `asset_id` of every recipe using a named text in a
    # field (any purpose or wording; `/purpose` for one purpose, `@version`
    # for one wording), and its arguments.
    private def using_text(field : String, name : String) : {String, Array(::DB::Any)}
      owner, base, purpose, version = Recipe::Text.new("", name).handle.not_nil!
      sql = "SELECT f.asset_id FROM named_texts n JOIN recipe_fields f ON f.named_id = n.id " \
            "WHERE n.field = ? AND n.owner = ? AND n.name = ?"
      args = [field, owner, base] of ::DB::Any
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

    # The named texts an owner has written for a field: {name, version,
    # text}, the name with its `/purpose` if it has one, by name, purpose
    # and version.
    def named_texts(field : String, owner : String) : Array({String, Int32, String})
      @db.query_all(<<-SQL, field, owner, as: {String, String, Int32, String}).map do |(name, purpose, version, text)|
        SELECT n.name, n.purpose, n.version, t.text FROM named_texts n JOIN texts t ON t.id = n.text_id
        WHERE n.field = ? AND n.owner = ? ORDER BY n.name, n.purpose, n.version
      SQL
        {purpose.empty? ? name : "#{name}/#{purpose}", version, text}
      end
    end

    # Adds an asset's recipe rows; the asset has none.
    private def write_recipe(conn : ::DB::Connection, asset_id : Int64, recipe : Recipe) : Nil
      steps = recipe.steps.empty? ? [recipe] : recipe.steps
      steps.each_with_index do |step, i|
        sent = step.prompt_sent
        as_joined = !sent.nil? && step.form == "picture" && sent == step.joined
        conn.exec(<<-SQL,
          INSERT INTO recipes (asset_id, step, form, settings_id, seed, cost, cost_basis, generated_at,
                               sent_as_joined, prompt_sent_id, refs)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
          asset_id, i, step.form, put_settings(conn, step.settings), step.seed, step.cost, step.cost_basis,
          step.generated_at.try(&.to_utc.to_s(TIME_FORMAT)), as_joined ? 1 : 0,
          sent && !as_joined ? put_text(conn, sent) : nil,
          step.references.empty? ? nil : step.references.to_json)
        step.fields.each do |field, words|
          text_id = put_text(conn, words.text)
          named_id = words.handle.try { |(owner, name, purpose, version)| put_named(conn, field, owner, name, purpose, version, text_id) }
          conn.exec("INSERT INTO recipe_fields (asset_id, step, field, text_id, named_id) VALUES (?, ?, ?, ?, ?)",
            asset_id, i, field, text_id, named_id)
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

    # The named_texts row for this wording of an owner's name and purpose.
    # A wording seen before keeps its version; a new one is the next for
    # the name and purpose, and only the owner adds one.
    private def put_named(conn : ::DB::Connection, field : String, owner : String, name : String,
                          purpose : String, given : Int32?, text_id : Int64) : Int64
      row = conn.query_one?(<<-SQL, field, owner, name, purpose, text_id, as: {Int64, Int32})
        SELECT id, version FROM named_texts WHERE field = ? AND owner = ? AND name = ? AND purpose = ? AND text_id = ?
      SQL
      written = Recipe::Text.handle(owner, name, purpose)
      id, version = row || begin
        unless @consumer == owner
          raise ArgumentError.new("#{written} is #{owner}'s: only it adds a wording to it " \
                                  "(this DB's consumer is #{@consumer.inspect})")
        end
        next_version = conn.scalar(<<-SQL, field, owner, name, purpose).as(Int64).to_i32
          SELECT ifnull(max(version), 0) + 1 FROM named_texts WHERE field = ? AND owner = ? AND name = ? AND purpose = ?
        SQL
        conn.exec("INSERT INTO named_texts (field, owner, name, purpose, version, text_id) VALUES (?, ?, ?, ?, ?, ?)",
          field, owner, name, purpose, next_version, text_id)
        {conn.scalar("SELECT last_insert_rowid()").as(Int64), next_version}
      end
      if given && given != version
        raise ArgumentError.new("this #{field} wording of #{written} is version #{version}, not #{given}")
      end
      id
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

    # Named texts gained a purpose in 0.13.1. Their unique constraints
    # change with it, which SQLite can only do by building the table again:
    # every row is copied with its id, so recipes still point at it, and
    # the copy is compared with the original before the original goes. Runs
    # with foreign keys off, inside setup_schema's transaction; true when it
    # rebuilt, so setup_schema checks the references afterwards.
    private def migrate_named_texts(conn : ::DB::Connection) : Bool
      return false if table_columns(conn, "named_texts").has_key?("purpose")
      schema = RECIPE_SCHEMAS.split(";").find!(&.includes?("named_texts ("))
      conn.exec(schema.sub("IF NOT EXISTS named_texts", "named_texts_migrated"))
      conn.exec(<<-SQL)
        INSERT INTO named_texts_migrated (id, field, owner, name, purpose, version, text_id)
        SELECT id, field, owner, name, '', version, text_id FROM named_texts
      SQL
      lost = conn.scalar(<<-SQL).as(Int64)
        SELECT (SELECT COUNT(*) FROM named_texts) - (SELECT COUNT(*) FROM named_texts_migrated)
             + (SELECT COUNT(*) FROM named_texts n LEFT JOIN named_texts_migrated m ON m.id = n.id
                WHERE m.field IS NOT n.field OR m.owner IS NOT n.owner OR m.name IS NOT n.name
                   OR m.version IS NOT n.version OR m.text_id IS NOT n.text_id)
      SQL
      raise "copying named texts to add their purpose left #{lost} different; the store is unchanged" unless lost == 0
      conn.exec("DROP TABLE named_texts")
      conn.exec("ALTER TABLE named_texts_migrated RENAME TO named_texts")
      true
    end
  end
end
