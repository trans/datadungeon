require "spec"
require "file_utils"
require "../src/data_dungeon"

# A take's tracks: what tools measured of it over time, kept with it (Thomas,
# 2026-10-19), Whisper's word timings and Rhubarb's mouth cues among them.
private def with_db(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  path = File.join(dir, "assets.db")
  db = DataDungeon::DB.new(path, cache_root: File.join(dir, "store"))
  db.register_type("speech", pool_traits: %w[line])
  yield db, path, dir
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

private def take(db, line = "l1") : DataDungeon::AssetRecord
  db.store("speech", {"line" => line}, bytes: "take #{line}".to_slice, content_type: "audio/mpeg")
end

private def cue(start_ms, end_ms, value) : DataDungeon::TrackCue
  DataDungeon::TrackCue.new(start_ms, end_ms, value)
end

describe "Tracks" do
  it "keeps a take's word times and mouth cues, each replaced whole" do
    with_db("dd-tracks") do |db|
      a = take(db)
      words = [cue(0, 180, "My"), cue(180, 520, "friend!"), cue(1400, 1750, "WHAT?")]
      db.set_track(a.id, "words", words, tool: "whisper-1")
      db.set_track(a.id, "mouth", [cue(0, 60, "X"), cue(60, 120, "B"), cue(120, 460, "C")], tool: "rhubarb 1.13.0")

      db.tracks(a.id).map(&.name).should eq %w[mouth words]
      kept = db.track(a.id, "words").not_nil!
      kept.tool.should eq "whisper-1"
      kept.cues.map { |c| {c.start_ms, c.end_ms, c.value} }.should eq [{0, 180, "My"}, {180, 520, "friend!"}, {1400, 1750, "WHAT?"}]

      db.set_track(a.id, "mouth", [cue(0, 460, "X")], tool: "rhubarb 1.14.0")
      redone = db.track(a.id, "mouth").not_nil!
      redone.tool.should eq "rhubarb 1.14.0"
      redone.cues.size.should eq 1
      db.tracks(a.id).size.should eq 2
      db.track(a.id, "nothing").should be_nil
      db.tracks(take(db, "l2").id).should be_empty
    end
  end

  it "refuses a track that can't be right, and changes nothing" do
    with_db("dd-tracks-refused") do |db|
      a = take(db)
      db.register_type("drop", pool_traits: %w[room])
      picture = db.store("drop", {"room" => "attic"}, bytes: "p".to_slice, content_type: "image/webp")
      refused = ->(id : Int64, name : String, cues : Array(DataDungeon::TrackCue), tool : String) do
        expect_raises(ArgumentError) { db.set_track(id, name, cues, tool: tool) }
      end
      refused.call(a.id, "Words", [cue(0, 10, "a")], "whisper-1").message.not_nil!.should contain "lowercase"
      refused.call(a.id, "words", [cue(0, 10, "a")], " ").message.not_nil!.should contain "tool"
      refused.call(picture.id, "words", [cue(0, 10, "a")], "whisper-1").message.not_nil!.should contain "image/webp"
      refused.call(a.id, "words", [cue(-5, 10, "a")], "whisper-1")
      refused.call(a.id, "words", [cue(20, 10, "a")], "whisper-1").message.not_nil!.should contain "ends before it starts"
      refused.call(a.id, "words", [cue(50, 60, "b"), cue(0, 10, "a")], "whisper-1").message.not_nil!.should contain "time order"
      refused.call(a.id, "words", [cue(0, 10, "")], "whisper-1")
      expect_raises(ArgumentError, /No asset/) { db.set_track(999_i64, "words", [] of DataDungeon::TrackCue, tool: "whisper-1") }
      db.tracks(a.id).should be_empty

      db.set_track(a.id, "words", [] of DataDungeon::TrackCue, tool: "whisper-1").cues.should be_empty
      db.tracks(a.id).map(&.name).should eq %w[words]

      # Only the start order is checked (@overlore): a word may last no
      # time, and run past the next one's start.
      db.set_track(a.id, "words", [cue(0, 200, "a"), cue(150, 150, "b"), cue(150, 300, "c")], tool: "whisper-1").cues.size.should eq 3
    end
  end

  it "goes with its asset, retired or deleted" do
    with_db("dd-tracks-delete") do |db|
      a = take(db)
      db.set_track(a.id, "mouth", [cue(0, 60, "X")], tool: "rhubarb 1.13.0")
      db.retire(a.id)
      db.tracks(a.id).size.should eq 1
      db.delete_asset(a.id)
      db.connection.scalar("SELECT count(*) FROM asset_tracks").should eq 0
    end
  end

  it "reads as none from a store no 0.15.3 has opened read-write" do
    with_db("dd-tracks-older") do |db, path|
      a = take(db)
      db.connection.exec("DROP TABLE asset_tracks")
      older = DataDungeon::DB.new(path, read_only: true)
      begin
        older.tracks(a.id).should be_empty
        older.track(a.id, "words").should be_nil
      ensure
        older.close
      end
    end
  end
end
