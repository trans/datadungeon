require "digest/sha256"
require "json"

module DataDungeon
  # How an asset was made, in the shape every app shares (DESIGN-recipes.md):
  # its form, the settings it was made with, what its provider was sent (the
  # prompt, and for speech and text the instructions beside it), the named
  # wordings that went into that, and what's its own (seed, cost, when, the
  # files it was made from). An asset made in steps has a recipe per step
  # (`steps`).
  struct Recipe
    include JSON::Serializable

    # What a recipe makes; empty for a step without a prompt (a matte, a
    # depth map) or for a recipe made of `steps`.
    FORMS = %w[picture speech text]

    # A wording's version is this many hex characters of its words'
    # SHA-256 (40 bits), so it names the same words in every store.
    VERSION_SIZE = 10

    # A named wording a recipe used, from the store's registry: what kind of
    # wording it is (`style`, `flavor`, `rating`, `framing`, `character`,
    # `theme`, ...), its name and its words. A name is `owner:name` going in
    # and `owner:name@version` coming back; the owner is the app that wrote
    # the wording (its consumer name), or `dd` for DataDungeon's own. A name
    # may add what the wording is for, `owner:name/purpose`, so two wordings
    # of one style in use at once share its name
    # (`overlore:silver-comic/figure`, `overlore:silver-comic/place`).
    struct Wording
      include JSON::Serializable

      getter kind : String
      getter name : String
      getter text : String

      def initialize(@kind : String, @name : String, @text : String)
      end

      # {owner, name, purpose, version}: the purpose empty when there's
      # none, the version nil when not given.
      def handle : {String, String, String, String?}
        base, at, version = @name.partition('@')
        owner, colon, rest = base.partition(':')
        name, slash, purpose = rest.partition('/')
        unless colon == ":" && DB::LABEL.matches?(owner) && DB::LABEL.matches?(name) &&
               (slash.empty? || DB::LABEL.matches?(purpose)) && (at.empty? || Recipe.version?(version))
          raise ArgumentError.new("a wording's name is owner:name or owner:name/purpose, with @version " \
                                  "(#{VERSION_SIZE} hex characters of its words' SHA-256) to name one wording " \
                                  "(#{@name.inspect})")
        end
        {owner, name, purpose, at.empty? ? nil : version}
      end

      # How a wording is named: `owner:name`, `/purpose` when it has one,
      # and `@version` when there is one.
      def self.handle(owner : String, name : String, purpose : String, version : String? = nil) : String
        String.build do |io|
          io << owner << ':' << name
          io << '/' << purpose unless purpose.empty?
          io << '@' << version if version
        end
      end
    end

    getter form : String
    getter settings : Hash(String, JSON::Any)
    # What the provider was sent: a picture's prompt, the words a speech
    # step speaks, a text step's input.
    getter prompt : String?
    # The provider's second input, beside the prompt: a voice's
    # instructions, a text step's instructions. A picture has none.
    getter instructions : String?
    # The named wordings that went into the prompt and instructions, each
    # word for word.
    getter wordings : Array(Wording)
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

    def initialize(@form : String, settings : Hash = {} of String => JSON::Any, @prompt : String? = nil,
                   @instructions : String? = nil, @wordings : Array(Wording) = [] of Wording,
                   seed : Int? = nil, cost : Number? = nil, @cost_basis : String? = nil,
                   @generated_at : Time? = nil, @references : Array(String) = [] of String,
                   @steps : Array(Recipe) = [] of Recipe)
      @settings = JSON.parse(settings.to_json).as_h
      @seed = seed.try(&.to_i64)
      @cost = cost.try(&.to_f64)
    end

    # A recipe made of steps, each a recipe of its own, in order.
    def self.in_steps(steps : Array(Recipe)) : Recipe
      new("", steps: steps)
    end

    # A named wording of some kind, `owner:name` or `owner:name/purpose`.
    def self.wording(kind : String, name : String, text : String) : Wording
      Wording.new(kind, name, text)
    end

    # The version of these words: the start of their SHA-256, in hex.
    def self.version(text : String) : String
      Digest::SHA256.hexdigest(text)[0, VERSION_SIZE]
    end

    # Whether this is written as a version is.
    def self.version?(version : String) : Bool
      version.size == VERSION_SIZE && version.each_char.all? { |char| char.ascii_number? || ('a'..'f').includes?(char) }
    end

    # Raises ArgumentError for a recipe that isn't in the standard shape:
    # among others, a wording whose words aren't in what was sent, word for
    # word.
    def check : Nil
      unless @steps.empty?
        unless @form.empty? && @settings.empty? && @prompt.nil? && @instructions.nil? && @wordings.empty? &&
               @seed.nil? && @cost.nil? && @cost_basis.nil? && @generated_at.nil? && @references.empty?
          raise ArgumentError.new("a recipe made of steps has nothing of its own: each step says it")
        end
        raise ArgumentError.new("a recipe's steps are recipes without steps") unless @steps.all?(&.steps.empty?)
        @steps.each(&.check)
        return
      end
      unless @form.empty? || FORMS.includes?(@form)
        raise ArgumentError.new("a recipe's form is #{FORMS.join(", ")}, or empty for a step without a prompt")
      end
      if @form.empty? && !(@prompt.nil? && @instructions.nil? && @wordings.empty?)
        raise ArgumentError.new("a step without a form has no prompt, instructions or wordings")
      end
      if @form == "picture" && @instructions
        raise ArgumentError.new("a picture's provider is sent one prompt: instructions are speech's and text's")
      end
      raise ArgumentError.new("the prompt has no words") if @prompt.try(&.empty?)
      raise ArgumentError.new("the instructions have no words") if @instructions.try(&.empty?)
      @wordings.each do |wording|
        raise ArgumentError.new("a wording's kind is lowercase words joined by '-' (#{wording.kind.inspect})") unless DB::LABEL.matches?(wording.kind)
        raise ArgumentError.new("the #{wording.kind} wording #{wording.name} has no words") if wording.text.empty?
        _, _, _, version = wording.handle
        if version && version != Recipe.version(wording.text)
          raise ArgumentError.new("#{wording.name}'s words are version #{Recipe.version(wording.text)}, not #{version}")
        end
        unless @prompt.try(&.includes?(wording.text)) || @instructions.try(&.includes?(wording.text))
          raise ArgumentError.new("the #{wording.kind} wording #{wording.name} isn't in what was sent: a recipe's " \
                                  "wordings are words its prompt or instructions hold word for word")
        end
      end
      raise ArgumentError.new("a cost basis says how a cost was reached; this recipe has no cost") if @cost_basis && @cost.nil?
      raise ArgumentError.new("a cost basis has words") if @cost_basis.try(&.blank?)
      @references.each do |ref|
        raise ArgumentError.new("a reference is a file's SHA-256, in hex (#{ref.inspect})") unless ref.matches?(/\A[0-9a-f]{64}\z/)
      end
    end
  end
end
