module DataDungeon
  # Single source of truth: read from shard.yml at compile time so it can't
  # drift from the packaged version.
  VERSION = {{ read_file("#{__DIR__}/../shard.yml").split("version:")[1].split("\n")[0].strip }}
end

require "./data_dungeon/cache"
require "./data_dungeon/prompts"
require "./data_dungeon/asset_record"
require "./data_dungeon/portrait_index"
require "./data_dungeon/webp"
require "./data_dungeon/storage"
require "./data_dungeon/db"
