require "json"

module DataDungeon
  # How an asset was made, in the shape every app shares (DESIGN-recipes.md):
  # its form, the settings it was made with, the words it was given by
  # prompt field, and what's its own (seed, cost, when, the files it was
  # made from). An asset made in steps has a recipe per step (`steps`).
  struct Recipe
    include JSON::Serializable

    # Each form's prompt fields, in the order they're joined. A picture's
    # rules come last, where a model takes them as the final word (`@mj`).
    FIELDS = {
      "picture" => %w[preamble subject description staging theme style rules],
      "speech"  => %w[style text],
      "text"    => %w[instructions description],
    }

    # The words of one prompt field: a text of its own, or a named one. A
    # name is `owner:name` going in and `owner:name@version` coming back;
    # the owner is the app that wrote the wording (its consumer name).
    struct Text
      include JSON::Serializable

      getter text : String
      getter name : String?

      def initialize(@text : String, @name : String? = nil)
      end

      # {owner, name, version}, the version nil when not given.
      def handle : {String, String, Int32?}?
        return nil unless full = @name
        base, _, version = full.partition('@')
        owner, colon, name = base.partition(':')
        unless colon == ":" && DB::LABEL.matches?(owner) && DB::LABEL.matches?(name) &&
               (version.empty? || version.to_i?.try(&.positive?))
          raise ArgumentError.new("a named text is owner:name, or owner:name@version (#{full.inspect})")
        end
        {owner, name, version.empty? ? nil : version.to_i}
      end
    end

    # "picture", "speech" or "text"; empty for a step without a prompt (a
    # matte, a depth map) or for a recipe made of `steps`.
    getter form : String
    getter settings : Hash(String, JSON::Any)
    getter fields : Hash(String, Text)
    # What the provider received. For a picture it's kept only where it
    # differs from the fields joined (`joined`).
    getter prompt_sent : String?
    getter seed : Int64?
    # In US dollars.
    getter cost : Float64?
    # How the cost was reached: the service's own bill (`reported: runware`),
    # priced from a rate table (`priced: arcana-ai 0.5.2`), or `estimated`.
    getter cost_basis : String?
    getter generated_at : Time?
    # The files it was made from, by hash.
    getter references : Array(String)
    getter steps : Array(Recipe)

    def initialize(@form : String, settings : Hash = {} of String => JSON::Any,
                   @fields : Hash(String, Text) = {} of String => Text, @prompt_sent : String? = nil,
                   seed : Int? = nil, cost : Number? = nil, @cost_basis : String? = nil,
                   @generated_at : Time? = nil, @references : Array(String) = [] of String,
                   @steps : Array(Recipe) = [] of Recipe)
      @settings = JSON.parse(settings.to_json).as_h
      @seed = seed.try(&.to_i64)
      @cost = cost.try(&.to_f64)
    end

    # This recipe with what the provider was sent.
    def with_prompt_sent(sent : String?) : Recipe
      Recipe.new(@form, @settings, @fields, sent, @seed, @cost, @cost_basis, @generated_at, @references, @steps)
    end

    # A recipe made of steps, each a recipe of its own, in order.
    def self.in_steps(steps : Array(Recipe)) : Recipe
      new("", steps: steps)
    end

    # A prompt field's words, of their own.
    def self.text(text : String) : Text
      Text.new(text)
    end

    # A prompt field's words under a name, `owner:name`.
    def self.named(name : String, text : String) : Text
      Text.new(text, name)
    end

    # The prompt fields that have words, joined by one space in the form's
    # order: what a picture's provider is sent, unless `prompt_sent` says
    # otherwise.
    def joined : String
      (FIELDS[@form]? || [] of String).compact_map { |field| @fields[field]?.try(&.text).presence }.join(" ")
    end

    # Raises ArgumentError for a recipe that isn't in the standard shape.
    def check : Nil
      unless @steps.empty?
        unless @form.empty? && @fields.empty? && @settings.empty? && @prompt_sent.nil? && @seed.nil? &&
               @cost.nil? && @cost_basis.nil? && @generated_at.nil? && @references.empty?
          raise ArgumentError.new("a recipe made of steps has nothing of its own: each step says it")
        end
        raise ArgumentError.new("a recipe's steps are recipes without steps") unless @steps.all?(&.steps.empty?)
        @steps.each(&.check)
        return
      end
      if @form.empty?
        raise ArgumentError.new("a step without a form has no prompt fields") unless @fields.empty?
      elsif allowed = FIELDS[@form]?
        unless (unknown = @fields.keys - allowed).empty?
          raise ArgumentError.new("a #{@form} recipe's fields are #{allowed.join(", ")}, not #{unknown.join(", ")}")
        end
      else
        raise ArgumentError.new("a recipe's form is #{FIELDS.keys.join(", ")}, or empty for a step without a prompt")
      end
      @fields.each do |field, text|
        raise ArgumentError.new("the #{field} field has no words") if text.text.empty?
        text.handle
      end
      raise ArgumentError.new("a cost basis says how a cost was reached; this recipe has no cost") if @cost_basis && @cost.nil?
      raise ArgumentError.new("a cost basis has words") if @cost_basis.try(&.blank?)
      @references.each do |ref|
        raise ArgumentError.new("a reference is a file's SHA-256, in hex (#{ref.inspect})") unless ref.matches?(/\A[0-9a-f]{64}\z/)
      end
    end
  end
end
