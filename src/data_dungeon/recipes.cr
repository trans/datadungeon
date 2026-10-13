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
    # numbered in the order its wordings were first seen. A recipe is a row
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
        version INTEGER NOT NULL,
        text_id INTEGER NOT NULL REFERENCES texts(id),
        UNIQUE (field, owner, name, version),
        UNIQUE (field, owner, name, text_id)
      );
      CREATE TABLE IF NOT EXISTS recipes (
        asset_id       INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        step           INTEGER NOT NULL,
        form           TEXT NOT NULL,
        settings_id    INTEGER REFERENCES recipe_settings(id),
        seed           INTEGER,
        cost           REAL,
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
    # `owner:name@version`; nil when it has none.
    def recipe(id : Int64) : Recipe?
      rows = @db.query_all(<<-SQL, id, as: {Int32, String, String?, Int64?, Float64?, String?, Int32, String?, String?})
        SELECT r.step, r.form, s.settings, r.seed, r.cost, r.generated_at, r.sent_as_joined, t.text, r.refs
        FROM recipes r
        LEFT JOIN recipe_settings s ON s.id = r.settings_id
        LEFT JOIN texts t ON t.id = r.prompt_sent_id
        WHERE r.asset_id = ? ORDER BY r.step
      SQL
      return nil if rows.empty?

      fields = Hash(Int32, Hash(String, Recipe::Text)).new { |hash, step| hash[step] = {} of String => Recipe::Text }
      @db.query(<<-SQL, id) do |rs|
        SELECT f.step, f.field, t.text, n.owner, n.name, n.version
        FROM recipe_fields f
        JOIN texts t ON t.id = f.text_id
        LEFT JOIN named_texts n ON n.id = f.named_id
        WHERE f.asset_id = ?
      SQL
        rs.each do
          step, field, text = rs.read(Int32), rs.read(String), rs.read(String)
          owner, name, version = rs.read(String?), rs.read(String?), rs.read(Int32?)
          fields[step][field] = Recipe::Text.new(text, owner && "#{owner}:#{name}@#{version}")
        end
      end

      steps = rows.map do |(step, form, settings, seed, cost, made, as_joined, sent, refs)|
        order = Recipe::FIELDS[form]? || [] of String
        own = fields[step]?.try(&.to_a.sort_by { |(field, _)| order.index(field) || order.size }.to_h) ||
              {} of String => Recipe::Text
        recipe = Recipe.new(form,
          settings: settings.try { |json| JSON.parse(json).as_h } || {} of String => JSON::Any,
          fields: own, seed: seed, cost: cost,
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
    # ones included, oldest first: `with_text("style", "overlore:silver")`
    # for any of its wordings, `"overlore:silver@2"` for one.
    def with_text(field : String, name : String) : Array(Int64)
      owner, base, version = Recipe::Text.new("", name).handle.not_nil!
      sql = "SELECT DISTINCT f.asset_id FROM named_texts n JOIN recipe_fields f ON f.named_id = n.id " \
            "WHERE n.field = ? AND n.owner = ? AND n.name = ?"
      args = [field, owner, base] of ::DB::Any
      if version
        sql += " AND n.version = ?"
        args << version
      end
      @db.query_all("#{sql} ORDER BY f.asset_id", args: args, as: Int64)
    end

    # The named texts an owner has written for a field: {name, version,
    # text}, by name and version.
    def named_texts(field : String, owner : String) : Array({String, Int32, String})
      @db.query_all(<<-SQL, field, owner, as: {String, Int32, String})
        SELECT n.name, n.version, t.text FROM named_texts n JOIN texts t ON t.id = n.text_id
        WHERE n.field = ? AND n.owner = ? ORDER BY n.name, n.version
      SQL
    end

    # Adds an asset's recipe rows; the asset has none.
    private def write_recipe(conn : ::DB::Connection, asset_id : Int64, recipe : Recipe) : Nil
      steps = recipe.steps.empty? ? [recipe] : recipe.steps
      steps.each_with_index do |step, i|
        sent = step.prompt_sent
        as_joined = !sent.nil? && step.form == "picture" && sent == step.joined
        conn.exec(<<-SQL,
          INSERT INTO recipes (asset_id, step, form, settings_id, seed, cost, generated_at,
                               sent_as_joined, prompt_sent_id, refs)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
          asset_id, i, step.form, put_settings(conn, step.settings), step.seed, step.cost,
          step.generated_at.try(&.to_utc.to_s(TIME_FORMAT)), as_joined ? 1 : 0,
          sent && !as_joined ? put_text(conn, sent) : nil,
          step.references.empty? ? nil : step.references.to_json)
        step.fields.each do |field, words|
          text_id = put_text(conn, words.text)
          named_id = words.handle.try { |(owner, name, version)| put_named(conn, field, owner, name, version, text_id) }
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

    # The named_texts row for this wording of an owner's name. A wording
    # seen before keeps its version; a new one is the next, and only the
    # owner adds one.
    private def put_named(conn : ::DB::Connection, field : String, owner : String, name : String,
                          given : Int32?, text_id : Int64) : Int64
      row = conn.query_one?("SELECT id, version FROM named_texts WHERE field = ? AND owner = ? AND name = ? AND text_id = ?",
        field, owner, name, text_id, as: {Int64, Int32})
      id, version = row || begin
        unless @consumer == owner
          raise ArgumentError.new("#{owner}:#{name} is #{owner}'s: only it adds a wording to it " \
                                  "(this DB's consumer is #{@consumer.inspect})")
        end
        next_version = conn.scalar("SELECT ifnull(max(version), 0) + 1 FROM named_texts WHERE field = ? AND owner = ? AND name = ?",
          field, owner, name).as(Int64).to_i32
        conn.exec("INSERT INTO named_texts (field, owner, name, version, text_id) VALUES (?, ?, ?, ?, ?)",
          field, owner, name, next_version, text_id)
        {conn.scalar("SELECT last_insert_rowid()").as(Int64), next_version}
      end
      if given && given != version
        raise ArgumentError.new("this #{field} wording of #{owner}:#{name} is version #{version}, not #{given}")
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
    end
  end
end
