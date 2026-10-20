module DataDungeon
  # An asset and how close it came to a search (SemanticIndex): its cosine
  # similarity, or for several facets at once its weakest facet's, with each
  # facet's in `facet_scores`.
  struct SearchHit
    include JSON::Serializable

    getter asset : AssetRecord
    getter score : Float64
    getter facet_scores : Hash(String, Float64)

    def initialize(@asset : AssetRecord, @score : Float64,
                   @facet_scores : Hash(String, Float64) = {} of String => Float64)
    end
  end

  # What a search index holds: the store's embedding model, and how many
  # texts wait to be embedded or failed.
  record SearchStatus, model : String, queued : Int64, failed : Int64 do
    include JSON::Serializable
  end

  # Searches assets by meaning; SemanticIndex (`data_dungeon/semantic`) is
  # the one implementation. Declared here so the HTTP API can offer search
  # without requiring Memo.
  module Searcher
    abstract def search(query : String, limit : Int32 = 10, min_score : Float64? = nil,
                        asset_type : String? = nil, media : String? = nil,
                        tags : Hash(String, String) = {} of String => String,
                        key : String? = nil, key_prefix : String? = nil,
                        facet : String? = nil) : Array(SearchHit)

    abstract def search_facets(queries : Hash(String, String), asset_type : String,
                               limit : Int32 = 10, min_score : Float64? = nil, media : String? = nil,
                               tags : Hash(String, String) = {} of String => String,
                               key : String? = nil, key_prefix : String? = nil,
                               depth : Int32 = 500) : Array(SearchHit)

    abstract def status : SearchStatus
  end
end
