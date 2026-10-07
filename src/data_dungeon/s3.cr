require "../data_dungeon"
require "awscr-s3"

module DataDungeon
  # Stores objects in an S3-compatible bucket: Cloudflare R2, Garage, MinIO or
  # AWS S3. Optional: `require "data_dungeon/s3"`, and add `awscr-s3` to the
  # application's own shard.yml.
  #
  # Objects are content-addressed, so they never change once written; they're
  # uploaded with long immutable cache headers, which lets a CDN in front of
  # `public_url` serve every repeat. Connections are pooled and kept alive,
  # and a request the service turns away for load (429, 5xx) is retried with
  # backoff. Give DataDungeon a bucket, or a `prefix` within one, of its own:
  # the consistency sweep treats every object under it as DataDungeon's.
  class S3Storage < Storage
    IMMUTABLE = "public, max-age=31536000, immutable"
    RETRYABLE = [429, 500, 502, 503, 504]

    getter bucket : String
    getter prefix : String

    @client : Awscr::S3::Client
    @endpoint : URI
    @region : String
    @access_key : String
    @secret_key : String
    @public_url : String?

    # `public_url` (e.g. a custom domain or CDN in front of the bucket) makes
    # `resolve` return plain URLs; without it, `resolve` returns presigned
    # URLs valid for `url_expires`.
    def initialize(
      @bucket : String,
      *,
      endpoint : String,
      @region : String,
      access_key : String,
      secret_key : String,
      prefix : String = "",
      public_url : String? = nil,
      @url_expires : Time::Span = 1.hour,
      @retries : Int32 = 3,
      pool_size : Int32 = 8,
    )
      @access_key = access_key
      @secret_key = secret_key
      @endpoint = URI.parse(endpoint)
      @prefix = prefix.empty? || prefix.ends_with?('/') ? prefix : "#{prefix}/"
      @public_url = public_url.try(&.rstrip('/'))
      @client = Awscr::S3::Client.new(@region, access_key, secret_key,
        endpoint: endpoint, client_factory: PooledClientFactory.new(pool_size))
    end

    # A Cloudflare R2 bucket in the given account.
    def self.r2(account_id : String, bucket : String, *, access_key : String, secret_key : String,
                prefix : String = "", public_url : String? = nil, url_expires : Time::Span = 1.hour,
                retries : Int32 = 3, pool_size : Int32 = 8) : S3Storage
      new(bucket, endpoint: "https://#{account_id}.r2.cloudflarestorage.com", region: "auto",
        access_key: access_key, secret_key: secret_key, prefix: prefix, public_url: public_url,
        url_expires: url_expires, retries: retries, pool_size: pool_size)
    end

    def write(key : String, bytes : Bytes, content_type : String? = nil) : Nil
      headers = {"Cache-Control" => IMMUTABLE}
      headers["Content-Type"] = content_type if content_type
      retrying { @client.put_object(@bucket, object(key), bytes, headers) }
    end

    def read(key : String) : Bytes
      retrying do
        @client.get_object(@bucket, object(key)) { |response| response.body_io.getb_to_end }
      end
    end

    def exists?(key : String) : Bool
      retrying { @client.head_object(@bucket, object(key)) }
      true
    rescue ex : Awscr::S3::Exception
      raise ex unless ex.status == HTTP::Status::NOT_FOUND
      false
    end

    # S3 reports success for a missing object too, so this is a no-op then.
    def delete(key : String) : Nil
      retrying { @client.delete_object(@bucket, object(key)) }
    end

    def list_keys : Array(String)
      keys = [] of String
      pages = @client.list_objects(@bucket, prefix: @prefix.empty? ? nil : @prefix)
      pages.each do |page|
        page.contents.each { |entry| keys << entry.key.lchop(@prefix) }
      end
      keys
    end

    def resolve(key : String) : String
      if base = @public_url
        return "#{base}/#{object(key)}"
      end
      options = Awscr::S3::Presigned::Url::Options.new(
        aws_access_key: @access_key, aws_secret_key: @secret_key, region: @region,
        object: "/#{object(key)}", bucket: @bucket, expires: @url_expires.total_seconds.to_i,
        endpoint: @endpoint.to_s, force_path_style: true)
      Awscr::S3::Presigned::Url.new(options).for(:get)
    end

    private def object(key : String) : String
      "#{@prefix}#{key}"
    end

    # Every call here is safe to repeat: a PUT of the same bytes to the same
    # content-addressed key, a GET, a HEAD or a DELETE.
    private def retrying(&)
      attempt = 0
      loop do
        return yield
      rescue ex : Awscr::S3::Exception
        status = ex.status
        raise ex unless status && RETRYABLE.includes?(status.code) && attempt < @retries
        sleep (0.2 * 2 ** attempt).seconds
        attempt += 1
      end
    end

    # Keeps HTTP clients alive between requests, instead of awscr-s3's default
    # of a new connection (and TLS handshake) per request. The signer is
    # attached once, when a client is created: awscr-s3 attaches it on every
    # acquire, which would stack signing callbacks on a reused client. A
    # client closed after an error reconnects on its next request.
    class PooledClientFactory < Awscr::S3::HttpClientFactory
      def initialize(@max_idle : Int32 = 8)
        @idle = Deque(HTTP::Client).new
        @lock = Mutex.new
      end

      def acquire_client(endpoint : URI, signer : Awscr::Signer::Signers::Interface) : HTTP::Client
        if client = @lock.synchronize { @idle.shift? }
          return client
        end
        client = acquire_raw_client(endpoint)
        attach_signer(client, signer)
        client
      end

      def acquire_raw_client(endpoint : URI) : HTTP::Client
        HTTP::Client.new(endpoint)
      end

      def release(client : HTTP::Client?) : Nil
        return unless client
        kept = @lock.synchronize do
          next false if @idle.size >= @max_idle
          @idle.push(client)
          true
        end
        client.close unless kept
      end
    end
  end
end
