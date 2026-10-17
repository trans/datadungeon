require "json"
require "./recipe"

module DataDungeon
  # A tag every app means the same by (DESIGN-types.md): its name, its
  # title for people ("Art Style"), the label its values take in a key
  # (empty when its values say what they are), its kind (`scale` for an
  # ordered one, empty for plain values), what it means, and its values.
  struct VocabularyTag
    include JSON::Serializable

    getter name : String
    getter title : String
    getter label : String
    getter kind : String
    getter description : String
    getter values : Array(VocabularyValue)

    def initialize(@name, @title, @label, @kind, @description, @values)
    end
  end

  # One value of a shared tag: its title for people ("16-Bit Pixel"), what
  # counts as it, the family a filter on it finds it by (`pixel` for
  # `pixel-16`; empty for none), and DataDungeon's words for it, where it
  # has them: an art style's, for a picture whose app takes its style from
  # them (`dd:silver-comic@<version>`), and a rating's, what's suitable for
  # it (`dd:pg@<version>`).
  struct VocabularyValue
    include JSON::Serializable

    getter value : String
    getter title : String
    getter description : String
    getter family : String
    getter wording : Recipe::Wording?

    def initialize(@value, @title, @description, @family, @wording)
    end
  end

  class DB
    # The owner of DataDungeon's own wordings, the art styles' and the
    # ratings' words.
    VOCABULARY_OWNER = "dd"

    VOCABULARY_SCHEMAS = <<-SQL
      CREATE TABLE IF NOT EXISTS vocabulary_tags (
        name        TEXT PRIMARY KEY,
        title       TEXT NOT NULL,
        label       TEXT NOT NULL DEFAULT '',
        kind        TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL
      ) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS vocabulary_values (
        tag         TEXT NOT NULL REFERENCES vocabulary_tags(name),
        value       TEXT NOT NULL,
        title       TEXT NOT NULL,
        description TEXT NOT NULL,
        family      TEXT NOT NULL DEFAULT '',
        wording_id  INTEGER REFERENCES named_texts(id),
        position    INTEGER NOT NULL,
        PRIMARY KEY (tag, value)
      ) WITHOUT ROWID
    SQL

    # The shared vocabulary as this release agrees it. It grows by
    # agreement, in a DataDungeon release: every store opened read-write
    # takes it as it is here. A value's words are DataDungeon's wording of
    # it, of the tag's kind of wording; changed words are the wording's next
    # version, and recipes keep the one they were made with.
    VOCABULARY = [
      {name: "art-style", title: "Art Style", label: "", kind: "", description: "how a picture is drawn or rendered",
       wording: "style", values: [
         {value: "golden-comic", title: "Golden Age Comic", description: "Golden Age comics", family: "",
          words: "Golden Age comic."},
         {value: "silver-comic", title: "Silver Age Comic", description: "Silver Age comics", family: "",
          words: "Silver Age comic."},
         {value: "modern-comic", title: "Modern Comic", description: "modern comics: detailed inks, digital coloring",
          family: "", words: "Modern comic book art, detailed inks, digital coloring."},
         {value: "dark-manga", title: "Dark Manga", description: "dark manga", family: "", words: "Dark manga."},
         {value: "fantasy", title: "Fantasy Cover", description: "classic fantasy cover art, slightly painterly",
          family: "", words: "Classic fantasy cover art, slightly painterly."},
         {value: "photorealism", title: "Photorealism",
          description: "looks real, however it was made, near-real 3D included", family: "", words: "Photorealistic."},
         {value: "pixel", title: "Pixel",
          description: "pixel art of no stated tier; a filter on pixel finds every pixel tier", family: "",
          words: "Pixel art."},
         {value: "pixel-32", title: "32-Bit Pixel",
          description: "detailed late 16-bit / early 32-bit pixel art, Silicon Circus's usual", family: "pixel",
          words: "Detailed late 16-bit / early 32-bit pixel art."},
         {value: "pixel-16", title: "16-Bit Pixel", description: "chunky early to mid 16-bit pixel art", family: "pixel",
          words: "Chunky early to mid 16-bit pixel art."},
         {value: "pixel-8", title: "8-Bit Pixel", description: "the coarsest pixel art", family: "pixel",
          words: "Coarse 8-bit pixel art."},
         {value: "3d-cartoon", title: "3D Cartoon",
          description: "3D that looks sculpted and lit, rounded and exaggerated: the Toy Story middle ground",
          family: "", words: "3D cartoon, sculpted and lit, rounded and exaggerated."},
         {value: "watercolor", title: "Storybook Watercolor",
          description: "storybook watercolour: soft washes, fine ink outlines", family: "",
          words: "Storybook watercolor, soft washes, fine ink outlines."},
         {value: "painted-animation", title: "Painted Animation",
          description: "hand-painted animation backgrounds: lush colour, soft cel shading", family: "",
          words: "Hand-painted animation, lush color, soft cel shading."},
         {value: "ascii", title: "ASCII", description: "text-mode art, ASCII made dynamic and modern", family: "",
          words: "ASCII art."},
       ]},
      {name: "rating", title: "Rating", label: "", kind: "scale",
       description: "who a thing is suitable for, the same in every app", wording: "rating", values: [
         {value: "g", title: "G", description: "general audiences", family: "",
          words: "Family-friendly and wholesome, suitable for all ages."},
         {value: "pg", title: "PG", description: "parental guidance", family: "",
          words: "Suitable for older children: mild peril and action, kept clean."},
         {value: "r", title: "R", description: "restricted", family: "",
          words: "For mature audiences: violence, blood and risqué scenes may be shown."},
         {value: "x", title: "X", description: "adults only", family: "", words: "For adults only."},
       ]},
    ]

    # Takes the vocabulary as this release has it, inside setup_schema's
    # transaction. Values a later release drops are kept.
    private def seed_vocabulary(conn : ::DB::Connection) : Nil
      # A store opened by the first 0.14 build (4426581) named a value's words style_id.
      if conn.query_one?("SELECT 1 FROM pragma_table_info('vocabulary_values') WHERE name = 'style_id'", as: Int32)
        conn.exec("ALTER TABLE vocabulary_values RENAME COLUMN style_id TO wording_id")
      end
      VOCABULARY_SCHEMAS.split(";").each { |sql| conn.exec(sql.strip) unless sql.strip.empty? }
      VOCABULARY.each do |tag|
        conn.exec(<<-SQL, tag[:name], tag[:title], tag[:label], tag[:kind], tag[:description])
          INSERT INTO vocabulary_tags (name, title, label, kind, description) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT (name) DO UPDATE SET title = excluded.title, label = excluded.label, kind = excluded.kind,
            description = excluded.description
        SQL
        tag[:values].each_with_index do |value, position|
          wording_id = put_named(conn, tag[:wording], VOCABULARY_OWNER, value[:value], "", put_text(conn, value[:words]), owned: true)
          conn.exec(<<-SQL, tag[:name], value[:value], value[:title], value[:description], value[:family], wording_id, position)
            INSERT INTO vocabulary_values (tag, value, title, description, family, wording_id, position)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (tag, value) DO UPDATE SET title = excluded.title, description = excluded.description,
              family = excluded.family, wording_id = excluded.wording_id, position = excluded.position
          SQL
        end
      end
    end

    # The shared tags by name, each with its values in the agreed order.
    def vocabulary : Array(VocabularyTag)
      values = Hash(String, Array(VocabularyValue)).new { |hash, tag| hash[tag] = [] of VocabularyValue }
      @db.query_all(<<-SQL, as: {String, String, String, String, String, String?, String?, String?}).each do |(tag, value, title, description, family, kind, version, text)|
        SELECT v.tag, v.value, v.title, v.description, v.family, n.kind, n.version, t.text
        FROM vocabulary_values v
        LEFT JOIN named_texts n ON n.id = v.wording_id
        LEFT JOIN texts t ON t.id = n.text_id
        ORDER BY v.tag, v.position, v.value
      SQL
        wording = Recipe::Wording.new(kind, Recipe::Wording.handle(VOCABULARY_OWNER, value, "", version), text) if kind && text
        values[tag] << VocabularyValue.new(value, title, description, family, wording)
      end
      @db.query_all("SELECT name, title, label, kind, description FROM vocabulary_tags ORDER BY name",
        as: {String, String, String, String, String}).map do |(name, title, label, kind, description)|
        VocabularyTag.new(name, title, label, kind, description, values[name]? || [] of VocabularyValue)
      end
    end

    # DataDungeon's words for an art style, for an app that takes its
    # style from them: `dd:silver-comic@<version>`, "Silver Age comic.". An
    # app may word its styles its own way instead (`overlore:silver-comic`).
    # Raises for a value that isn't a standard art style.
    def style_text(art_style : String) : Recipe::Wording
      vocabulary_text("art-style", art_style) || raise ArgumentError.new("#{art_style.inspect} isn't a standard art style (vocabulary)")
    end

    # DataDungeon's words for a rating, the same for every form: what's
    # suitable for it, `dd:pg@<version>`, "Suitable for older children: …".
    # A picture takes them with its rules. Raises for a value that isn't a
    # rating.
    def rating_text(rating : String) : Recipe::Wording
      vocabulary_text("rating", rating) || raise ArgumentError.new("#{rating.inspect} isn't a rating (vocabulary)")
    end

    private def vocabulary_text(tag : String, value : String) : Recipe::Wording?
      row = @db.query_one?(<<-SQL, tag, value, as: {String, String, String})
        SELECT n.kind, n.version, t.text FROM vocabulary_values v
        JOIN named_texts n ON n.id = v.wording_id JOIN texts t ON t.id = n.text_id
        WHERE v.tag = ? AND v.value = ?
      SQL
      row.try { |(kind, version, words)| Recipe::Wording.new(kind, Recipe::Wording.handle(VOCABULARY_OWNER, value, "", version), words) }
    end
  end
end
