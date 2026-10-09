module DataDungeon
  # An asset and how closely it matches what was asked (see MatchIndex).
  struct BestMatch
    include JSON::Serializable

    getter asset : AssetRecord
    getter score : Float64

    def initialize(@asset : AssetRecord, @score : Float64)
    end
  end

  # Finds best matches; MatchIndex (`data_dungeon/matches`) is the one
  # implementation. Declared here so the HTTP API can offer best matches
  # without requiring USearch.
  abstract class Matcher
    abstract def best_matches(asset_type : String, picks : Hash(String, String), *,
                              require required_traits : Array(String) = [] of String,
                              weights : Hash(String, Float64) = {} of String => Float64,
                              limit : Int32 = 10) : Array(BestMatch)

    abstract def similar(id : Int64, *,
                         require required_traits : Array(String) = [] of String,
                         weights : Hash(String, Float64) = {} of String => Float64,
                         limit : Int32 = 10) : Array(BestMatch)

    abstract def close : Nil
  end
end
