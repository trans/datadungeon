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

    def write(key : String, bytes : Bytes) : Nil
      path = resolve(key)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, bytes)
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
  end
end
