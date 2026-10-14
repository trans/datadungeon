require "spec"
require "file_utils"
require "../src/data_dungeon"

# Local storage that counts its writes.
private class CountingStorage < DataDungeon::LocalStorage
  getter writes = 0

  def write(key : String, bytes : Bytes, content_type : String? = nil) : Nil
    @writes += 1
    super
  end
end

private def open_store(dir : String, name : String, storage : DataDungeon::Storage) : DataDungeon::DB
  db = DataDungeon::DB.new(File.join(dir, "#{name}.db"), storage)
  db.register_type("drop", pool_traits: %w[art-style])
  db.register_type("prop", pool_traits: %w[art-style])
  db
end

private def store_drop(db, bytes : String) : DataDungeon::AssetRecord
  db.store("drop", {"art-style" => "pixel"}, bytes: bytes.to_slice, content_type: "image/webp",
    image: DataDungeon::ImageMeta.new(compression: "original"))
end

describe "Shared storage" do
  it "never deletes an object other stores may use, and writes each one again" do
    dir = File.tempname("dd-shared")
    Dir.mkdir_p(dir)
    storage = CountingStorage.new(File.join(dir, "objects"), shared: true)
    park = open_store(dir, "park", storage)
    owl = open_store(dir, "owl", storage)

    mine = store_drop(park, "same picture")
    copy = store_drop(owl, "same picture")
    copy.file_path.should eq mine.file_path # one object for both
    storage.writes.should eq 2              # written again, so its date is the latest use

    park.delete_asset(mine.id)
    storage.exists?(copy.file_path).should be_true
    owl.read(copy).should eq "same picture".to_slice

    owl.object_keys.should eq [copy.file_path]
    park.object_keys.should be_empty
    expect_raises(ArgumentError, /shared/) { park.vacuum(delete_orphan_objects: true) }
    park.check_consistency.orphan_objects.should eq [copy.file_path] # owl's, as far as park can tell
  ensure
    park.try(&.close)
    owl.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end

  it "deletes an object no row uses when the storage is the store's own" do
    dir = File.tempname("dd-unshared")
    Dir.mkdir_p(dir)
    storage = CountingStorage.new(File.join(dir, "objects"))
    db = open_store(dir, "park", storage)
    a = store_drop(db, "a picture")
    b = db.store("prop", {"art-style" => "pixel"}, bytes: "a picture".to_slice, content_type: "image/webp",
      image: DataDungeon::ImageMeta.new(compression: "original"))
    storage.writes.should eq 1 # already there
    db.delete_asset(a.id)
    storage.exists?(a.file_path).should be_true # the other row still uses it
    db.delete_asset(b.id)
    storage.exists?(a.file_path).should be_false
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end
end
