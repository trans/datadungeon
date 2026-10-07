require "spec"
require "file_utils"
require "../src/data_dungeon/s3"

# Runs against a real S3-compatible server when DD_S3_ENDPOINT and friends are
# set; scripts/garage-test starts a throwaway Garage and sets them.
S3_SETTINGS = {
  endpoint:   ENV["DD_S3_ENDPOINT"]?,
  region:     ENV["DD_S3_REGION"]?,
  bucket:     ENV["DD_S3_BUCKET"]?,
  access_key: ENV["DD_S3_ACCESS_KEY"]?,
  secret_key: ENV["DD_S3_SECRET_KEY"]?,
}

private def s3_storage(prefix : String) : DataDungeon::S3Storage
  DataDungeon::S3Storage.new(S3_SETTINGS[:bucket].not_nil!,
    endpoint: S3_SETTINGS[:endpoint].not_nil!, region: S3_SETTINGS[:region].not_nil!,
    access_key: S3_SETTINGS[:access_key].not_nil!, secret_key: S3_SETTINGS[:secret_key].not_nil!,
    prefix: prefix)
end

describe DataDungeon::S3Storage do
  unless S3_SETTINGS.values.all?
    pending "needs an S3-compatible server (run scripts/garage-test)"
    next
  end

  it "writes, reads, checks, lists and deletes objects under its prefix" do
    storage = s3_storage("spec-#{Random::Secure.hex(4)}")
    storage.local?.should be_false
    storage.exists?("ab/one.webp").should be_false

    storage.write("ab/one.webp", "first".to_slice, "image/webp")
    storage.write("cd/two.mp3", Bytes[0, 255, 1, 254], "audio/mpeg") # bytes, not text
    storage.exists?("ab/one.webp").should be_true
    String.new(storage.read("ab/one.webp")).should eq "first"
    storage.read("cd/two.mp3").should eq Bytes[0, 255, 1, 254]
    storage.list_keys.sort.should eq ["ab/one.webp", "cd/two.mp3"]

    storage.delete("ab/one.webp")
    storage.delete("ab/one.webp") # a missing object is fine
    storage.exists?("ab/one.webp").should be_false
    storage.list_keys.should eq ["cd/two.mp3"]
    storage.delete("cd/two.mp3")
  end

  it "serves a presigned URL for an object" do
    storage = s3_storage("spec-#{Random::Secure.hex(4)}")
    storage.write("ab/url.txt", "by url".to_slice, "text/plain")
    response = HTTP::Client.get(storage.resolve("ab/url.txt"))
    response.status_code.should eq 200
    response.body.should eq "by url"
    response.headers["Content-Type"]?.should eq "text/plain"
    storage.delete("ab/url.txt")
  end

  it "backs a DataDungeon::DB end to end" do
    dir = File.tempname("dd-s3-db")
    Dir.mkdir_p(dir)
    storage = s3_storage("spec-#{Random::Secure.hex(4)}")
    db = DataDungeon::DB.new(File.join(dir, "assets.db"), storage: storage)
    db.register_type("voice", pool_traits: %w[line voice])
    traits = {"line" => "hello", "voice" => "fable"}

    rec = db.store("voice", traits, bytes: "audio-1".to_slice, content_type: "audio/mpeg", media: "audio")
    db.get("voice", traits, touch: false).not_nil!.id.should eq rec.id
    String.new(db.read(rec)).should eq "audio-1"
    db.check_consistency.clean?.should be_true

    # Replacing the asset stores the new object and removes the old one.
    newer = db.store("voice", traits, bytes: "audio-2".to_slice, content_type: "audio/mpeg", media: "audio")
    String.new(db.read(newer)).should eq "audio-2"
    storage.exists?(rec.file_path).should be_false
    db.check_consistency.clean?.should be_true

    db.delete_asset(newer.id)
    storage.list_keys.should be_empty
  ensure
    db.try(&.close)
    FileUtils.rm_rf(dir) if dir
  end
end
