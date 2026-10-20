# dd-serve: DataDungeon's JSON API (DataDungeon::API) on its own, next to a
# database, for a browser elsewhere to reach. Configured by environment:
#
#   DD_DATABASE         the SQLite database (required)
#   DD_CACHE_ROOT       local object storage, or
#   DD_S3_BUCKET        a bucket, with DD_S3_ENDPOINT, DD_S3_ACCESS_KEY,
#                       DD_S3_SECRET_KEY, and optionally DD_S3_REGION (auto)
#                       and DD_S3_PREFIX
#   DD_SHARED_STORAGE   1 when other stores keep objects there too: nothing is
#                       deleted from it (Storage#shared?)
#   DD_READ_TOKEN       needed to read; required unless only this machine listens
#   DD_WRITE_TOKEN      enables writes; without it the database opens read-only
#   DD_HOST, DD_PORT    where to listen (127.0.0.1:7077)
#   DD_MATCHES_DIR      where best-match files go (beside the database)
#
# Building it needs the awscr-s3 and usearch shards (usearch builds its C
# library when installed, statically linked), and libtiff 4.5 or later.
require "./data_dungeon/http"
require "./data_dungeon/s3"
require "./data_dungeon/matches"
require "./data_dungeon/tiff"

def setting(name : String) : String?
  ENV[name]?.presence
end

def required(name : String) : String
  setting(name) || abort "dd-serve: #{name} is required"
end

database = required("DD_DATABASE")
shared = setting("DD_SHARED_STORAGE") == "1"
storage =
  if bucket = setting("DD_S3_BUCKET")
    DataDungeon::S3Storage.new(bucket, endpoint: required("DD_S3_ENDPOINT"), region: setting("DD_S3_REGION") || "auto",
      access_key: required("DD_S3_ACCESS_KEY"), secret_key: required("DD_S3_SECRET_KEY"), prefix: setting("DD_S3_PREFIX") || "",
      shared: shared)
  elsif root = setting("DD_CACHE_ROOT")
    DataDungeon::LocalStorage.new(root, shared: shared)
  else
    abort "dd-serve: set DD_CACHE_ROOT or DD_S3_BUCKET"
  end
read_token = setting("DD_READ_TOKEN")
write_token = setting("DD_WRITE_TOKEN")
host = setting("DD_HOST") || "127.0.0.1"
port = (setting("DD_PORT") || "7077").to_i

unless read_token || host.in?("127.0.0.1", "::1", "localhost")
  abort "dd-serve: listening on #{host} needs DD_READ_TOKEN"
end

db = DataDungeon::DB.new(database, storage, read_only: write_token.nil?)
# Owns the store's match files; a type's index is built on its first match query.
matcher = DataDungeon::MatchIndex.new(db, setting("DD_MATCHES_DIR"))
server = HTTP::Server.new([DataDungeon::API.new(db, read_token: read_token, write_token: write_token,
  matcher: matcher)])
Process.on_terminate do
  server.close
end
address = server.bind_tcp(host, port)
puts "dd-serve: #{database} (#{db.read_only? ? "read-only" : "writable"}) on http://#{address}"
server.listen
matcher.close
db.close
