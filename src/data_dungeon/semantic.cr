require "../data_dungeon"
require "memo"

module DataDungeon
  # Optional Memo index of what a type's registration says to embed.
  #
  # An asset of a type registered with `embed` (DB#register_type) gets one
  # embedding of those parts: its description as written, then a statement
  # for each tag, by name ("Hair color is red."). A type can also declare
  # facets, each a group of tags embedded on its own as Memo source type
  # `<asset_type>.<facet>`, so a search can rank one part of an asset
  # without the rest diluting it. Types with neither aren't embedded.
  #
  # A store has one embedding model, the first one used: vectors from two
  # models can't be compared, so opening with another raises, unless
  # `switch_model: true` drops the old vectors to embed everything again.
  #
  # Stored assets enqueue work; one worker per store calls catch_up, for what
  # other processes changed, and process_queue to embed it. Search does not
  # touch DataDungeon usage counters or Memo's search counters.
  class SemanticIndex < AssetIndexer
    include Searcher

    SOURCE_TYPE = "asset"

    alias Hit = SearchHit

    # The Memo source type holding one facet of a type's assets.
    def self.facet_source(asset_type : String, facet : String) : String
      "#{asset_type}.#{facet}"
    end

    getter memo : Memo::Service

    # What a search is restricted to: asset type, media, exact tags, and a
    # registered type's key or key prefix (in its own index).
    private record Filter,
      asset_type : String?, media : String?, tags : Hash(String, String),
      key : String?, key_prefix : String? do
      def any? : Bool
        !!(asset_type || media || keyed?) || !tags.empty?
      end

      def keyed? : Bool
        !!(key || key_prefix)
      end
    end

    def initialize(
      @assets : DataDungeon::DB,
      *,
      service : String? = nil,
      format : String? = nil,
      api_key : String? = nil,
      base_url : String? = nil,
      model : String? = nil,
      dimensions : Int32? = nil,
      max_tokens : Int32? = nil,
      chunking_max_tokens : Int32 = 2000,
      query_cache_size : Int32 = 1024,
      switch_model : Bool = false,
    )
      @memo = Memo::Service.new(
        db: @assets.connection,
        service: service,
        format: format,
        api_key: api_key,
        base_url: base_url,
        model: model,
        dimensions: dimensions,
        max_tokens: max_tokens,
        chunking_max_tokens: chunking_max_tokens,
        store_text: true,
        build_vocab: false,
        query_cache_size: query_cache_size,
        persistent_query_cache: false,
        track_matches: false,
      )
      begin
        check_model(switch_model)
      rescue ex
        @memo.close
        raise ex
      end
      @assets.attach_indexer(self)
    end

    # The store's model is the one its vectors were made with. Another
    # service holding vectors means another model's: refused, or with
    # `switch` dropped, so catch_up's first pass embeds everything again.
    private def check_model(switch : Bool) : Nil
      others = @assets.connection.query_all(<<-SQL, @memo.service_id, as: {String, String})
        SELECT s.name, s.model FROM memo_services s
        WHERE s.id <> ? AND EXISTS (SELECT 1 FROM memo_embeddings e WHERE e.service_id = s.id)
      SQL
      return if others.empty?
      unless switch
        raise ArgumentError.new("this store's assets are embedded with #{others.map(&.[1]).join(", ")}, " \
                                "not #{@memo.service_model}, and vectors from two models can't be compared: " \
                                "pass switch_model: true to drop them and embed everything again")
      end
      others.each { |(name, _)| @memo.delete_service(name, force: true) }
    end

    # The store's embedding model, and how many texts wait or failed.
    def status : SearchStatus
      stats = @memo.queue_stats
      SearchStatus.new(@memo.service_model, stats.pending, stats.failed)
    end

    # The asset write has already committed when this runs. Embedding happens
    # later, outside the asset write path.
    def enqueue_asset(id : Int64) : Nil
      index_asset(id)
    end

    # Queues the asset's embedding and each facet's whose text changed, and
    # drops sources it no longer has (a facet removed, or one left with no
    # text). A retired asset is dropped, as a deleted one is, until it is
    # reinstated. Returns true when anything was queued.
    def index_asset(id : Int64) : Bool
      asset = @assets.find_asset_by_id(id)
      if asset.nil? || asset.retired?
        delete_asset(id)
        return false
      end

      texts = {} of String => String
      type = @assets.registration(asset.asset_type)
      if type && !(type.embed.empty? && type.facets.empty?)
        tags = @assets.load_tags(id)
        texts[SOURCE_TYPE] = SemanticIndex.text(type.embed, asset.description, tags) unless type.embed.empty?
        type.facets.each do |facet, parts|
          texts[SemanticIndex.facet_source(type.name, facet)] = SemanticIndex.text(parts, asset.description, tags)
        end
      end
      (sources_of(id) - texts.keys).each { |source_type| delete_source(source_type, id) }

      queued = false
      texts.each { |source_type, text| queued = index_source(source_type, id, text) || queued }
      queued
    end

    private def index_source(source_type : String, id : Int64, text : String) : Bool
      if text.empty?
        delete_source(source_type, id)
        return false
      end
      if source_id = Memo::SourceRegistry.get_internal(@assets.connection, source_type, id)
        return false if @memo.get_source_text(source_id) == text && vectors_present?(source_id)
      end
      @memo.enqueue(source_type: source_type, source_id: id, text: text)
      true
    end

    # Queues what changed since the last call, in this process or another
    # (DB's change log, asset_changes), so assets other programs store become
    # searchable too. The first call, and one the log no longer reaches back
    # to, checks every asset (backfill). Returns the number of assets queued.
    # The worker calls it before process_queue.
    def catch_up : Int64
      latest = latest_change # read first: changes made meanwhile come next time
      seen = @seen
      return 0_i64 if seen && latest <= seen
      # What's embedded may have changed too, and on the first pass another
      # process may have registered since this one opened.
      @assets.refresh_registrations
      oldest = @assets.connection.query_one("SELECT min(seq) FROM asset_changes", as: Int64?)
      queued = 0_i64
      if seen.nil? || oldest.nil? || oldest > seen + 1
        queued = backfill
      else
        changed = @assets.connection.query_all("SELECT DISTINCT asset_id FROM asset_changes WHERE seq > ? AND seq <= ?",
          seen, latest, as: Int64)
        changed.each_with_index do |id, i|
          queued += 1 if index_asset(id)
          Fiber.yield if i % 100 == 99
        end
      end
      @seen = latest
      queued
    end

    @seen : Int64? = nil

    private def latest_change : Int64
      @assets.connection.query_one?("SELECT seq FROM sqlite_sequence WHERE name = 'asset_changes'", as: Int64) || 0_i64
    end

    # Keyset pagination keeps memory bounded for large existing catalogs.
    # Returns the number of assets newly queued.
    def backfill(batch_size : Int32 = 500) : Int64
      raise ArgumentError.new("batch_size must be positive") if batch_size <= 0
      last_id = 0_i64
      queued = 0_i64
      loop do
        ids = [] of Int64
        @assets.connection.query(
          "SELECT id FROM assets WHERE id > ? ORDER BY id LIMIT ?", last_id, batch_size
        ) do |rs|
          rs.each { ids << rs.read(Int64) }
        end
        break if ids.empty?
        ids.each { |id| queued += 1 if index_asset(id) }
        last_id = ids.last
        Fiber.yield # a server answers between batches
      end
      queued
    end

    # Run from a single background worker; Memo owns retries and the queue.
    # Memo saves the index file on its own policy (after many unsaved changes
    # or a few minutes) and on close; until then its journal covers a crash,
    # so saving after every batch would only rewrite the file needlessly.
    def process_queue : Int32
      processed = @memo.process_queue
      @memo.save_index_if_due
      processed
    end

    # Returns up to `limit` hits, best first, each with its score. There is no
    # score cutoff unless `min_score` gives one: scores aren't comparable
    # across embedding models or query lengths, so the threshold belongs to
    # the caller's decision (offering choices vs. reusing an asset outright).
    # `key` ranks only the assets with one key; `key_prefix` (ending in ".",
    # e.g. from DB#group_key_for) only those whose leading traits match.
    # `facet` ranks one of a registered type's facets instead of the whole
    # asset's embedding, and needs `asset_type`.
    def search(
      query : String,
      limit : Int32 = 10,
      min_score : Float64? = nil,
      asset_type : String? = nil,
      media : String? = nil,
      tags : Hash(String, String) = {} of String => String,
      key : String? = nil,
      key_prefix : String? = nil,
      facet : String? = nil,
    ) : Array(Hit)
      return [] of Hit if limit <= 0
      if (prefix = key_prefix) && !prefix.ends_with?(TraitKey::SEPARATOR)
        raise ArgumentError.new("a key prefix must end with #{TraitKey::SEPARATOR.inspect}")
      end
      source = source_for(asset_type, facet)
      tags = @assets.normalize_tags(asset_type, tags) if asset_type
      filter = Filter.new(asset_type, media, tags, key, key_prefix)
      floor = min_score || -1.0 # cosine similarity is never below -1

      # Most filters (including a popular art style) match many assets. Start
      # with nearest neighbors and check just those IDs in SQLite. A rare
      # filter falls back to Memo's complete prefiltered search for recall.
      # A key or prefix names a small set, so it goes straight there.
      unless filter.keyed?
        candidate_limit = Math.max(limit * 4, 40)
        max_candidates = Math.max(limit * 32, 512)
        loop do
          # A facet's vectors are a fraction of the index, so name its source
          # type; the asset's own embedding keeps the unfiltered first try.
          candidates = @memo.search(
            query: query, limit: candidate_limit, min_score: floor,
            source_type: facet ? source : nil, include_text: false
          )
          hits = hits_for(candidates, limit, filter, source)
          return hits if hits.size >= limit
          return hits if candidates.size < candidate_limit
          break if candidate_limit >= max_candidates
          candidate_limit = Math.min(candidate_limit * 2, max_candidates)
        end
      end

      where, args = asset_filter(filter, source)
      candidates = @memo.search(
        query: query,
        limit: Math.min(limit * 4, 1000),
        min_score: floor,
        source_type: source,
        sql_where: where,
        sql_where_args: args,
        include_text: false,
      )

      hits_for(candidates, limit, filter, source)
    end

    # Ranks assets of a registered type on several facets at once, each with
    # its own query (`{"hair" => "long red braids", "body" => "hulking"}`). An
    # asset must have every facet named, and scores its weakest one: a close
    # match on one part doesn't make up for a poor match on another. Each
    # facet is searched to a depth of `depth` assets, so combine within a
    # scope (`key`, `key_prefix`, tags) small enough to be ranked whole.
    def search_facets(
      queries : Hash(String, String),
      asset_type : String,
      limit : Int32 = 10,
      min_score : Float64? = nil,
      media : String? = nil,
      tags : Hash(String, String) = {} of String => String,
      key : String? = nil,
      key_prefix : String? = nil,
      depth : Int32 = 500,
    ) : Array(Hit)
      raise ArgumentError.new("search_facets needs at least one facet query") if queries.empty?
      by_facet = queries.map do |facet, query|
        hits = search(query, limit: depth, asset_type: asset_type, media: media, tags: tags,
          key: key, key_prefix: key_prefix, facet: facet)
        {facet, hits.to_h { |hit| {hit.asset.id, hit} }}
      end
      common = by_facet.map { |_, hits| hits.keys.to_set }.reduce { |shared, ids| shared & ids }
      combined = common.map do |id|
        scores = by_facet.to_h { |facet, hits| {facet, hits[id].score} }
        Hit.new(by_facet.first[1][id].asset, scores.values.min, scores)
      end
      combined.select! { |hit| hit.score >= min_score } if min_score
      combined.sort_by { |hit| {-hit.score, hit.asset.id} }.first(limit)
    end

    private def source_for(asset_type : String?, facet : String?) : String
      return SOURCE_TYPE unless facet
      type = asset_type.try { |name| @assets.registration(name) }
      raise ArgumentError.new("a facet search needs a registered asset_type") unless type
      raise ArgumentError.new("#{type.name} has no facet #{facet}") unless type.facets.has_key?(facet)
      SemanticIndex.facet_source(type.name, facet)
    end

    private def hits_for(candidates : Array(Memo::Search::Result), limit : Int32, filter : Filter, source : String) : Array(Hit)
      ids = candidates.compact_map do |candidate|
        candidate.source_type == source ? candidate.source_id.as?(Int64) : nil
      end.uniq
      valid_ids = filter.any? ? matching_ids(ids, filter) : ids.to_set
      seen = Set(Int64).new
      hits = [] of Hit
      candidates.each do |candidate|
        next unless candidate.source_type == source
        id = candidate.source_id.as?(Int64)
        next unless id && valid_ids.includes?(id) && seen.add?(id)
        asset = @assets.get_by_id(id, touch: false)
        next unless asset && !asset.retired? # retired by a process without this index
        hits << Hit.new(asset, candidate.score)
        break if hits.size >= limit
      end
      hits
    end

    private def matching_ids(ids : Array(Int64), filter : Filter) : Set(Int64)
      matches = Set(Int64).new
      return matches if ids.empty?
      placeholders = Array.new(ids.size, "?").join(", ")
      clauses = ["a.id IN (#{placeholders})"] of String
      args = ids.map(&.as(::DB::Any))
      append_filter(clauses, args, filter)
      @assets.connection.query("SELECT a.id FROM assets a WHERE #{clauses.join(" AND ")}", args: args) do |rs|
        rs.each { matches << rs.read(Int64) }
      end
      matches
    end

    # Removes the asset's embedding and all of its facets'.
    def delete_asset(id : Int64) : Nil
      sources_of(id).each { |source_type| delete_source(source_type, id) }
    end

    private def delete_source(source_type : String, id : Int64) : Nil
      if Memo::SourceRegistry.get_internal(@assets.connection, source_type, id)
        @memo.delete(id, source_type)
      end
    end

    # The Memo source types this index holds for an asset: its own embedding
    # and its facets' (`<asset_type>.<facet>`).
    private def sources_of(id : Int64) : Array(String)
      @assets.connection.query_all(
        "SELECT source_type FROM memo_sources WHERE external_int = ? AND (source_type = ? OR source_type LIKE '%.%')",
        id, SOURCE_TYPE, as: String
      )
    end

    def close : Nil
      @assets.detach_indexer(self)
      @memo.close
    end

    private def vectors_present?(source_id : Int64) : Bool
      found = false
      present = true
      @assets.connection.query(
        "SELECT e.rowid FROM memo_chunks c JOIN memo_embeddings e ON e.hash = c.hash AND e.service_id = ? WHERE c.source_id = ?",
        @memo.service_id, source_id
      ) do |rs|
        rs.each do
          found = true
          present = false unless @memo.usearch_index.contains?(rs.read(Int64).to_u64)
        end
      end
      found && present
    end

    # The text embedded for these parts of an asset: its description as
    # written, then one statement per tag, by name ("Hair color is red."),
    # which searched best of the forms measured (DESIGN-embeddings.md).
    # The parts are a set: any order gives the same text, so the same
    # vector. Empty parts are left out.
    def self.text(parts : Array(String), description : String?, tags : Hash(String, String)) : String
      AssetType.embed_order(parts).compact_map { |part|
        if part == "description"
          description.try(&.strip).presence
        elsif value = tags[part]?.try(&.strip).presence
          statement(part, value)
        end
      }.join("\n")
    end

    # `hair-color`, `red` → "Hair color is red." A `-` or `_` in the name
    # reads as a space, so renaming one to the other re-embeds nothing.
    private def self.statement(name : String, value : String) : String
      sentence = "#{name.tr("_-", "  ").capitalize} is #{value}"
      sentence.ends_with?('.') || sentence.ends_with?('!') || sentence.ends_with?('?') ? sentence : "#{sentence}."
    end

    private def asset_filter(filter : Filter, source : String) : {String?, Array(::DB::Any)}
      return {nil, [] of ::DB::Any} unless filter.any?

      clauses = [] of String
      args = [] of ::DB::Any
      append_filter(clauses, args, filter)
      where = if filter.keyed?
                # Start from the key index: those assets, then their Memo
                # sources (CROSS JOIN keeps that order), so the cost follows
                # the pool's size rather than the catalogue's.
                args << source
                "c.source_id IN (SELECT ms.id FROM assets a CROSS JOIN memo_sources ms " \
                "WHERE #{clauses.join(" AND ")} AND ms.source_type = ? AND ms.external_int = a.id)"
              else
                "EXISTS (SELECT 1 FROM memo_sources ms JOIN assets a ON a.id = ms.external_int " \
                "WHERE ms.id = c.source_id AND #{clauses.join(" AND ")})"
              end
      {where, args}
    end

    private def append_filter(clauses : Array(String), args : Array(::DB::Any), filter : Filter) : Nil
      if key = filter.key
        clause, key_args = @assets.key_clause(TraitKey.type_of(key), key)
        clauses << clause
        args.concat(key_args)
      end
      if prefix = filter.key_prefix
        clause, key_args = @assets.key_clause(TraitKey.type_of(prefix), prefix, prefix: true)
        clauses << clause
        args.concat(key_args)
      end
      if asset_type = filter.asset_type
        # With a key, `+` keeps SQLite on the key index rather than the type's.
        clauses << (filter.keyed? ? "+a.asset_type = ?" : "a.asset_type = ?")
        args << asset_type
      end
      if media = filter.media
        clauses << "a.media = ?"
        args << media
      end
      filter.tags.keys.sort.each do |key|
        clauses << "EXISTS (SELECT 1 FROM asset_tags t WHERE t.asset_id = a.id AND t.tag_key = ? AND t.tag_value = ?)"
        args << key
        args << filter.tags[key]
      end
    end
  end
end
