module DataDungeon
  # Optional secondary index attached to the asset database.
  abstract class AssetIndexer
    abstract def enqueue_asset(id : Int64) : Nil
    abstract def delete_asset(id : Int64) : Nil
    abstract def close : Nil
  end
end
