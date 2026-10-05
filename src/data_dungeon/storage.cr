require "random/secure"

module DataDungeon
  # Storage backend abstraction. `file_path` on an asset is an opaque *key*;
  # a Storage implementation resolves that key to a real location. This keeps
  # DataDungeon backend-agnostic — local disk today, object stores (R2/S3) later.
  abstract class Storage
    # Write bytes at the given key, creating any containers as needed.
    abstract def write(key : String, bytes : Bytes) : Nil
    # Read the bytes stored at the given key.
    abstract def read(key : String) : Bytes
    # Whether an object exists at the given key.
    abstract def exists?(key : String) : Bool
    # Remove the object at the given key (no-op if absent).
    abstract def delete(key : String) : Nil
    # Enumerate every object key currently in the backend. Used by the
    # consistency sweep to find objects with no owning row. May be expensive
    # on large object stores; intended for maintenance, not the hot path.
    abstract def list_keys : Array(String)
    # Resolve a key to a usable location — a local absolute path here,
    # a URL for object stores.
    abstract def resolve(key : String) : String
  end

  # Local filesystem storage rooted at a directory. Keys are relative paths
  # under the root, e.g. "venue/ab/abcd….webp".
  class LocalStorage < Storage
    getter root : String

    def initialize(@root : String)
    end

    def resolve(key : String) : String
      File.join(@root, key)
    end

    # Writes to a temporary sibling, then renames it into place, so a crash
    # never leaves a truncated object at the key. DB#store skips writing a
    # content-addressed key that already exists, so a partial object there
    # would otherwise be permanent.
    def write(key : String, bytes : Bytes) : Nil
      path = resolve(key)
      Dir.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Random::Secure.hex(8)}.tmp"
      begin
        File.write(tmp, bytes)
        File.rename(tmp, path)
      rescue ex
        File.delete(tmp) if File.exists?(tmp)
        raise ex
      end
    end

    def read(key : String) : Bytes
      File.open(resolve(key), "rb", &.getb_to_end)
    end

    def exists?(key : String) : Bool
      File.file?(resolve(key))
    end

    def delete(key : String) : Nil
      path = resolve(key)
      File.delete(path) if File.exists?(path)
    end

    def list_keys : Array(String)
      return [] of String unless Dir.exists?(@root)
      base = Path[@root]
      keys = [] of String
      Dir.glob(File.join(@root, "**", "*")) do |path|
        next unless File.file?(path)
        keys << Path[path].relative_to(base).to_s
      end
      keys
    end
  end
end
