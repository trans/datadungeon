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
    # `rating`, ...); its version is the start of its words' SHA-256
    # (Recipe::VERSION_SIZE), so it names the same words in every store. A
    # recipe is a row per step (0 for a single recipe), with what its
    # provider was sent, and a row per named wording it used. Before 0.13 an
    # asset's `generation` was free-form JSON on its row; it stays readable
    # in recipe_legacy until its app gives it a recipe.
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
        version TEXT NOT NULL,
        text_id INTEGER NOT NULL REFERENCES texts(id),
        UNIQUE (kind, owner, name, version)
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
    # `owner:name@version`; nil when it has none.
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
      @db.query_all(<<-SQL, id, as: {Int32, String, String, String, String, String}).each do |(step, kind, owner, name, version, text)|
        SELECT w.step, n.kind, n.owner, n.name, n.version, t.text
        FROM recipe_wordings w
        JOIN named_texts n ON n.id = w.named_id
        JOIN texts t ON t.id = n.text_id
        WHERE w.asset_id = ? ORDER BY w.step, w.position
      SQL
        wordings[step] << Recipe::Wording.new(kind, Recipe::Wording.handle(owner, name, version), text)
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

    # Names wordings a stored recipe's step was sent but doesn't name, for
    # an app naming its words after the fact (its rating's words, on
    # pictures made before it named them); `step` is 0 for a recipe without
    # steps. Only the new wordings are checked, as a new recipe's are: their
    # words in the step's prompt or instructions, word for word, and theirs
    # to add. What the step names already stays as it was stored, and a
    # wording it names already is skipped. Returns how many were added.
    def add_wordings(id : Int64, wordings : Array(Recipe::Wording), step : Int32 = 0) : Int32
      writable!
      stored = recipe(id).try { |whole| whole.steps.empty? ? (whole if step == 0) : whole.steps[step]? }
      raise ArgumentError.new("Asset #{id} has no recipe step #{step}") unless stored
      named = stored.wordings.map { |wording| wording_key(wording) }
      added = wordings.uniq { |wording| wording_key(wording) }.reject { |wording| named.includes?(wording_key(wording)) }
      Recipe.new(stored.form, prompt: stored.prompt, instructions: stored.instructions, wordings: added).check
      check_wordings(added)
      return 0 if added.empty?
      write_transaction do |conn|
        position = conn.scalar("SELECT ifnull(max(position) + 1, 0) FROM recipe_wordings WHERE asset_id = ? AND step = ?",
          id, step).as(Int64)
        added.each_with_index do |wording, i|
          owner, name, _ = wording.handle
          named_id = put_named(conn, wording.kind, owner, name, put_text(conn, wording.text))
          conn.exec("INSERT INTO recipe_wordings (asset_id, step, position, named_id) VALUES (?, ?, ?, ?)",
            id, step, position + i, named_id)
        end
      end
      @indexer.try(&.enqueue_asset(id))
      added.size
    end

    # A wording as the store tells it apart: its kind, owner, name and
    # version.
    private def wording_key(wording : Recipe::Wording) : {String, String, String, String}
      owner, name, _ = wording.handle
      {wording.kind, owner, name, Recipe.version(wording.text)}
    end

    # The assets whose recipes used a named wording of a kind, retired ones
    # included, oldest first: `with_text("style", "overlore:silver-comic")`
    # for any of its wordings, `"overlore:silver-comic@3f9a2c71b0"` for one;
    # `with_text("rating", "dd:pg")` for everything given DataDungeon's
    # words for a rating.
    def with_text(kind : String, name : String) : Array(Int64)
      sql, args = using_text(kind, name)
      @db.query_all("SELECT DISTINCT asset_id FROM (#{sql}) ORDER BY asset_id", args: args, as: Int64)
    end

    # SQL selecting the `asset_id` of every recipe using a named wording of
    # a kind (any version; `@version` for one wording), and its arguments.
    private def using_text(kind : String, name : String) : {String, Array(::DB::Any)}
      owner, base, version = Recipe::Wording.new(kind, name, "").handle
      sql = "SELECT w.asset_id FROM named_texts n JOIN recipe_wordings w ON w.named_id = n.id " \
            "WHERE n.kind = ? AND n.owner = ? AND n.name = ?"
      args = [kind, owner, base] of ::DB::Any
      if version
        sql += " AND n.version = ?"
        args << version
      end
      {sql, args}
    end

    # The wordings an owner has of a kind: {name, version, text}, by name,
    # oldest first.
    def named_texts(kind : String, owner : String) : Array({String, String, String})
      @db.query_all(<<-SQL, kind, owner, as: {String, String, String})
        SELECT n.name, n.version, t.text FROM named_texts n JOIN texts t ON t.id = n.text_id
        WHERE n.kind = ? AND n.owner = ? ORDER BY n.name, n.id
      SQL
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
          owner, name, _ = wording.handle
          named_id = put_named(conn, wording.kind, owner, name, put_text(conn, wording.text))
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

    # The named_texts row for this wording of an owner's name, its version
    # the start of its words' SHA-256. Only the owner adds a
    # wording (DataDungeon adds its own, the vocabulary's words, with
    # `owned: true`); two wordings of one name whose versions are the same
    # (a 1 in a trillion chance) are refused rather than confused.
    private def put_named(conn : ::DB::Connection, kind : String, owner : String, name : String,
                          text_id : Int64, owned : Bool = false) : Int64
      version = conn.scalar("SELECT hash FROM texts WHERE id = ?", text_id).as(String)[0, Recipe::VERSION_SIZE]
      written = Recipe::Wording.handle(owner, name, version)
      row = conn.query_one?(<<-SQL, kind, owner, name, version, as: {Int64, Int64})
        SELECT id, text_id FROM named_texts WHERE kind = ? AND owner = ? AND name = ? AND version = ?
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
      conn.exec("INSERT INTO named_texts (kind, owner, name, version, text_id) VALUES (?, ?, ?, ?, ?)",
        kind, owner, name, version, text_id)
      conn.scalar("SELECT last_insert_rowid()").as(Int64)
    end

    # Whether a store has these words as this wording: the same kind and
    # name, any version.
    private def wording?(kind : String, owner : String, name : String, text : String) : Bool
      !@db.query_one?(<<-SQL, kind, owner, name, text, as: Int32).nil?
        SELECT 1 FROM named_texts n JOIN texts t ON t.id = n.text_id
        WHERE n.kind = ? AND n.owner = ? AND n.name = ? AND t.text = ?
      SQL
    end

    # The store's checks on a recipe's wordings, before anything is
    # written. A store is its owner's: a wording it hasn't seen is its
    # consumer's to add, and a `dd` one is DataDungeon's words already.
    private def check_wordings(recipe : Recipe) : Nil
      check_wordings((recipe.steps.empty? ? [recipe] : recipe.steps).flat_map(&.wordings))
    end

    private def check_wordings(wordings : Array(Recipe::Wording)) : Nil
      wordings.each do |wording|
        owner, name, _ = wording.handle
        next if wording?(wording.kind, owner, name, wording.text)
        if owner == VOCABULARY_OWNER
          raise ArgumentError.new("#{wording.name} isn't DataDungeon's words: a dd wording comes from the " \
                                  "store (db.rating_text)")
        end
        unless owner == @consumer
          raise ArgumentError.new("#{wording.name} is #{owner}'s: a store adds its consumer's own wordings " \
                                  "(this DB's consumer is #{@consumer.inspect})")
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
    # raises and the open's transaction leaves the store as it was; the
    # fields go after (setup_schema). One way. Runs with foreign keys off,
    # inside setup_schema's transaction; true when it rebuilt, so
    # setup_schema checks the references afterwards.
    private def migrate_prompts(conn : ::DB::Connection) : Bool
      return false unless table_columns(conn, "recipes").has_key?("sent_as_joined")
      migrate_wordings(conn, fields_name: true)
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

    # Rebuilds named_texts in 0.15's shape, from 0.13's (each wording's
    # field and a number for its version, with a purpose since 0.13.1) or
    # 0.14's (with a purpose): its kind, owner, name, and a version from its
    # words. Purposes went in 0.15, since what they told apart was framing
    # (Thomas, 2026-10-17): a wording with one that nothing names any more
    # isn't kept, so no version is left over for it, and one a recipe still
    # names becomes a version of its plain name, its words and version
    # unchanged. Every other row is copied with its id, so recipes still
    # point at it, and the copy is compared with the original before the
    # original goes. Two wordings that would be one name's same version (the
    # same words under two purposes, or two versions whose words' hashes
    # start alike) raise, and the open's transaction leaves the store as it
    # was. `fields_name:` when a 0.13 store's recipes are read from its
    # prompt fields after this, so what they name is in use. True when it
    # rebuilt.
    private def migrate_wordings(conn : ::DB::Connection, fields_name : Bool = false) : Bool
      columns = table_columns(conn, "named_texts")
      return false if columns.has_key?("kind") && !columns.has_key?("purpose")
      kind = columns.has_key?("kind") ? "n.kind" : "n.field"
      # What names a wording: a recipe, the vocabulary, or 0.13's prompt
      # fields while they're still to be read.
      users = {"recipe_wordings" => "named_id", "vocabulary_values" => "wording_id"}
      users["recipe_fields"] = "named_id" if fields_name
      named = users.compact_map do |table, column|
        "EXISTS (SELECT 1 FROM #{table} u WHERE u.#{column} = n.id)" unless table_columns(conn, table).empty?
      end
      unused = columns.has_key?("purpose") ? "n.purpose != '' AND NOT (#{named.empty? ? "0" : named.join(" OR ")})" : "0"
      rows = conn.query_all(<<-SQL, as: {Int64, String, String, String, Int64, String, Bool})
        SELECT n.id, #{kind}, n.owner, n.name, n.text_id, t.hash, #{unused}
        FROM named_texts n JOIN texts t ON t.id = n.text_id
      SQL
      dropped, rows = rows.partition(&.[6])
      rows.group_by { |row| {row[1], row[2], row[3]} }.each do |(of_kind, owner, name), group|
        versions = group.map(&.[5][0, Recipe::VERSION_SIZE])
        unless versions.uniq.size == versions.size
          raise "two wordings of #{Recipe::Wording.handle(owner, name)} (#{of_kind}) would have the same version; " \
                "the store is unchanged"
        end
      end
      schema = RECIPE_SCHEMAS.split(";").find!(&.includes?("named_texts ("))
      conn.exec(schema.sub("IF NOT EXISTS named_texts", "named_texts_migrated"))
      rows.each do |(id, of_kind, owner, name, text_id, hash, _)|
        conn.exec("INSERT INTO named_texts_migrated (id, kind, owner, name, version, text_id) VALUES (?, ?, ?, ?, ?, ?)",
          id, of_kind, owner, name, hash[0, Recipe::VERSION_SIZE], text_id)
      end
      # 0.14's versions are already their words'.
      kept = columns.has_key?("kind") ? "OR m.version IS NOT n.version" : ""
      lost = conn.scalar(<<-SQL, dropped.size).as(Int64)
        SELECT (SELECT COUNT(*) FROM named_texts) - ? - (SELECT COUNT(*) FROM named_texts_migrated)
             + (SELECT COUNT(*) FROM named_texts n JOIN named_texts_migrated m ON m.id = n.id
                LEFT JOIN texts t ON t.id = n.text_id
                WHERE m.kind IS NOT #{kind} OR m.owner IS NOT n.owner OR m.name IS NOT n.name
                   OR m.text_id IS NOT n.text_id OR m.version IS NOT substr(t.hash, 1, #{Recipe::VERSION_SIZE}) #{kept})
      SQL
      lost += 1 unless conn.query_all("SELECT id FROM named_texts_migrated ORDER BY id", as: Int64) == rows.map(&.[0]).sort
      raise "copying named texts to version them by their words left #{lost} different; the store is unchanged" unless lost == 0
      conn.exec("DROP TABLE named_texts")
      conn.exec("ALTER TABLE named_texts_migrated RENAME TO named_texts")
      true
    end
  end
end
