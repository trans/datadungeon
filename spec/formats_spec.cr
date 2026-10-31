require "spec"
require "file_utils"
require "../src/data_dungeon"

private def ext(content_type : String, name : String? = nil) : String
  DataDungeon::DB.extension_for(content_type, name)
end

private def with_db(&)
  dir = File.tempname("dd-formats")
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("data", pool_traits: %w[name])
  begin
    yield db, dir
  ensure
    db.close
    FileUtils.rm_rf(dir)
  end
end

describe "Formats" do
  it "gives every content type known before 0.16.8 the extension it had" do
    {
      "image/webp" => "webp", "image/png" => "png", "image/jpeg" => "jpg", "image/jpg" => "jpg",
      "image/gif" => "gif", "image/svg+xml" => "svg", "image/tiff" => "tif", "image/x-xcf" => "xcf",
      "audio/mpeg" => "mp3", "audio/mp3" => "mp3", "audio/ogg" => "ogg", "audio/opus" => "opus",
      "audio/wav" => "wav", "audio/x-wav" => "wav", "video/webm" => "webm", "video/mp4" => "mp4",
      "text/plain" => "txt", "text/plain; charset=utf-8" => "txt", "application/json" => "json",
      "application/pdf" => "pdf", "Image/PNG" => "png",
    }.each { |content_type, extension| ext(content_type).should eq extension }
  end

  it "gives the formats it knows now their own" do
    {
      "model/gltf-binary" => "glb", "model/gltf+json" => "gltf", "font/ttf" => "ttf", "font/otf" => "otf",
      "font/woff" => "woff", "font/woff2" => "woff2", "text/vtt" => "vtt", "application/x-subrip" => "srt",
      "application/epub+zip" => "epub", "text/x-yarn" => "yarn", "text/vnd.datadungeon.eyarn" => "eyarn",
      "text/csv" => "csv", "application/xml" => "xml", "application/yaml" => "yaml",
      "application/x-yaml" => "yaml", "application/toml" => "toml",
    }.each { |content_type, extension| ext(content_type).should eq extension }
  end

  it "gives a format of an app's own its syntax's" do
    ext("application/vnd.cattacula.marionette+json").should eq "json"
    ext("application/vnd.example.scene+xml").should eq "xml"
  end

  it "keeps the file's own extension for a format it doesn't know" do
    ext("application/octet-stream", "walk.bvh").should eq "bvh"
    ext("application/octet-stream", "/models/Kitty.FBX").should eq "fbx"
    ext("application/x-blender", "set.blend1").should eq "blend1"
    ext("application/gzip", "poses.tar.gz").should eq "tgz"
    ext("application/x-xz", "poses.tar.xz").should eq "txz"
    ext("application/gzip", "store.db.gz").should eq "gz" # one part
  end

  it "takes bin when the name gives no extension it can use" do
    ext("application/octet-stream").should eq "bin"
    ext("application/octet-stream", "notes").should eq "bin"
    ext("application/octet-stream", ".bashrc").should eq "bin"
    ext("application/octet-stream", "a.c++").should eq "bin"
    ext("application/octet-stream", "trailing.").should eq "bin"
  end

  it "lets a known format decide, never the name" do
    ext("image/jpeg", "photo.jpeg").should eq "jpg"
    ext("application/x-yaml", "export.yml").should eq "yaml"
  end

  it "takes a known format's medium" do
    DataDungeon::DB.media_of("application/x-subrip").should eq "text"
    DataDungeon::DB.media_of("text/vnd.datadungeon.eyarn").should eq "text"
    DataDungeon::DB.media_of("application/epub+zip").should eq "data"
    DataDungeon::DB.media_of("model/gltf-binary").should eq "model"
    DataDungeon::DB.format("audio/mp3").not_nil!.content_types.first.should eq "audio/mpeg"
    DataDungeon::DB.format("application/octet-stream").should be_nil
  end

  it "stores a format it doesn't know under the name it came with" do
    with_db do |db, dir|
      hash = Digest::SHA256.hexdigest("HIERARCHY")
      bvh = db.store("data", {"name" => "walk"}, bytes: "HIERARCHY".to_slice, filename: "walk.bvh",
        content_type: "application/octet-stream")
      bvh.file_path.should eq "#{hash[0, 2]}/#{hash}.bvh"
      String.new(db.read(bvh)).should eq "HIERARCHY"

      path = File.join(dir, "kitty.fbx")
      File.write(path, "Kaydara FBX")
      db.store("data", {"name" => "kitty"}, source_path: path, content_type: "application/octet-stream")
        .file_path.should end_with ".fbx"

      db.store("data", {"name" => "raw"}, bytes: "raw".to_slice, content_type: "application/octet-stream")
        .file_path.should end_with ".bin"
      db.store("data", {"name" => "poses"}, bytes: %({"strings": []}).to_slice, filename: "poses.dat",
        content_type: "application/vnd.cattacula.marionette+json").file_path.should end_with ".json"
    end
  end

  it "adopts a file outside the store under its own extension" do
    with_db do |db, dir|
      path = File.join(dir, "run.bvh")
      File.write(path, "MOTION")
      id = db.store_asset(asset_type: "data", media: "data", content_type: "application/octet-stream",
        file_path: path, tags: {"name" => "run"})
      db.adopt(db.find_asset_by_id(id).not_nil!).file_path.should end_with ".bvh"
    end
  end
end
