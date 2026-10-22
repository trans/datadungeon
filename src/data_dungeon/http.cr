require "http/server"
require "http/formdata"
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
  #                                          wording a recipe used; @<version> for one wording)
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
  #                                          wordings it used (owner:name@version),
  #                                          steps included; 404 when it has none
  #     GET    /assets/:id/links           its links, and the links to it
  #     GET    /assets/:id/tracks          what tools measured of a sound or video over time
  #                                          (DB#tracks): each track's name, tool, made_at and
  #                                          cues [{start_ms, end_ms, value}]
  #     GET    /assets/:id/tracks/:name    one track; 404 when it has none of that name
  #     POST   /maintenance/check          check_consistency's report
  #     GET    /objects                    every object key the store's rows use (object_keys),
  #                                          for clearing a shared bucket
  #     GET    /vocabulary                 the shared tags and their values, with their titles
  #                                          (DB#vocabulary), each rating with DataDungeon's
  #                                          words for it; DataDungeon's asset types
  #                                          (DB::STANDARD_TYPES); and the shared tracks
  #                                          (DB::STANDARD_TRACKS)
  #     GET    /types/:type/matches        best matches, given a matcher (MatchIndex):
  #                                          ?trait.<k>=<v> &field.<f>=<v> (view=back-left,
  #                                          dominant-color=#aa3311) &require=a,b &weight.<k>=<n> &limit=
  #     GET    /assets/:id/similar         the assets closest to this one: ?require= &weight.<k>= &limit=
  #     GET    /search                     assets by meaning, given a searcher (SemanticIndex), best
  #                                          first with their scores: ?q= &type= &media= &tag.<k>=
  #                                          &key= &key_prefix= &facet= (one facet of type) &limit=
  #                                          &min_score=; or one query per facet, &facet.<name>=<q>
  #                                          with type: each asset scores its weakest
  #     GET    /search/status              the store's embedding model, and how many texts wait
  #                                          to be embedded or failed
  #
  #     POST   /assets                     a file added by hand, as multipart/form-data: file
  #                                          (its Content-Type the asset's) and asset, JSON
  #                                          {type, tags, custom, description, permanent,
  #                                          made_at, supersedes, image}; stored as not generated,
  #                                          with no recipe; image as PATCH takes it, plus how
  #                                          to store the file ({compression: "normalize",
  #                                          target_format: "tiff"} for 8-bit 64x64 tiles); 409
  #                                          with asset_id when its type already holds the bytes;
  #                                          413 for a file over max_upload (256 MiB)
  #     POST   /assets/:id/webp            {tags, quality}: a picture's WebP as an asset of its
  #                                          own, its tags with these over them, linked
  #                                          derived-from it (DB#store_webp); 409 as above
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
  #     PUT    /assets/:id/tracks/:name    {tool, cues}: set_track, replacing the track
  #     POST   /types/:type/promote        {trait, value}: promote
  #     POST   /maintenance/vacuum         {delete_missing_rows, delete_orphan_objects}
  class API
    include HTTP::Handler

    PAGE     =  50
    MAX_PAGE = 500
    # The most an upload's file may hold unless `max_upload:` says otherwise,
    # and its asset part (JSON): read no further than that, so a body of any
    # size can't fill the server's memory.
    MAX_UPLOAD     = 256_i64 * 1024 * 1024
    MAX_ASSET_PART = 1_i64 * 1024 * 1024

    # A part of a request bigger than the server takes (413).
    class TooLarge < Exception
    end

    def initialize(@db : DB, *, @read_token : String? = nil, @write_token : String? = nil, prefix : String = "",
                   @matcher : Matcher? = nil, @searcher : Searcher? = nil, @max_upload : Int64 = MAX_UPLOAD)
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
    rescue ex : ArgumentError | JSON::ParseException | TypeCastError | KeyError | Time::Format::Error | ImageProbe::Error
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
      elsif method == "GET" && parts == ["search"]
        search(context)
      elsif method == "GET" && parts == ["search", "status"]
        searcher = @searcher || return error(context, 404, "Search isn't enabled on this server")
        respond(context, searcher.status)
      elsif method == "POST" && parts.size == 3 && parts[0] == "types" && parts[2] == "promote"
        body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
        respond(context, {promoted: @db.promote(parts[1], body["trait"].as_s, body["value"].as_s)})
      elsif method == "GET" && parts == ["assets"]
        list(context)
      elsif method == "POST" && parts == ["assets"]
        upload(context)
      elsif method == "GET" && parts == ["objects"]
        respond(context, {objects: @db.object_keys})
      elsif method == "GET" && parts == ["vocabulary"]
        respond(context, {tags: @db.vocabulary, types: DB::STANDARD_TYPES, tracks: DB::STANDARD_TRACKS})
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
      elsif method == "GET" && parts.size == 3 && parts[0] == "assets" && parts[2] == "tracks" && id
        @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
        respond(context, {tracks: @db.tracks(id)})
      elsif parts.size == 4 && parts[0] == "assets" && parts[2] == "tracks" && id
        @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
        case method
        when "GET"
          track = @db.track(id, parts[3]) || return error(context, 404, "Asset #{id} has no #{parts[3]} track")
          respond(context, {track: track})
        when "PUT"
          body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
          tool = body["tool"]?.try(&.as_s) || raise ArgumentError.new("tool is required: the tool that made the track, with its version")
          cues = Array(TrackCue).from_json((body["cues"]? || raise ArgumentError.new("cues is required")).to_json)
          respond(context, {track: @db.set_track(id, parts[3], cues, tool: tool)})
        else
          error(context, 405, "#{method} isn't allowed here")
        end
      elsif method == "POST" && parts.size == 3 && parts[0] == "assets" && parts[2] == "webp" && id
        @db.find_asset_by_id(id) || return error(context, 404, "No asset #{id}")
        webp(context, id)
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
        before = body["retired_before"]?.try { |date| time(date) }
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

    private def search(context) : Nil
      searcher = @searcher || return error(context, 404, "Search isn't enabled on this server")
      params = context.request.query_params
      type, query, facets = params["type"]?, params["q"]?, prefixed(params, "facet.")
      limit = page_param(context, "limit", 10, max: 100)
      min_score = params["min_score"]?.try { |score| score.to_f64? || raise ArgumentError.new("min_score must be a number") }
      tags, media, key, key_prefix = prefixed(params, "tag."), params["media"]?, params["key"]?, params["key_prefix"]?
      hits = if facets.empty?
               query = query.presence || raise ArgumentError.new("q is required: what to search for")
               searcher.search(query, limit: limit, min_score: min_score, asset_type: type, media: media, tags: tags,
                 key: key, key_prefix: key_prefix, facet: params["facet"]?)
             else
               raise ArgumentError.new("give q or facet.<name>, not both") if query
               type || raise ArgumentError.new("a search by facets needs type")
               searcher.search_facets(facets, type, limit: limit, min_score: min_score, media: media, tags: tags,
                 key: key, key_prefix: key_prefix)
             end
      found = @db.load_tags_batch(hits.map(&.asset.id))
      respond(context, {hits: hits.map { |hit|
        {asset: hit.asset, tags: found[hit.asset.id]? || {} of String => String, score: hit.score,
         facet_scores: hit.facet_scores.empty? ? nil : hit.facet_scores}
      }})
    rescue ex : ArgumentError
      raise ex
    rescue ex
      # Most likely the embedding service, asked for the query's vector.
      error(context, 502, "search failed: #{ex.message}")
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

    # A file added by hand, with no prompt: not generated, so no recipe,
    # and what it shows in words, if anything, as its description.
    private def upload(context) : Nil
      bytes, content_type, fields = nil, nil, nil
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "file"
          raise ArgumentError.new("an upload has one file part") if bytes
          bytes = read_part(part.body, @max_upload, "the file")
          content_type = part.headers["Content-Type"]?
        when "asset"
          raise ArgumentError.new("an upload has one asset part") if fields
          fields = JSON.parse(String.new(read_part(part.body, MAX_ASSET_PART, "the asset part")))
        else raise ArgumentError.new("an upload's parts are file and asset, not #{part.name}")
        end
      end
      file = bytes || raise ArgumentError.new("an upload has a file part: the asset's bytes")
      asset = fields || raise ArgumentError.new("an upload has an asset part: JSON with its type and tags")
      given_type = content_type.presence || raise ArgumentError.new("the file part's Content-Type is the asset's, and it has none")
      rec = @db.store(asset["type"].as_s, asset["tags"]?.try(&.as_h.transform_values(&.as_s)) || {} of String => String,
        bytes: file, content_type: given_type, description: asset["description"]?.try(&.as_s),
        custom: asset["custom"]?.try(&.as_a.map(&.as_s)) || [] of String, permanent: asset["permanent"]?.try(&.as_bool) || false,
        made_at: asset["made_at"]?.try { |made| time(made) }, supersedes: asset["supersedes"]?.try(&.as_i64),
        image: asset["image"]?.try { |fields| image_fields(fields, storing: true) })
      respond(context, {asset: rec, tags: @db.load_tags(rec.id)})
    rescue ex : AlreadyStored
      context.response.status_code = 409
      respond(context, {error: ex.message, asset_id: ex.asset_id, retired: ex.retired?})
    rescue ex : HTTP::FormData::Error | MIME::Multipart::Error
      error(context, 400, "POST /assets takes multipart/form-data, a file part and an asset part (#{ex.message})")
    rescue ex : TooLarge
      error(context, 413, ex.message)
    end

    # A part's bytes, reading no more than one past `limit`.
    private def read_part(io : IO, limit : Int64, what : String) : Bytes
      held = IO::Memory.new
      raise TooLarge.new("#{what} is over #{limit} bytes") if IO.copy(io, held, limit + 1) > limit
      held.to_slice
    end

    # A picture's WebP, stored as its own asset (DB#store_webp).
    private def webp(context, id : Int64) : Nil
      body = JSON.parse(context.request.body.try(&.gets_to_end).presence || "{}")
      rec = @db.store_webp(id, body["tags"]?.try(&.as_h.transform_values(&.as_s)) || {} of String => String,
        quality: body["quality"]?.try(&.as_i) || WebP::QUALITY.to_i)
      respond(context, {asset: rec, tags: @db.load_tags(rec.id)})
    rescue ex : AlreadyStored
      context.response.status_code = 409
      respond(context, {error: ex.message, asset_id: ex.asset_id, retired: ex.retired?})
    end

    # A time given as a date (2026-10-19) or as DataDungeon writes one.
    private def time(value : JSON::Any) : Time
      given = value.as_s
      Time.parse_utc(given, given.size == 10 ? "%F" : DB::TIME_FORMAT)
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
    # The image fields an application sets; when `storing`, also how the
    # file is stored (compression, target_format, quality_floor), which only
    # a store reads.
    private def image_fields(fields : JSON::Any, *, storing : Bool = false) : ImageMeta
      number = ->(name : String) { number(fields[name]?) }
      direction = ->(name : String) { direction(fields[name]?) }
      animation = fields["animation"]?.try do |given|
        ImageAnimation.new(*{"frame_count", "duration_ms", "loop_count", "frame_w", "frame_h", "columns"}.map { |name| given[name]?.try(&.as_i) })
      end
      ImageMeta.new(usage_class: fields["usage_class"]?.try(&.as_s), presentation: fields["presentation"]?.try(&.as_s),
        view: direction.call("view"), light: direction.call("light"),
        anchor_x: number.call("anchor_x"), anchor_y: number.call("anchor_y"), world_width: number.call("world_width"),
        world_height: number.call("world_height"), world_depth: number.call("world_depth"), animation: animation,
        compression: (fields["compression"]?.try(&.as_s) if storing) || "original",
        target_format: storing ? fields["target_format"]?.try(&.as_s) : nil,
        quality_floor: storing ? fields["quality_floor"]?.try(&.as_i) : nil)
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
