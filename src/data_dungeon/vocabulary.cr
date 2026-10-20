require "json"
require "./recipe"

module DataDungeon
  # A tag every app means the same by (DESIGN-types.md): its name, its
  # title for people ("Rating"), the label its values take in a key
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

  # One value of a shared tag: its title for people ("PG"), what counts as
  # it, the family a filter on it finds it by (empty for none), and
  # DataDungeon's words for it, where it has them: a rating's, what's
  # suitable for it (`dd:pg@<version>`).
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

  # One of DataDungeon's asset types (DESIGN-types.md): what an asset is,
  # by its role, from one list every app shares, so another app can tell
  # what it is. An app tells its own kinds of one type apart with tags of
  # its own. A type is a role and the media its form, so a type can come in
  # several media: a drop can be a still picture or a moving one.
  struct StandardType
    include JSON::Serializable

    getter name : String
    getter title : String
    getter media : Array(String)
    getter description : String

    def initialize(@name, @title, @media, @description)
    end
  end

  class DB
    # DataDungeon's asset types, as agreed (Thomas with the apps,
    # 2026-10-13). The list changes in a release, by agreement, never by
    # an app. Apps move their own types onto it one at a time (rename_type);
    # once all have, register_type takes only these.
    STANDARD_TYPES = [
      # Pictures, still or moving
      StandardType.new("drop", "Drop", %w[image video], "a place, the set things stand in front of"),
      StandardType.new("plug", "Plug", %w[image video], "a framed moment, shown as it is: a comic panel, a hero shot"),
      StandardType.new("placard", "Placard", %w[image video], "words shown on their own, between scenes: an intro, a title card, end credits"),
      StandardType.new("scrim", "Scrim", %w[image video], "a frame's whole size, laid over a drop or plug"),
      StandardType.new("prop", "Prop", %w[image video model], "an object the app places: a picture cropped close to its edges, or a 3D model of a thing " \
                                                              "(a chair, a sword), not a set or a figure"),
      StandardType.new("texture", "Texture", %w[image video], "a material with no subject or edges, filling an area"),
      StandardType.new("icon", "Icon", %w[image video], "a small indicator: a button, a rating"),
      StandardType.new("pass", "Pass", %w[image video], "for programs, not people: a depth map, a mask, a matte"),
      StandardType.new("automaton", "Automaton", %w[text data], "a character's moves as a graph of picture frames, which may follow which, " \
                                                                "walked afresh each play; its frames are props linked from it"),
      # Sound
      StandardType.new("speech", "Speech", %w[audio], "one voice saying something, words or not (a laugh, a grunt)"),
      StandardType.new("dialogue", "Dialogue", %w[audio], "voices in turns, a conversation"),
      StandardType.new("music", "Music", %w[audio], "composed: a bed under a scene, or a cue (a fanfare, a sting)"),
      StandardType.new("ambience", "Ambience", %w[audio], "a place's continuous sound (wind, a crowd, a hum)"),
      StandardType.new("effect", "Effect", %w[audio], "one event's sound, trimmed close to it; interface sounds too"),
      StandardType.new("recording", "Recording", %w[audio video], "anything captured or mixed, with no clear boundaries"),
      # Text
      StandardType.new("prose", "Prose", %w[text], "continuous writing in one voice: a description, a decree, a story"),
      StandardType.new("script", "Script", %w[text], "lines for voices in turns"),
      StandardType.new("transcript", "Transcript", %w[text], "the words of an audio or video asset as text (corrected by hand, with who speaks, " \
                                                             "with sounds that aren't words), linked transcript-of it; a words track is a tool's timing of the words, not their text"),
      StandardType.new("log", "Log", %w[text], "a record of what happened, in order"),
      # Documents and data
      StandardType.new("document", "Document", %w[data text], "made to be read: pages laid out, text and pictures (PDF, EPUB)"),
      StandardType.new("data", "Data", %w[data text], "made for programs: structured (JSON, CSV) or binary (a story file, a saved game); also the catch-all"),
      # 3D (and prop, above)
      StandardType.new("set", "Set", %w[model], "a place in 3D, to be inside or look into"),
      StandardType.new("figure", "Figure", %w[model], "a character's body, usually rigged"),
      StandardType.new("motion", "Motion", %w[model data], "movement for a skeleton, without geometry"),
      # Across media
      StandardType.new("sequence", "Sequence", %w[audio video], "parts arranged in time: shots cut together, clips put together into one file"),
      StandardType.new("font", "Font", %w[font], "a typeface"),
    ]

    # Whether a type's name is one of DataDungeon's (STANDARD_TYPES).
    def self.standard_type?(name : String) : Bool
      STANDARD_TYPES.any? { |type| type.name == name }
    end

    # The owner of DataDungeon's own wordings, the ratings' words.
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
      # One name for an app's own kinds of a standard type, so curio and a
      # copy can tell which tag says the kind (Thomas, 2026-10-19). The
      # values are each app's own words, so none is listed.
      {name: "subtype", title: "Subtype", label: "", kind: "",
       description: "an app's own kind of a standard type, in its own words: a room, a door view, a background",
       wording: "", values: [] of {value: String, title: String, description: String, family: String, words: String}},
    ]

    # Takes the vocabulary as this release has it, inside setup_schema's
    # transaction. Values a later release drops are kept.
    private def seed_vocabulary(conn : ::DB::Connection) : Nil
      # A store opened by the first 0.14 build (4426581) named a value's words style_id.
      if conn.query_one?("SELECT 1 FROM pragma_table_info('vocabulary_values') WHERE name = 'style_id'", as: Int32)
        conn.exec("ALTER TABLE vocabulary_values RENAME COLUMN style_id TO wording_id")
      end
      VOCABULARY_SCHEMAS.split(";").each { |sql| conn.exec(sql.strip) unless sql.strip.empty? }
      # A store opened by a 0.14 build before the tag has standard art
      # styles, which 0.14 doesn't keep (Thomas, 2026-10-17: each app names,
      # words and tags its own). No released store has them, and no asset's
      # tags are touched; their words stay in named_texts, as every
      # wording does.
      conn.exec("DELETE FROM vocabulary_values WHERE tag = 'art-style'")
      conn.exec("DELETE FROM vocabulary_tags WHERE name = 'art-style'")
      VOCABULARY.each do |tag|
        conn.exec(<<-SQL, tag[:name], tag[:title], tag[:label], tag[:kind], tag[:description])
          INSERT INTO vocabulary_tags (name, title, label, kind, description) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT (name) DO UPDATE SET title = excluded.title, label = excluded.label, kind = excluded.kind,
            description = excluded.description
        SQL
        tag[:values].each_with_index do |value, position|
          wording_id = put_named(conn, tag[:wording], VOCABULARY_OWNER, value[:value], put_text(conn, value[:words]), owned: true)
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
        wording = Recipe::Wording.new(kind, Recipe::Wording.handle(VOCABULARY_OWNER, value, version), text) if kind && text
        values[tag] << VocabularyValue.new(value, title, description, family, wording)
      end
      @db.query_all("SELECT name, title, label, kind, description FROM vocabulary_tags ORDER BY name",
        as: {String, String, String, String, String}).map do |(name, title, label, kind, description)|
        VocabularyTag.new(name, title, label, kind, description, values[name]? || [] of VocabularyValue)
      end
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
      row.try { |(kind, version, words)| Recipe::Wording.new(kind, Recipe::Wording.handle(VOCABULARY_OWNER, value, version), words) }
    end
  end
end
