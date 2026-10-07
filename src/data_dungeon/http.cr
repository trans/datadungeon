require "http/server"
require "json"
require "uri"
require "crypto/subtle"
require "../data_dungeon"

module DataDungeon
  # A JSON API over a DB, for tools that browse and curate a store from
  # elsewhere, such as an asset browser. Mount it in an application's HTTP
  # server (it's an HTTP::Handler, under `prefix`), or run it alone next to
  # the database with `dd-serve`.
  #
  # Tokens go in `Authorization: Bearer <token>`. Reads need `read_token`,
  # or nothing when it's nil (for a server only this machine can reach).
  # Writes need `write_token`; with none, there are no writes. The write
  # token reads too. A read-only DB refuses writes whatever the token.
  #
  #     GET    /types                      types, counts and registrations
  #     GET    /types/:type/tags           tag names and how many assets carry each
  #     GET    /types/:type/tags/:key      a tag's values, most frequent first (?limit=)
  #     GET    /assets?type=&tag.<key>=    a page of assets with their tags (?limit=&offset=)
  #     GET    /assets/:id                 an asset, its tags, custom tags and metadata
  #     GET    /assets/:id/object          its bytes, streamed from the storage
  #     POST   /maintenance/check          check_consistency's report
  #
  #     PATCH  /assets/:id                 {tags, description, flagged, rating}: update_asset
  #     DELETE /assets/:id
  #     POST   /types/:type/promote        {trait, value}: promote
  #     POST   /maintenance/vacuum         {delete_missing_rows, delete_orphan_objects}
  class API
    include HTTP::Handler

    PAGE     =  50
    MAX_PAGE = 500

    def initialize(@db : DB, *, @read_token : String? = nil, @write_token : String? = nil, prefix : String = "")
      @prefix = prefix.rstrip('/')
    end

    def call(context : HTTP::Server::Context) : Nil
      path = context.request.path
      return call_next(context) unless path == @prefix || path.starts_with?("#{@prefix}/")
      parts = path.lchop(@prefix).split('/', remove_empty: true).map { |part| URI.decode(part) }
      method = context.request.method
      write = method.in?("PATCH", "DELETE") || (method == "POST" && parts != ["maintenance", "check"])
      return unless authorized?(context, write)
      route(context, method, parts)
    rescue ex : ArgumentError | JSON::ParseException | TypeCastError | KeyError
      error(context, 400, ex.message)
    rescue ex : ReadOnlyError
      error(context, 409, ex.message)
    end

    private def route(context, method : String, parts : Array(String)) : Nil
      id = parts[1]?.try(&.to_i64?)
      if method == "GET" && parts == ["types"]
        respond(context, @db.asset_types.map { |name, count|
          {name: name, count: count, registration: @db.registration(name)}
        })
      elsif method == "GET" && parts.size == 3 && parts[0] == "types" && parts[2] == "tags"
        respond(context, @db.tag_keys(parts[1]))
      elsif method == "GET" && parts.size == 4 && parts[0] == "types" && parts[2] == "tags"
        respond(context, @db.tag_values(parts[1], parts[3], page_param(context, "limit", 100)))
      elsif method == "POST" && parts.size == 3 && parts[0] == "types" && parts[2] == "promote"
        body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
        respond(context, {promoted: @db.promote(parts[1], body["trait"].as_s, body["value"].as_s)})
      elsif method == "GET" && parts == ["assets"]
        list(context)
      elsif parts.size == 2 && parts[0] == "assets" && id
        case method
        when "GET"    then show(context, id)
        when "PATCH"  then update(context, id)
        when "DELETE" then delete(context, id)
        else               error(context, 405, "#{method} isn't allowed here")
        end
      elsif method == "GET" && parts.size == 3 && parts[0] == "assets" && parts[2] == "object" && id
        object(context, id)
      elsif method == "POST" && parts == ["maintenance", "check"]
        respond(context, @db.check_consistency)
      elsif method == "POST" && parts == ["maintenance", "vacuum"]
        body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
        respond(context, @db.vacuum(delete_missing_rows: body["delete_missing_rows"]?.try(&.as_bool) || false,
          delete_orphan_objects: body["delete_orphan_objects"]?.try(&.as_bool) || false))
      else
        error(context, 404, "No such endpoint")
      end
    end

    private def list(context) : Nil
      params = context.request.query_params
      type = params["type"]? || raise ArgumentError.new("type is required")
      tags = {} of String => String
      params.each { |name, value| tags[name.lchop("tag.")] = value if name.starts_with?("tag.") }
      limit = page_param(context, "limit", PAGE)
      offset = page_param(context, "offset", 0, max: Int32::MAX)
      assets = @db.list_assets(type, tags, limit, offset)
      tags_by_id = @db.load_tags_batch(assets.map(&.id))
      respond(context, {
        total:  @db.count_pool_assets(type, tags),
        limit:  limit,
        offset: offset,
        assets: assets.map { |rec| {asset: rec, tags: tags_by_id[rec.id]? || {} of String => String} },
      })
    end

    private def show(context, id : Int64) : Nil
      found = @db.get_with_meta_by_id(id, touch: false) || return error(context, 404, "No asset #{id}")
      rec, meta = found
      respond(context, {asset: rec, tags: @db.load_tags(id), custom: @db.custom_traits(id), meta: meta})
    end

    private def update(context, id : Int64) : Nil
      @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
      body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
      tags = body["tags"]?.try(&.as_h.transform_values(&.as_s))
      rec = @db.update_asset(id, tags: tags, description: body["description"]?.try(&.as_s),
        flagged: body["flagged"]?.try(&.as_bool), rating: body["rating"]?.try(&.as_i))
      respond(context, {asset: rec, tags: @db.load_tags(id)})
    end

    private def delete(context, id : Int64) : Nil
      @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
      @db.delete_asset(id)
      respond(context, {deleted: id})
    end

    # Streamed through the DB from whichever storage it has, so a client
    # needs nothing but this API, even for a bucket.
    private def object(context, id : Int64) : Nil
      rec = @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
      storage = @db.storage || return error(context, 503, "This store has no storage")
      return error(context, 404, "Asset #{id}'s object isn't in the store") unless storage.exists?(rec.file_path)
      context.response.content_type = rec.content_type
      context.response.headers["Cache-Control"] = "private, max-age=3600"
      @db.open(rec) { |io| IO.copy(io, context.response) }
    end

    private def authorized?(context, write : Bool) : Bool
      given = context.request.headers["Authorization"]?.try(&.lchop?("Bearer "))
      if write
        token = @write_token || (error(context, 403, "Writes aren't enabled"); return false)
        return true if given && Crypto::Subtle.constant_time_compare(given, token)
        error(context, 403, "Writes need the write token")
        false
      else
        tokens = [@read_token, @write_token].compact
        return true if @read_token.nil? || (given && tokens.any? { |token| Crypto::Subtle.constant_time_compare(given, token) })
        error(context, 401, "Reads need a token")
        false
      end
    end

    private def page_param(context, name : String, default : Int32, max : Int32 = MAX_PAGE) : Int32
      value = context.request.query_params[name]?
      return default unless value
      number = value.to_i? || raise ArgumentError.new("#{name} must be a number")
      raise ArgumentError.new("#{name} must be 0 to #{max}") unless 0 <= number <= max
      number
    end

    private def respond(context, value) : Nil
      context.response.content_type = "application/json"
      value.to_json(context.response)
    end

    private def error(context, status : Int32, message : String?) : Nil
      context.response.status_code = status
      respond(context, {error: message || "error"})
    end
  end
end
