require "spec"
require "file_utils"
require "../src/data_dungeon"

private def with_store(&)
  dir = File.tempname("dd-schema")
  Dir.mkdir_p(dir)
  begin
    yield File.join(dir, "assets.db"), dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

private def open_store(path : String, dir : String, read_only = false) : DataDungeon::DB
  DataDungeon::DB.new(path, cache_root: File.join(dir, "store"), read_only: read_only)
end

private def stamp(path : String) : Int64
  DB.open("sqlite3://#{path}") { |raw| raw.scalar("PRAGMA user_version").as(Int64) }
end

private def set_stamp(path : String, value : Int32) : Nil
  DB.open("sqlite3://#{path}") { |raw| raw.exec("PRAGMA user_version = #{value}") }
end

private def copies(dir : String) : Array(String)
  Dir.children(dir).select(&.includes?(".before-")).sort
end

describe "A store's schema" do
  it "stamps a new store, with nothing to copy" do
    with_store do |path, dir|
      db = open_store(path, dir)
      db.schema.should eq DataDungeon::DB::SCHEMA
      db.copied_to.should be_nil
      db.close
      stamp(path).should eq DataDungeon::DB::SCHEMA
      copies(dir).should be_empty
    end
  end

  it "copies the database of a store it converts, then stamps it, once" do
    with_store do |path, dir|
      db = open_store(path, dir)
      db.register_type("data", pool_traits: %w[name])
      db.store("data", {"name" => "walk"}, bytes: "HIERARCHY".to_slice, filename: "walk.bvh",
        content_type: "application/octet-stream")
      db.close
      set_stamp(path, 0) # as 0.16.7 left it

      db = open_store(path, dir)
      copy = "#{path}.before-#{DataDungeon::VERSION}"
      db.copied_to.should eq copy
      db.schema.should eq DataDungeon::DB::SCHEMA
      db.close
      stamp(path).should eq DataDungeon::DB::SCHEMA
      stamp(copy).should eq 0
      DB.open("sqlite3://#{copy}") { |raw| raw.scalar("SELECT count(*) FROM assets").as(Int64) }.should eq 1

      db = open_store(path, dir)
      db.copied_to.should be_nil
      db.close
      copies(dir).should eq ["assets.db.before-#{DataDungeon::VERSION}"]
    end
  end

  it "never overwrites a copy" do
    with_store do |path, dir|
      open_store(path, dir).close
      first = "#{path}.before-#{DataDungeon::VERSION}"
      File.write(first, "an earlier copy")
      set_stamp(path, 0)

      db = open_store(path, dir)
      db.copied_to.should eq "#{first}-2"
      db.close
      File.read(first).should eq "an earlier copy"
      copies(dir).size.should eq 2
    end
  end

  it "refuses a store a newer DataDungeon converted, and leaves it as it is" do
    with_store do |path, dir|
      open_store(path, dir).close
      newer = DataDungeon::DB::SCHEMA + 1
      set_stamp(path, newer)

      expect_raises(DataDungeon::NewerStoreError, /schema #{newer}/) { open_store(path, dir) }
      expect_raises(DataDungeon::NewerStoreError) { open_store(path, dir, read_only: true) }
      stamp(path).should eq newer
      copies(dir).should be_empty
    end
  end

  it "reads the schema as it is when read-only" do
    with_store do |path, dir|
      open_store(path, dir).close
      db = open_store(path, dir, read_only: true)
      db.schema.should eq DataDungeon::DB::SCHEMA
      db.close

      set_stamp(path, 0) # unstamped, but in today's layout: read as before
      db = open_store(path, dir, read_only: true)
      db.schema.should eq 0
      db.close
      stamp(path).should eq 0
      copies(dir).should be_empty
    end
  end
end
