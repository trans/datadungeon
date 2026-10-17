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
  #     GET    /types                      types, counts (current and retired), registrations
  #                                          and every consumer's indexes
  #     GET    /types/:type/tags           tag names and how many assets carry each
  #     GET    /types/:type/tags/:key      a tag's values, most frequent first (?limit=)
  #     GET    /types/:type/views          how many pictures are seen from each named direction
  #     GET    /assets                     a page of assets with their tags, newest first:
  #                                          ?type= &q= (whole words, catt* for a start)
  #                                          &tag.<key>= &link.<rel>=<name> (or <name>.*
  #                                          for it and the names under it, <start>*)
  #                                          &unlinked=<rel> &file_hash=<sha-256>
  #                                          &description_hash=<sha-256> (every asset sharing
  #                                          a description) &text.<kind>=<owner:name> (a
  #                                          wording a recipe used; /<purpose> for one purpose,
  #                                          @<version> for one wording)
  #                                          &limit= &page=<n> or &before=<id>
  #                                          &count=1 (a total), &meta=1 (each picture's fields,
  #                                          and its view readably)
  #                                          picture fields: &field.<name>=<low>..<high> (either
  #                                          end open), &view=<named direction>, &view.side=
  #                                          &view.yaw= &view.pitch= &view.within=<degrees>,
  #                                          and the same for light
  #                                        Listings and counts take current assets, or with
  #                                          ?retired=only retired ones, =include both
  #     GET    /assets/:id                 an asset, its tags, custom tags, metadata (with a
  #                                          picture's view and light readably) and links
  #     GET    /assets/:id/object          its bytes, streamed from the storage
  #     GET    /assets/:id/recipe          how it was made (DB#recipe): what was sent, the
  #                                          wordings it used (owner:name[/purpose]@version),
  #                                          steps included; 404 when it has none
  #     GET    /assets/:id/links           its links, and the links to it
  #     POST   /maintenance/check          check_consistency's report
  #     GET    /objects                    every object key the store's rows use (object_keys),
  #                                          for clearing a shared bucket
  #     GET    /vocabulary                 the shared tags and their values, with their titles
  #                                          (DB#vocabulary), an art style's with DataDungeon's words
  #                                          for it
  #     GET    /types/:type/matches        best matches, given a matcher (MatchIndex):
  #                                          ?trait.<k>=<v> &field.<f>=<v> (view=back-left,
  #                                          dominant-color=#aa3311) &require=a,b &weight.<k>=<n> &limit=
  #     GET    /assets/:id/similar         the assets closest to this one: ?require= &weight.<k>= &limit=
  #
  #     PATCH  /assets/:id                 {tags, description, everywhere, flagged, rating,
  #                                          permanent, image}: update_asset;
  #                                          image holds the fields an application sets, view
  #                                          and light as {side, yaw, pitch, roll}
  #     DELETE /assets/:id
  #     POST   /assets/:id/links           {rel, to (an asset id) or name, data}: link
  #                                          (rel supersedes: supersede)
  #     DELETE /assets/:id/links           ?rel= &to= or &name=: unlink
  #     POST   /assets/:id/retire          retire: hidden, kept, reversible
  #     POST   /assets/:id/reinstate       reinstate
  #     POST   /maintenance/prune          {type, keep_last, retired_before}: delete retired assets
  #     POST   /maintenance/measure        {type, all}: measure_images
  #     PUT    /assets/:id/keyframes       [{at_ms, held, view, light, anchor_x, anchor_y}]:
  #                                          set_keyframes (view and light readably)
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
      write = method.in?("PATCH", "DELETE", "PUT") || (method == "POST" && parts != ["maintenance", "check"])
      return unless authorized?(context, write)
      route(context, method, parts)
    rescue ex : ArgumentError | JSON::ParseException | TypeCastError | KeyError | Time::Format::Error
      error(context, 400, ex.message)
    rescue ex : ReadOnlyError
      error(context, 409, ex.message)
    end

    private def route(context, method : String, parts : Array(String)) : Nil
      id = parts[1]?.try(&.to_i64?)
      if method == "GET" && parts == ["types"]
        retired = @db.asset_types(retired: true)
        respond(context, @db.asset_types.map { |name, count|
          {name: name, count: count, retired: retired[name]? || 0, registration: @db.registration(name),
           indexes: @db.indexes(name)}
        })
      elsif method == "GET" && parts.size == 3 && parts[0] == "types" && parts[2] == "tags"
        respond(context, @db.tag_keys(parts[1], retired: retired_param(context)))
      elsif method == "GET" && parts.size == 3 && parts[0] == "types" && parts[2] == "views"
        respond(context, @db.view_counts(parts[1], retired: retired_param(context)))
      elsif method == "GET" && parts.size == 4 && parts[0] == "types" && parts[2] == "tags"
        respond(context, @db.tag_values(parts[1], parts[3], page_param(context, "limit", 100), retired: retired_param(context)))
      elsif method == "GET" && parts.size == 3 && parts[0] == "types" && parts[2] == "matches"
        matches(context) { |matcher, required, weights, limit|
          picks = prefixed(context.request.query_params, "trait.").merge(prefixed(context.request.query_params, "field."))
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
      elsif method == "GET" && parts == ["objects"]
        respond(context, {objects: @db.object_keys})
      elsif method == "GET" && parts == ["vocabulary"]
        respond(context, {tags: @db.vocabulary})
      elsif parts.size == 2 && parts[0] == "assets" && id
        case method
        when "GET"    then show(context, id)
        when "PATCH"  then update(context, id)
        when "DELETE" then delete(context, id)
        else               error(context, 405, "#{method} isn't allowed here")
        end
      elsif method == "GET" && parts.size == 3 && parts[0] == "assets" && parts[2] == "object" && id
        object(context, id)
      elsif method == "GET" && parts.size == 3 && parts[0] == "assets" && parts[2] == "recipe" && id
        @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
        recipe = @db.recipe(id) || return error(context, 404, "Asset #{id} has no recipe")
        respond(context, {recipe: recipe})
      elsif method == "PUT" && parts.size == 3 && parts[0] == "assets" && parts[2] == "keyframes" && id
        @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
        given = JSON.parse(context.request.body.try(&.gets_to_end) || "[]").as_a
        respond(context, {keyframes: @db.set_keyframes(id, given.map { |keyframe| keyframe_fields(keyframe) })})
      elsif method == "POST" && parts.size == 3 && parts[0] == "assets" && parts[2] == "retire" && id
        @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
        respond(context, {retired: @db.retire(id)})
      elsif method == "POST" && parts.size == 3 && parts[0] == "assets" && parts[2] == "reinstate" && id
        @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
        respond(context, {reinstated: @db.reinstate(id)})
      elsif parts.size == 3 && parts[0] == "assets" && parts[2] == "links" && id
        case method
        when "GET"    then respond(context, {from: @db.links_from(id), to: @db.links_to(id)})
        when "POST"   then link(context, id)
        when "DELETE" then unlink(context, id)
        else               error(context, 405, "#{method} isn't allowed here")
        end
      elsif method == "POST" && parts == ["maintenance", "check"]
        respond(context, @db.check_consistency)
      elsif method == "POST" && parts == ["maintenance", "prune"]
        body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
        before = body["retired_before"]?.try { |date| Time.parse_utc(date.as_s, date.as_s.size == 10 ? "%F" : DB::TIME_FORMAT) }
        respond(context, {pruned: @db.prune(body["type"].as_s, keep_last: body["keep_last"]?.try(&.as_i) || 0,
          retired_before: before)})
      elsif method == "POST" && parts == ["maintenance", "measure"]
        body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
        respond(context, {measured: @db.measure_images(body["type"]?.try(&.as_s), all: body["all"]?.try(&.as_bool) || false)})
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
      tags, links, texts = prefixed(params, "tag."), prefixed(params, "link."), prefixed(params, "text.")
      file_hash, description_hash = params["file_hash"]?, params["description_hash"]?
      limit = page_param(context, "limit", PAGE)
      page = page_param(context, "page", 1, max: Int32::MAX // MAX_PAGE)
      raise ArgumentError.new("page counts from 1") if page < 1
      before = params["before"]?.try { |value| value.to_i64? || raise ArgumentError.new("before must be an asset id") }
      retired = retired_param(context)
      image = image_filter(params)
      assets = @db.list_assets(type, tags, q: q, links: links, unlinked: unlinked, limit: limit,
        offset: (page - 1) * limit, before: before, retired: retired, image: image,
        file_hash: file_hash, description_hash: description_hash, texts: texts)
      tags_by_id = @db.load_tags_batch(assets.map(&.id))
      metas = params["meta"]? == "1" ? @db.load_image_meta_batch(assets.map(&.id)) : nil
      respond(context, {
        assets: assets.map do |rec|
          meta = metas.try(&.[rec.id]?)
          {asset: rec, tags: tags_by_id[rec.id]? || {} of String => String,
           meta: meta, view: meta.try(&.view).try { |view| readable(view) }}
        end,
        page:  page,
        next:  assets.size == limit ? assets.last?.try(&.id) : nil,
        total: params["count"]? == "1" ? @db.count_assets(type, tags, q: q, links: links, unlinked: unlinked, retired: retired, image: image,
                  file_hash: file_hash, description_hash: description_hash, texts: texts) : nil,
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

    # The picture fields a listing asks for, or nil for none.
    private def image_filter(params : URI::Params) : ImageFilter?
      ranges = prefixed(params, "field.").transform_values do |range|
        low, dots, high = range.partition("..")
        low, high = low.presence.try(&.to_f64), high.presence.try(&.to_f64)
        dots.empty? ? {low, low} : {low, high}
      rescue ArgumentError
        raise ArgumentError.new("a field's range is <low>..<high>, either end open, not #{range}")
      end
      view, light = direction_param(params, "view"), direction_param(params, "light")
      named = params["view"]?
      return nil if ranges.empty? && view.nil? && light.nil? && named.nil?
      ImageFilter.new(ranges, view, params["view.within"]?.try(&.to_f64) || 30.0,
        light, params["light.within"]?.try(&.to_f64) || 30.0, named)
    end

    # A direction from `<name>.side`, `.yaw` and `.pitch`, when any is given.
    private def direction_param(params : URI::Params, name : String) : Direction?
      side, yaw, pitch = params["#{name}.side"]?, params["#{name}.yaw"]?, params["#{name}.pitch"]?
      return nil unless side || yaw || pitch
      Direction.new(side || "front", yaw.try(&.to_f64) || 0.0, pitch.try(&.to_f64) || 0.0)
    end

    # `retired=only` for retired assets, `include` for all, current by default.
    private def retired_param(context) : Bool?
      case value = context.request.query_params["retired"]?
      when nil       then false
      when "only"    then true
      when "include" then nil
      else                raise ArgumentError.new("retired is only or include, not #{value}")
      end
    end

    private def prefixed(params : URI::Params, prefix : String) : Hash(String, String)
      found = {} of String => String
      params.each { |name, value| found[name.lchop(prefix)] = value if name.starts_with?(prefix) }
      found
    end

    private def link(context, id : Int64) : Nil
      body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
      data = body["data"]?.try { |value| value.raw.nil? ? nil : value.to_json }
      @db.link(id, body["rel"].as_s, link_target(body["to"]?.try(&.as_i64), body["name"]?.try(&.as_s)), data)
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
      picture = meta.as?(ImageMeta)
      respond(context, {asset: rec, tags: @db.load_tags(id), custom: @db.custom_traits(id), meta: meta,
                        view: picture.try(&.view).try { |view| readable(view) },
                        light: picture.try(&.light).try { |light| readable(light) },
                        keyframes: picture.try(&.animated) ? @db.load_keyframes(id) : nil,
                        links: {from: @db.links_from(id), to: @db.links_to(id)}})
    end

    private def update(context, id : Int64) : Nil
      @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
      body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
      tags = body["tags"]?.try(&.as_h.transform_values(&.as_s))
      rec = @db.update_asset(id, tags: tags, description: body["description"]?.try(&.as_s),
        everywhere: body["everywhere"]?.try(&.as_bool) || false, flagged: body["flagged"]?.try(&.as_bool), rating: body["rating"]?.try(&.as_i),
        permanent: body["permanent"]?.try(&.as_bool),
        image: body["image"]?.try { |fields| image_fields(fields) })
      respond(context, {asset: rec, tags: @db.load_tags(id)})
    end

    # A direction readably, with its name.
    private def readable(direction : Direction)
      {side: direction.side, yaw: direction.yaw, pitch: direction.pitch, roll: direction.roll, name: direction.name}
    end

    # A number given as either JSON integer or float.
    private def number(value : JSON::Any?) : Float64?
      value.try { |given| given.as_f? || given.as_i.to_f64 }
    end

    # A direction given readably: {side, yaw, pitch, roll}.
    private def direction(value : JSON::Any?) : Direction?
      value.try do |given|
        Direction.new(given["side"]?.try(&.as_s) || "front", number(given["yaw"]?) || 0.0,
          number(given["pitch"]?) || 0.0, number(given["roll"]?) || 0.0)
      end
    end

    private def keyframe_fields(fields : JSON::Any) : ImageKeyframe
      ImageKeyframe.new(fields["at_ms"].as_i, fields["held"]?.try(&.as_bool) || false,
        view: direction(fields["view"]?), light: direction(fields["light"]?),
        anchor_x: number(fields["anchor_x"]?), anchor_y: number(fields["anchor_y"]?))
    end

    # The fields an application sets, from a PATCH body's `image`.
    private def image_fields(fields : JSON::Any) : ImageMeta
      number = ->(name : String) { number(fields[name]?) }
      direction = ->(name : String) { direction(fields[name]?) }
      animation = fields["animation"]?.try do |given|
        ImageAnimation.new(*{"frame_count", "duration_ms", "loop_count", "frame_w", "frame_h", "columns"}.map { |name| given[name]?.try(&.as_i) })
      end
      ImageMeta.new(usage_class: fields["usage_class"]?.try(&.as_s), presentation: fields["presentation"]?.try(&.as_s),
        view: direction.call("view"), light: direction.call("light"),
        anchor_x: number.call("anchor_x"), anchor_y: number.call("anchor_y"), world_width: number.call("world_width"),
        world_height: number.call("world_height"), world_depth: number.call("world_depth"), animation: animation)
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
