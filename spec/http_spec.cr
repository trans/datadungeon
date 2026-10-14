require "spec"
require "file_utils"
require "../src/data_dungeon/http"

private def with_api(name : String, read_token : String? = "r", write_token : String? = "w", &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  db = DataDungeon::DB.new(File.join(dir, "assets.db"), cache_root: File.join(dir, "store"))
  db.register_type("backdrop", pool_traits: %w[art-style rating])
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

      page = json(call(api, "GET", "/dd/assets?type=backdrop&tag.art-style=Golden&limit=1&count=1", "r"))
      page["total"].should eq 2
      page["assets"].as_a.map(&.["asset"]["id"]).should eq [c.id]
      page["assets"][0]["tags"]["art-style"].should eq "golden"
      page["next"].should eq c.id
      last = json(call(api, "GET", "/dd/assets?type=backdrop&tag.art-style=golden&limit=1&before=#{c.id}", "r"))
      last["assets"][0]["asset"]["id"].should eq a.id
      last["total"].raw.should be_nil # counted only on request
      second = json(call(api, "GET", "/dd/assets?type=backdrop&limit=2&page=2", "r"))
      second["page"].should eq 2
      second["assets"].as_a.map(&.["asset"]["id"]).should eq [a.id]
      call(api, "GET", "/dd/assets?page=0", "r").status_code.should eq 400
      json(call(api, "GET", "/dd/assets?q=golden&limit=5", "r"))["next"].raw.should be_nil
      json(call(api, "GET", "/dd/assets?q=silv*", "r"))["assets"].size.should eq 1

      shown = json(call(api, "GET", "/dd/assets/#{a.id}", "r"))
      shown["asset"]["key"].should eq "backdrop.golden.pg"
      shown["tags"].should eq({"art-style" => "golden", "rating" => "pg"})
      object = call(api, "GET", "/dd/assets/#{a.id}/object", "r")
      object.status_code.should eq 200
      object.headers["Content-Type"].should eq "image/webp"
      object.body.should eq "a"
      db.flush_usage
      db.find_asset_by_id(a.id).not_nil!.use_count.should eq 0 # browsing doesn't count as use

      call(api, "GET", "/dd/assets/999", "r").status_code.should eq 404
      json(call(api, "GET", "/dd/assets", "r"))["assets"].size.should eq 3 # every type
      call(api, "GET", "/dd/assets?before=x", "r").status_code.should eq 400
      call(api, "GET", "/dd/assets?type=backdrop&limit=9999", "r").status_code.should eq 400
    end
  end

  it "links and unlinks with the write token, and shows links" do
    with_api("dd-api-links") do |api, db|
      a = store_backdrop(db, "golden", "a")
      b = store_backdrop(db, "silver", "b")
      call(api, "POST", "/dd/assets/#{a.id}/links", "r", {rel: "used-by", name: "boardwalk"}).status_code.should eq 403
      json(call(api, "POST", "/dd/assets/#{a.id}/links", "w", {rel: "used-by", name: "boardwalk"}))["from"][0]["to_name"].should eq "boardwalk"
      call(api, "POST", "/dd/assets/#{b.id}/links", "w", {rel: "derived-from", to: a.id}).status_code.should eq 200
      call(api, "POST", "/dd/assets/#{b.id}/links", "w", {rel: "derived-from", to: a.id, name: "x"}).status_code.should eq 400

      json(call(api, "GET", "/dd/assets/#{a.id}", "r"))["links"]["to"][0]["from_id"].should eq b.id
      json(call(api, "GET", "/dd/assets?link.used-by=boardwalk", "r"))["assets"].as_a.map(&.["asset"]["id"]).should eq [a.id]
      json(call(api, "GET", "/dd/assets?unlinked=used-by", "r"))["assets"].as_a.map(&.["asset"]["id"]).should eq [b.id]
      json(call(api, "DELETE", "/dd/assets/#{a.id}/links?rel=used-by&name=boardwalk", "w"))["removed"].should be_true
      json(call(api, "GET", "/dd/assets/#{a.id}/links", "r"))["from"].as_a.should be_empty
    end
  end

  it "retires, reinstates and prunes, and lists retired assets on request" do
    with_api("dd-api-retire") do |api, db|
      a = store_backdrop(db, "golden", "a")
      b = store_backdrop(db, "silver", "b")

      json(call(api, "POST", "/dd/assets/#{b.id}/retire", "w"))["retired"].should be_true
      json(call(api, "POST", "/dd/assets/#{b.id}/retire", "w"))["retired"].should be_false
      call(api, "POST", "/dd/assets/999/retire", "w").status_code.should eq 404
      types = json(call(api, "GET", "/dd/types", "r"))
      types[0]["count"].should eq 1
      types[0]["retired"].should eq 1
      json(call(api, "GET", "/dd/assets?type=backdrop&count=1", "r"))["total"].should eq 1
      only = json(call(api, "GET", "/dd/assets?type=backdrop&retired=only", "r"))
      only["assets"].as_a.map(&.["asset"]["id"]).should eq [b.id]
      only["assets"][0]["asset"]["retired_at"].as_s.should_not be_empty
      json(call(api, "GET", "/dd/assets?retired=include&count=1", "r"))["total"].should eq 2
      json(call(api, "GET", "/dd/types/backdrop/tags/art-style?retired=only", "r")).should eq({"silver" => 1})
      call(api, "GET", "/dd/assets?retired=yes", "r").status_code.should eq 400

      json(call(api, "POST", "/dd/assets/#{b.id}/reinstate", "w"))["reinstated"].should be_true
      c = store_backdrop(db, "golden", "c")
      json(call(api, "POST", "/dd/assets/#{c.id}/links", "w", {rel: "supersedes", to: a.id}))
      db.find_asset_by_id(a.id).not_nil!.retired?.should be_true
      json(call(api, "POST", "/dd/maintenance/prune", "w", {type: "backdrop", retired_before: "2000-01-01"}))["pruned"].should eq 0
      json(call(api, "POST", "/dd/maintenance/prune", "w", {type: "backdrop"}))["pruned"].should eq 1
      db.find_asset_by_id(a.id).should be_nil
      call(api, "POST", "/dd/maintenance/prune", "w", {type: "backdrop", retired_before: "soon"}).status_code.should eq 400
    end
  end

  it "keeps a link's data, and filters by a name and what's under it" do
    with_api("dd-api-link-data") do |api, db|
      a = store_backdrop(db, "golden", "a")
      store_backdrop(db, "silver", "b")
      call(api, "POST", "/dd/assets/#{a.id}/links", "w",
        {rel: "used-by", name: "boardwalk.holidayland", data: {at: [0.25, 0.5], layer: 2}}).status_code.should eq 200

      links = json(call(api, "GET", "/dd/assets/#{a.id}/links", "r"))
      links["from"][0]["data"]["layer"].should eq 2
      json(call(api, "GET", "/dd/assets?link.used-by=boardwalk.*", "r"))["assets"].as_a.map(&.["asset"]["id"]).should eq [a.id]
      json(call(api, "GET", "/dd/assets?link.used-by=boardwalk", "r"))["assets"].size.should eq 0
    end
  end

  it "sets, shows and filters a picture's fields, and measures pictures" do
    with_api("dd-api-image") do |api, db|
      a = store_backdrop(db, "golden", "a")
      store_backdrop(db, "silver", "b")
      call(api, "PATCH", "/dd/assets/#{a.id}", "w",
        {image: {view: {side: "back", yaw: -0.5}, light: {yaw: -0.5, pitch: 0.5}, world_height: 3, anchor_y: 1}}).status_code.should eq 200

      shown = json(call(api, "GET", "/dd/assets/#{a.id}", "r"))
      shown["view"]["name"].should eq "back-left"
      shown["light"]["pitch"].should eq 0.5
      shown["meta"]["world_height"].should eq 3.0
      ids = ->(query : String) { json(call(api, "GET", "/dd/assets?#{query}", "r"))["assets"].as_a.map(&.["asset"]["id"]) }
      ids.call("view=back-left").should eq [a.id]
      ids.call("field.world_height=2..4").should eq [a.id]
      ids.call("field.world_height=4..").should be_empty
      ids.call("view.side=back&view.yaw=-0.5&view.within=10").should eq [a.id]
      ids.call("light.yaw=0.5").should be_empty
      call(api, "GET", "/dd/assets?field.world_height=tall", "r").status_code.should eq 400
      call(api, "GET", "/dd/assets?view=north", "r").status_code.should eq 400

      json(call(api, "POST", "/dd/maintenance/measure", "w", {type: "backdrop", all: true}))["measured"].should eq 2
      json(call(api, "GET", "/dd/types/backdrop/views", "r")).should eq({"back-left" => 1})
      rows = json(call(api, "GET", "/dd/assets?type=backdrop&meta=1", "r"))["assets"].as_a
      rows.map { |row| row["view"].raw.nil? ? nil : row["view"]["name"].as_s }.should eq [nil, "back-left"]
      rows[1]["meta"]["world_height"].should eq 3.0
      json(call(api, "GET", "/dd/assets?type=backdrop", "r"))["assets"][1]["meta"].raw.should be_nil # only on request

      db.update_asset(a.id, image: DataDungeon::ImageMeta.new(animation: DataDungeon::ImageAnimation.new(frame_count: 2, duration_ms: 500)))
      set = json(call(api, "PUT", "/dd/assets/#{a.id}/keyframes", "w", [{at_ms: 250, view: {side: "back", yaw: 0}}]))
      set["keyframes"][0]["at_ms"].should eq 250
      json(call(api, "GET", "/dd/assets/#{a.id}", "r"))["keyframes"].size.should eq 1
      call(api, "PUT", "/dd/assets/#{a.id}/keyframes", "r", [] of Int32).status_code.should eq 403
    end
  end

  it "shows an asset's recipe, and marks an asset permanent" do
    with_api("dd-api-recipe") do |api, db|
      recipe = DataDungeon::Recipe.new("picture", settings: {"model" => "flux-dev"},
        fields: {"subject" => DataDungeon::Recipe.text("A pier at dusk.")}, seed: 3)
      made = db.store("backdrop", {"art-style" => "pixel", "rating" => "g"}, bytes: "m".to_slice,
        content_type: "image/webp", recipe: recipe)
      plain = store_backdrop(db, "golden", "p")

      json(call(api, "GET", "/dd/assets/#{made.id}", "r"))["asset"]["has_recipe"].should eq true
      shown = json(call(api, "GET", "/dd/assets/#{made.id}/recipe", "r"))["recipe"]
      shown["form"].should eq "picture"
      shown["fields"]["subject"]["text"].should eq "A pier at dusk."
      shown["settings"].should eq({"model" => "flux-dev"})
      shown["seed"].should eq 3
      call(api, "GET", "/dd/assets/#{plain.id}/recipe", "r").status_code.should eq 404
      call(api, "GET", "/dd/assets/999/recipe", "r").status_code.should eq 404

      edited = json(call(api, "PATCH", "/dd/assets/#{plain.id}", "w", {permanent: true}))
      edited["asset"]["permanent"].should eq true
    end
  end

  it "finds assets by file and by description, and changes a shared description everywhere" do
    with_api("dd-api-shared") do |api, db|
      a = db.store("backdrop", {"art-style" => "pixel", "rating" => "g"}, bytes: "a".to_slice,
        content_type: "image/webp", description: "A pier.")
      b = db.store("backdrop", {"art-style" => "golden", "rating" => "g"}, bytes: "b".to_slice,
        content_type: "image/webp", description: "A pier.")
      hash = json(call(api, "GET", "/dd/assets/#{a.id}", "r"))["asset"]["description_hash"].as_s
      listed = json(call(api, "GET", "/dd/assets?description_hash=#{hash}&count=1", "r"))
      listed["total"].should eq 2
      json(call(api, "GET", "/dd/assets?file_hash=#{b.file_hash}", "r"))["assets"].as_a.map(&.["asset"]["id"]).should eq [b.id]
      json(call(api, "GET", "/dd/assets?text.style=overlore:silver", "r"))["assets"].as_a.should be_empty
      call(api, "GET", "/dd/assets?text.style=silver", "r").status_code.should eq 400

      call(api, "PATCH", "/dd/assets/#{a.id}", "w", {description: "A long pier.", everywhere: true})
      db.find_asset_by_id(b.id).not_nil!.description.should eq "A long pier."
      json(call(api, "GET", "/dd/objects", "r"))["objects"].as_a.map(&.as_s).should eq [a.file_path, b.file_path].sort
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
      edited["asset"]["key"].should eq "backdrop.silver.pg"

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
