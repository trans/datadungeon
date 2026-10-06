require "../data_dungeon"
require "memo"

module DataDungeon
  # Optional Memo index for descriptions and selected descriptive tags.
  #
  # Stored assets enqueue work; call process_queue from one worker to embed it.
  # Search does not touch DataDungeon usage counters or Memo's search counters.
  class SemanticIndex < AssetIndexer
    SOURCE_TYPE = "asset"

    struct Hit
      getter asset : AssetRecord
      getter score : Float64

      def initialize(@asset : AssetRecord, @score : Float64)
      end
    end

    getter memo : Memo::Service

    # What a search is restricted to: asset type, media, exact tags, and a
    # registered type's pool key or key prefix.
    private record Filter,
      asset_type : String?, media : String?, tags : Hash(String, String),
      pool_key : String?, key_prefix : String? do
      def any? : Bool
        !!(asset_type || media || keyed?) || !tags.empty?
      end

      def keyed? : Bool
        !!(pool_key || key_prefix)
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
      semantic_tag_keys : Array(String) = [] of String,
    )
      @semantic_tag_keys = semantic_tag_keys.to_set
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
      @assets.attach_indexer(self)
    end

    # The asset write has already committed when this runs. Embedding happens
    # later, outside the asset write path.
    def enqueue_asset(id : Int64) : Nil
      index_asset(id)
    end

    # Returns true when the asset was queued for embedding.
    def index_asset(id : Int64) : Bool
      asset = @assets.find_asset_by_id(id)
      return false unless asset

      text = embedding_text(asset.description, @assets.load_tags(id))
      if text.empty?
        delete_asset(id)
        return false
      end

      if source_id = Memo::SourceRegistry.get_internal(@assets.connection, SOURCE_TYPE, id)
        return false if @memo.get_source_text(source_id) == text && vectors_present?(source_id)
      end

      @memo.enqueue(source_type: SOURCE_TYPE, source_id: id, text: text)
      true
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
      end
      queued
    end

    # Run from a single background worker; Memo owns retries and the queue.
    # Saving through Memo checkpoints its journal, so a restart replays only
    # what came after.
    def process_queue : Int32
      processed = @memo.process_queue
      @memo.save_index if processed > 0
      processed
    end

    # Returns up to `limit` hits, best first, each with its score. There is no
    # score cutoff unless `min_score` gives one: scores aren't comparable
    # across embedding models or query lengths, so the threshold belongs to
    # the caller's decision (offering choices vs. reusing an asset outright).
    # `pool_key` ranks only one pool's assets; `key_prefix` (ending in ".",
    # e.g. from DB#group_key_for) only those whose leading traits match.
    def search(
      query : String,
      limit : Int32 = 10,
      min_score : Float64? = nil,
      asset_type : String? = nil,
      media : String? = nil,
      tags : Hash(String, String) = {} of String => String,
      pool_key : String? = nil,
      key_prefix : String? = nil,
    ) : Array(Hit)
      return [] of Hit if limit <= 0
      if (prefix = key_prefix) && !prefix.ends_with?(TraitKey::SEPARATOR)
        raise ArgumentError.new("a key prefix must end with #{TraitKey::SEPARATOR.inspect}")
      end
      tags = @assets.normalize_tags(asset_type, tags) if asset_type
      filter = Filter.new(asset_type, media, tags, pool_key, key_prefix)
      floor = min_score || -1.0 # cosine similarity is never below -1

      # Most filters (including a popular art style) match many assets. Start
      # with nearest neighbors and check just those IDs in SQLite. A rare
      # filter falls back to Memo's complete prefiltered search for recall.
      # A key or prefix names a small set, so it goes straight there.
      unless filter.keyed?
        candidate_limit = Math.max(limit * 4, 40)
        max_candidates = Math.max(limit * 32, 512)
        loop do
          candidates = @memo.search(
            query: query, limit: candidate_limit, min_score: floor,
            include_text: false
          )
          hits = hits_for(candidates, limit, filter)
          return hits if hits.size >= limit
          return hits if candidates.size < candidate_limit
          break if candidate_limit >= max_candidates
          candidate_limit = Math.min(candidate_limit * 2, max_candidates)
        end
      end

      where, args = asset_filter(filter)
      candidates = @memo.search(
        query: query,
        limit: Math.min(limit * 4, 1000),
        min_score: floor,
        source_type: SOURCE_TYPE,
        sql_where: where,
        sql_where_args: args,
        include_text: false,
      )

      hits_for(candidates, limit, filter)
    end

    private def hits_for(candidates : Array(Memo::Search::Result), limit : Int32, filter : Filter) : Array(Hit)
      ids = candidates.compact_map do |candidate|
        candidate.source_type == SOURCE_TYPE ? candidate.source_id.as?(Int64) : nil
      end.uniq
      valid_ids = filter.any? ? matching_ids(ids, filter) : ids.to_set
      seen = Set(Int64).new
      hits = [] of Hit
      candidates.each do |candidate|
        next unless candidate.source_type == SOURCE_TYPE
        id = candidate.source_id.as?(Int64)
        next unless id && valid_ids.includes?(id) && seen.add?(id)
        asset = @assets.get_by_id(id, touch: false)
        next unless asset
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

    def delete_asset(id : Int64) : Nil
      if source_id = Memo::SourceRegistry.get_internal(@assets.connection, SOURCE_TYPE, id)
        @assets.connection.exec("DELETE FROM memo_embed_queue WHERE source_id = ?", source_id)
        @memo.delete(id, SOURCE_TYPE)
      end
    end

    def close : Nil
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

    private def embedding_text(description : String?, tags : Hash(String, String)) : String
      lines = [] of String
      if description && !description.strip.empty?
        lines << description.strip
      end
      tags.keys.sort.each do |key|
        next unless @semantic_tag_keys.includes?(key)
        value = tags[key].strip
        next if value.empty?
        lines << "#{key.tr("_", " ")}: #{value}"
      end
      lines.join("\n")
    end

    private def asset_filter(filter : Filter) : {String?, Array(::DB::Any)}
      return {nil, [] of ::DB::Any} unless filter.any?

      clauses = [] of String
      args = [] of ::DB::Any
      append_filter(clauses, args, filter)
      where = if filter.keyed?
                # Start from the key index: those assets, then their Memo
                # sources (CROSS JOIN keeps that order), so the cost follows
                # the pool's size rather than the catalogue's.
                args << SOURCE_TYPE
                "c.source_id IN (SELECT ms.id FROM assets a CROSS JOIN memo_sources ms " \
                "WHERE #{clauses.join(" AND ")} AND ms.source_type = ? AND ms.external_int = a.id)"
              else
                "EXISTS (SELECT 1 FROM memo_sources ms JOIN assets a ON a.id = ms.external_int " \
                "WHERE ms.id = c.source_id AND #{clauses.join(" AND ")})"
              end
      {where, args}
    end

    private def append_filter(clauses : Array(String), args : Array(::DB::Any), filter : Filter) : Nil
      if key = filter.pool_key
        clauses << "a.pool_key = ?"
        args << key
      end
      if prefix = filter.key_prefix
        clauses << "a.pool_key >= ? AND a.pool_key < ?"
        args << prefix << prefix.rchop + TraitKey::SEPARATOR.succ
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
