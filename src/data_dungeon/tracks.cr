require "json"

module DataDungeon
  # One cue of a track: from `start_ms` to `end_ms` into the asset, and what
  # holds then (a word as spoken, a mouth shape).
  struct TrackCue
    include JSON::Serializable

    getter start_ms : Int32
    getter end_ms : Int32
    getter value : String

    def initialize(@start_ms : Int32, @end_ms : Int32, @value : String)
    end
  end

  # What a tool measured of a sound or a video over time (DB#set_track):
  # the track's name, the tool that made it with its version, when, and its
  # cues in time order.
  struct Track
    include JSON::Serializable

    getter name : String
    getter tool : String
    getter made_at : String
    getter cues : Array(TrackCue)

    def initialize(@name : String, @tool : String, @made_at : String, @cues : Array(TrackCue))
    end
  end

  # A track every app means the same by: its name, its title for people,
  # and what its cues hold.
  struct StandardTrack
    include JSON::Serializable

    getter name : String
    getter title : String
    getter description : String

    def initialize(@name : String, @title : String, @description : String)
    end
  end

  class DB
    # The tracks apps share (Thomas, 2026-10-19: a take's word times and
    # mouth cues go in with the speech). Other names are an app's own.
    STANDARD_TRACKS = [
      StandardTrack.new("words", "Words", "when each word is spoken, its value the word with its punctuation: as written " \
                                          "when the tool aligns a known text, as heard when it transcribes (the tool says which)"),
      StandardTrack.new("mouth", "Mouth", "the mouth's shape over time, for lip sync, its values the tool's own " \
                                          "(Rhubarb Lip Sync's A to H, and X at rest)"),
    ]

    # An asset's tracks, each replaced whole; its cues as JSON, each
    # [start_ms, end_ms, value].
    ASSET_TRACKS_SCHEMA = <<-SQL
      CREATE TABLE IF NOT EXISTS asset_tracks (
        asset_id INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        name     TEXT NOT NULL,
        tool     TEXT NOT NULL,
        cues     TEXT NOT NULL,
        made_at  TEXT NOT NULL,
        PRIMARY KEY (asset_id, name)
      ) WITHOUT ROWID
    SQL

    # False when a read-only open finds a store no 0.15.3 has opened
    # read-write: it has no tracks yet, and reads find none.
    @tracks_kept = true

    # Keep what a tool measured of a sound or a video over time, replacing
    # the track of that name: `words` and `mouth` are shared
    # (STANDARD_TRACKS), other names an app's own. `tool` names the tool, its
    # version and any options that change its result (`rhubarb 1.14.0
    # --dialogFile`), so a better one can redo the track.
    # Cues go in time order; a track with none says the tool found nothing.
    # Tracks go when their asset does.
    def set_track(id : Int64, name : String, cues : Array(TrackCue), *, tool : String) : Track
      writable!
      raise ArgumentError.new("a track's name #{name.inspect} must be lowercase words joined by '-'") unless name.matches?(LABEL)
      raise ArgumentError.new("a track names the tool that made it") if tool.strip.empty?
      rec = find_asset_by_id(id) || raise ArgumentError.new("No asset #{id}")
      unless rec.content_type.starts_with?("audio/") || rec.content_type.starts_with?("video/")
        raise ArgumentError.new("a track times a sound or a video, and asset #{id} is #{rec.content_type}")
      end
      before = 0
      cues.each do |cue|
        raise ArgumentError.new("a cue starts at 0 ms or later, not #{cue.start_ms}") if cue.start_ms < 0
        raise ArgumentError.new("the cue at #{cue.start_ms} ms ends before it starts, at #{cue.end_ms}") if cue.end_ms < cue.start_ms
        raise ArgumentError.new("cues go in time order: one at #{cue.start_ms} ms follows one at #{before}") if cue.start_ms < before
        raise ArgumentError.new("the cue at #{cue.start_ms} ms has no value") if cue.value.empty?
        before = cue.start_ms
      end
      stored = cues.map { |cue| {cue.start_ms, cue.end_ms, cue.value} }.to_json
      made_at = Time.utc.to_s(TIME_FORMAT)
      write_transaction do |conn|
        conn.exec(<<-SQL, id, name, tool, stored, made_at)
          INSERT INTO asset_tracks (asset_id, name, tool, cues, made_at) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT (asset_id, name) DO UPDATE SET tool = excluded.tool, cues = excluded.cues, made_at = excluded.made_at
        SQL
      end
      Track.new(name, tool, made_at, cues)
    end

    # An asset's tracks, by name.
    def tracks(id : Int64) : Array(Track)
      query_tracks("asset_id = ?", [id] of ::DB::Any)
    end

    # One of an asset's tracks, or nil.
    def track(id : Int64, name : String) : Track?
      query_tracks("asset_id = ? AND name = ?", [id, name] of ::DB::Any).first?
    end

    private def query_tracks(where : String, args : Array(::DB::Any)) : Array(Track)
      return [] of Track unless @tracks_kept
      @db.query_all("SELECT name, tool, made_at, cues FROM asset_tracks WHERE #{where} ORDER BY name", args: args) do |rs|
        name, tool, made_at = rs.read(String), rs.read(String), rs.read(String)
        cues = Array({Int32, Int32, String}).from_json(rs.read(String)).map { |(start, finish, value)| TrackCue.new(start, finish, value) }
        Track.new(name, tool, made_at, cues)
      end
    end
  end
end
