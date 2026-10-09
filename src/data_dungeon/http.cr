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
  #     GET    /assets                     a page of assets with their tags, newest first:
  #                                          ?type= &q= (whole words, catt* for a start)
  #                                          &tag.<key>= &link.<rel>=<name>
  #                                          &unlinked=<rel> &limit= &page=<n> or &before=<id>
  #                                          &count=1 (a total)
  #     GET    /assets/:id                 an asset, its tags, custom tags, metadata and links
  #     GET    /assets/:id/object          its bytes, streamed from the storage
  #     GET    /assets/:id/links           its links, and the links to it
  #     POST   /maintenance/check          check_consistency's report
  #     GET    /types/:type/matches        best matches, given a matcher (MatchIndex):
  #                                          ?trait.<k>=<v> &require=a,b &weight.<k>=<n> &limit=
  #     GET    /assets/:id/similar         the assets closest to this one: ?require= &weight.<k>= &limit=
  #
  #     PATCH  /assets/:id                 {tags, description, flagged, rating}: update_asset
  #     DELETE /assets/:id
  #     POST   /assets/:id/links           {rel, to (an asset id) or name}: link
  #     DELETE /assets/:id/links           ?rel= &to= or &name=: unlink
  #     POST   /types/:type/promote        {trait, value}: promote
  #     POST   /maintenance/vacuum         {delete_missing_rows, delete_orphan_objects}
  class API
    include HTTP::Handler

    PAGE     =  50
    MAX_PAGE = 500

    def initialize(@db : DB, *, @read_token : String? = nil, @write_token : String? = nil, prefix : String = "",
                   @matcher : Matcher? = nil)
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
      elsif method == "GET" && parts.size == 3 && parts[0] == "types" && parts[2] == "matches"
        matches(context) { |matcher, required, weights, limit|
          picks = prefixed(context.request.query_params, "trait.")
          matcher.best_matches(parts[1], picks, require: required, weights: weights, limit: limit)
        }
      elsif method == "GET" && parts.size == 3 && parts[0] == "assets" && parts[2] == "similar" && id
        matches(context) { |matcher, required, weights, limit|
          matcher.similar(id, require: required, weights: weights, limit: limit)
        }
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
      elsif parts.size == 3 && parts[0] == "assets" && parts[2] == "links" && id
        case method
        when "GET"    then respond(context, {from: @db.links_from(id), to: @db.links_to(id)})
        when "POST"   then link(context, id)
        when "DELETE" then unlink(context, id)
        else               error(context, 405, "#{method} isn't allowed here")
        end
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

    # `page` (from 1) numbers pages of `limit`; `next` is the `before` for
    # the following page, or null after the last, for walking through them
    # all. The total is counted only on request (`count=1`): it reads every
    # match.
    private def list(context) : Nil
      params = context.request.query_params
      type, q, unlinked = params["type"]?, params["q"]?, params["unlinked"]?
      tags, links = prefixed(params, "tag."), prefixed(params, "link.")
      limit = page_param(context, "limit", PAGE)
      page = page_param(context, "page", 1, max: Int32::MAX // MAX_PAGE)
      raise ArgumentError.new("page counts from 1") if page < 1
      before = params["before"]?.try { |value| value.to_i64? || raise ArgumentError.new("before must be an asset id") }
      assets = @db.list_assets(type, tags, q: q, links: links, unlinked: unlinked, limit: limit,
        offset: (page - 1) * limit, before: before)
      tags_by_id = @db.load_tags_batch(assets.map(&.id))
      respond(context, {
        assets: assets.map { |rec| {asset: rec, tags: tags_by_id[rec.id]? || {} of String => String} },
        page:   page,
        next:   assets.size == limit ? assets.last?.try(&.id) : nil,
        total:  params["count"]? == "1" ? @db.count_assets(type, tags, q: q, links: links, unlinked: unlinked) : nil,
      })
    end

    private def matches(context, & : Matcher, Array(String), Hash(String, Float64), Int32 -> Array(BestMatch)) : Nil
      matcher = @matcher || return error(context, 404, "Best matches aren't enabled on this server")
      params = context.request.query_params
      required = params["require"]?.try(&.split(',', remove_empty: true)) || [] of String
      weights = prefixed(params, "weight.").transform_values do |weight|
        weight.to_f64? || raise ArgumentError.new("a weight must be a number")
      end
      found = yield matcher, required, weights, page_param(context, "limit", 10, max: 100)
      tags = @db.load_tags_batch(found.map(&.asset.id))
      respond(context, {matches: found.map { |match| {asset: match.asset, tags: tags[match.asset.id]? || {} of String => String, score: match.score} }})
    end

    private def prefixed(params : URI::Params, prefix : String) : Hash(String, String)
      found = {} of String => String
      params.each { |name, value| found[name.lchop(prefix)] = value if name.starts_with?(prefix) }
      found
    end

    private def link(context, id : Int64) : Nil
      body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
      @db.link(id, body["rel"].as_s, link_target(body["to"]?.try(&.as_i64), body["name"]?.try(&.as_s)))
      respond(context, {from: @db.links_from(id)})
    end

    private def unlink(context, id : Int64) : Nil
      params = context.request.query_params
      to = params["to"]?.try { |value| value.to_i64? || raise ArgumentError.new("to must be an asset id") }
      removed = @db.unlink(id, params["rel"]? || raise(ArgumentError.new("rel is required")), link_target(to, params["name"]?))
      respond(context, {removed: removed})
    end

    private def link_target(to : Int64?, name : String?) : Int64 | String
      return to if to && !name
      return name if name && !to
      raise ArgumentError.new("give exactly one of to (an asset id) or name")
    end

    private def show(context, id : Int64) : Nil
      found = @db.get_with_meta_by_id(id, touch: false) || return error(context, 404, "No asset #{id}")
      rec, meta = found
      respond(context, {asset: rec, tags: @db.load_tags(id), custom: @db.custom_traits(id), meta: meta,
                        links: {from: @db.links_from(id), to: @db.links_to(id)}})
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
