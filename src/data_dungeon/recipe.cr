require "json"

module DataDungeon
  # How an asset was made, in the shape every app shares (DESIGN-recipes.md):
  # its form, the settings it was made with, the words it was given by
  # prompt field, and what's its own (seed, cost, when, the files it was
  # made from). An asset made in steps has a recipe per step (`steps`).
  struct Recipe
    include JSON::Serializable

    # Each form's prompt fields in the order they're joined, by field order.
    # A recipe keeps the order it was made in, so what it says was sent
    # reads back the same. Order 1 is 0.13's, which every recipe stored
    # before 0.14 keeps (its preamble renamed framing). Order 2, since 0.14
    # (`@mj` with Thomas, DESIGN-recipes.md): the fixed rules first, then
    # how much is in frame, the look (DataDungeon's words for the art style,
    # the app's flavor of it, the theme), the object (subject, description,
    # staging), and what relates it to pictures that exist: their light, and
    # the directives for this picture last, where the end holds what it's for.
    ORDERS = {
      1 => {
        "picture" => %w[framing subject description staging theme style rules],
        "speech"  => %w[style text],
        "text"    => %w[instructions description],
      },
      2 => {
        "picture" => %w[rules framing style flavor theme subject description staging light directives],
        "speech"  => %w[style text],
        "text"    => %w[instructions description],
      },
    }

    # The order a new recipe is made in.
    ORDER = 2

    # Each form's prompt fields, in the order new recipes are joined.
    FIELDS = ORDERS[ORDER]

    # The words of one prompt field: a text of its own, or a named one. A
    # name is `owner:name` going in and `owner:name@version` coming back;
    # the owner is the app that wrote the wording (its consumer name). A
    # name may add what the wording is for, `owner:name/purpose`, so two
    # wordings of one style in use at once share its name
    # (`overlore:silver-comic/figure`, `overlore:silver-comic/place`).
    struct Text
      include JSON::Serializable

      getter text : String
      getter name : String?

      def initialize(@text : String, @name : String? = nil)
      end

      # {owner, name, purpose, version}: the purpose empty when there's
      # none, the version nil when not given.
      def handle : {String, String, String, Int32?}?
        return nil unless full = @name
        base, _, version = full.partition('@')
        owner, colon, rest = base.partition(':')
        name, slash, purpose = rest.partition('/')
        unless colon == ":" && DB::LABEL.matches?(owner) && DB::LABEL.matches?(name) &&
               (slash.empty? || DB::LABEL.matches?(purpose)) &&
               (version.empty? || version.to_i?.try(&.positive?))
          raise ArgumentError.new("a named text is owner:name or owner:name/purpose, " \
                                  "with @version to name one wording (#{full.inspect})")
        end
        {owner, name, purpose, version.empty? ? nil : version.to_i}
      end

      # How a named text is written: `owner:name`, `/purpose` when it has
      # one, and `@version` when there is one.
      def self.handle(owner : String, name : String, purpose : String, version : Int32? = nil) : String
        String.build do |io|
          io << owner << ':' << name
          io << '/' << purpose unless purpose.empty?
          io << '@' << version if version
        end
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
    # The field order its prompt was joined in (ORDERS): 2 for a new
    # recipe; 1 converts a prompt made in 0.13's order.
    getter order : Int32 = ORDER

    def initialize(@form : String, settings : Hash = {} of String => JSON::Any,
                   @fields : Hash(String, Text) = {} of String => Text, @prompt_sent : String? = nil,
                   seed : Int? = nil, cost : Number? = nil, @cost_basis : String? = nil,
                   @generated_at : Time? = nil, @references : Array(String) = [] of String,
                   @steps : Array(Recipe) = [] of Recipe, @order : Int32 = ORDER)
      @settings = JSON.parse(settings.to_json).as_h
      @seed = seed.try(&.to_i64)
      @cost = cost.try(&.to_f64)
    end

    # This recipe with what the provider was sent.
    def with_prompt_sent(sent : String?) : Recipe
      Recipe.new(@form, @settings, @fields, sent, @seed, @cost, @cost_basis, @generated_at, @references, @steps, @order)
    end

    # A recipe made of steps, each a recipe of its own, in order.
    def self.in_steps(steps : Array(Recipe)) : Recipe
      new("", steps: steps)
    end

    # A prompt field's words, of their own.
    def self.text(text : String) : Text
      Text.new(text)
    end

    # A prompt field's words under a name, `owner:name` or
    # `owner:name/purpose`.
    def self.named(name : String, text : String) : Text
      Text.new(text, name)
    end

    # The prompt fields that have words, joined by one space in the form's
    # order: what a picture's provider is sent, unless `prompt_sent` says
    # otherwise. A field the order doesn't have raises, so a prompt never
    # leaves out words it was given, before anything is paid for.
    def joined : String
      field_names.compact_map { |field| @fields[field]?.try(&.text).presence }.join(" ")
    end

    # The form's fields in this recipe's order; raises for a field it
    # doesn't have.
    private def field_names : Array(String)
      unless forms = ORDERS[@order]?
        raise ArgumentError.new("a recipe's field order is #{ORDERS.keys.join(" or ")}, not #{@order}")
      end
      return [] of String if @fields.empty? && (@form.empty? || !@steps.empty?)
      allowed = forms[@form]?
      if allowed.nil?
        raise ArgumentError.new("a step without a form has no prompt fields") if @form.empty?
        raise ArgumentError.new("a recipe's form is #{forms.keys.join(", ")}, or empty for a step without a prompt")
      end
      unless (unknown = @fields.keys - allowed).empty?
        renamed = unknown.includes?("preamble") ? " (0.14 renamed preamble framing)" : ""
        raise ArgumentError.new("a #{@form} recipe's fields are #{allowed.join(", ")}, not #{unknown.join(", ")}#{renamed}")
      end
      allowed
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
      field_names
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
