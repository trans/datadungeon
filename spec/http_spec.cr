require "spec"
require "file_utils"
require "../src/data_dungeon/http"

private def with_api(name : String, read_token : String? = "r", write_token : String? = "w", &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("backdrop", pool_traits: %w[art-style rating], pool: true)
  api = DataDungeon::API.new(db, read_token: read_token, write_token: write_token, prefix: "/dd")
  yield api, db, dir
ensure
  db.try(&.close)
  FileUtils.rm_rf(dir) if dir
end

# One request through the handler, as a client would see the response.
private def call(api, method : String, path : String, token : String? = nil, body = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Authorization"] = "Bearer #{token}" if token
  request = HTTP::Request.new(method, path, headers, body.try(&.to_json))
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  api.call(HTTP::Server::Context.new(request, response))
  response.close
  HTTP::Client::Response.from_io(io.rewind)
end

private def json(response) : JSON::Any
  JSON.parse(response.body)
end

private def store_backdrop(db, style : String, bytes : String) : DataDungeon::AssetRecord
  db.store("backdrop", {"art-style" => style, "rating" => "pg"}, bytes: bytes.to_slice, content_type: "image/webp")
end

describe DataDungeon::API do
  it "lists types, tags and their values" do
    with_api("dd-api-types") do |api, db|
      store_backdrop(db, "golden", "a")
      store_backdrop(db, "golden", "b")
      store_backdrop(db, "silver", "c")

      types = json(call(api, "GET", "/dd/types", "r"))
      types[0]["name"].should eq "backdrop"
      types[0]["count"].should eq 3
      types[0]["registration"]["pool_traits"].should eq ["art-style", "rating"]
      json(call(api, "GET", "/dd/types/backdrop/tags", "r")).should eq({"art-style" => 3, "rating" => 3})
      json(call(api, "GET", "/dd/types/backdrop/tags/art-style?limit=1", "r")).should eq({"golden" => 2})
    end
  end

  it "pages through assets by tag, and shows one with its metadata and bytes" do
    with_api("dd-api-assets") do |api, db|
      a = store_backdrop(db, "golden", "a")
      store_backdrop(db, "silver", "b")
      c = store_backdrop(db, "golden", "c")

      page = json(call(api, "GET", "/dd/assets?type=backdrop&tag.art-style=Golden&limit=1", "r"))
      page["total"].should eq 2
      page["assets"].as_a.map(&.["asset"]["id"]).should eq [c.id]
      page["assets"][0]["tags"]["art-style"].should eq "golden"
      json(call(api, "GET", "/dd/assets?type=backdrop&tag.art-style=golden&limit=1&offset=1", "r"))["assets"][0]["asset"]["id"].should eq a.id

      shown = json(call(api, "GET", "/dd/assets/#{a.id}", "r"))
      shown["asset"]["pool_key"].should eq "backdrop.golden.pg"
      shown["tags"].should eq({"art-style" => "golden", "rating" => "pg"})
      object = call(api, "GET", "/dd/assets/#{a.id}/object", "r")
      object.status_code.should eq 200
      object.headers["Content-Type"].should eq "image/webp"
      object.body.should eq "a"
      db.find_asset_by_id(a.id).not_nil!.use_count.should eq 0 # browsing doesn't count as use

      call(api, "GET", "/dd/assets/999", "r").status_code.should eq 404
      call(api, "GET", "/dd/assets", "r").status_code.should eq 400 # no type
      call(api, "GET", "/dd/assets?type=backdrop&limit=9999", "r").status_code.should eq 400
    end
  end

  it "needs the read token to read, and the write token to write" do
    with_api("dd-api-auth") do |api, db|
      rec = store_backdrop(db, "golden", "a")
      call(api, "GET", "/dd/types").status_code.should eq 401
      call(api, "GET", "/dd/types", "nope").status_code.should eq 401
      call(api, "GET", "/dd/types", "w").status_code.should eq 200 # the write token reads too
      call(api, "POST", "/dd/maintenance/check", "r").status_code.should eq 200

      call(api, "PATCH", "/dd/assets/#{rec.id}", "r", {flagged: true}).status_code.should eq 403
      call(api, "DELETE", "/dd/assets/#{rec.id}", "r").status_code.should eq 403
      call(api, "POST", "/dd/maintenance/vacuum", "r").status_code.should eq 403
      db.find_asset_by_id(rec.id).not_nil!.flagged.should be_false
    end
  end

  it "edits, promotes and deletes with the write token" do
    with_api("dd-api-write") do |api, db|
      rec = db.store("backdrop", {"art-style" => "golden", "rating" => "pg"}, custom: %w[art-style],
        bytes: "a".to_slice, content_type: "image/webp")

      edited = json(call(api, "PATCH", "/dd/assets/#{rec.id}", "w",
        {description: "a beach", flagged: true, tags: {"art-style" => "silver", "rating" => "pg"}}))
      edited["asset"]["description"].should eq "a beach"
      edited["asset"]["flagged"].should be_true
      edited["asset"]["pool_key"].should eq "backdrop.silver.pg"

      db.update_asset(rec.id, tags: {"art-style" => "golden", "rating" => "pg"}) # golden, not custom now
      db.store("backdrop", {"art-style" => "bronze", "rating" => "pg"}, custom: %w[art-style],
        bytes: "b".to_slice, content_type: "image/webp")
      json(call(api, "POST", "/dd/types/backdrop/promote", "w", {trait: "art-style", value: "bronze"}))["promoted"].should eq 1
      db.custom_values("backdrop", "art-style").should be_empty

      call(api, "PATCH", "/dd/assets/#{rec.id}", "w", {rating: "high"}).status_code.should eq 400
      json(call(api, "DELETE", "/dd/assets/#{rec.id}", "w"))["deleted"].should eq rec.id
      db.find_asset_by_id(rec.id).should be_nil
      call(api, "DELETE", "/dd/assets/#{rec.id}", "w").status_code.should eq 404
    end
  end

  it "has no writes without a write token, reads freely without a read token, and refuses writes on a read-only DB" do
    with_api("dd-api-modes", read_token: nil, write_token: nil) do |api, db, dir|
      rec = store_backdrop(db, "golden", "a")
      call(api, "GET", "/dd/types").status_code.should eq 200
      call(api, "DELETE", "/dd/assets/#{rec.id}", "anything").status_code.should eq 403

      ro = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"), read_only: true)
      begin
        read_only = DataDungeon::API.new(ro, write_token: "w")
        response = call(read_only, "PATCH", "/assets/#{rec.id}", "w", {flagged: true})
        response.status_code.should eq 409
        json(response)["error"].as_s.should contain "read-only"
        call(read_only, "GET", "/assets/#{rec.id}/object").body.should eq "a"
      ensure
        ro.close
      end
    end
  end

  it "leaves paths outside its prefix to the next handler" do
    with_api("dd-api-prefix") do |api|
      call(api, "GET", "/elsewhere", "r").status_code.should eq 404
      call(api, "GET", "/ddx/types", "r").status_code.should eq 404
      call(api, "GET", "/dd/nothing", "r").body.should contain "No such endpoint"
    end
  end
end
