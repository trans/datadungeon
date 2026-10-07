module DataDungeon
  # Canonical trait keys. A key is the asset type followed by the values of
  # its traits, in the order its registration gives them (most important
  # first), joined by dots:
  # `portrait.golden.pg.f.human.tan-skin.long-hair.straight-hair.black-hair`.
  # A trait the asset lacks is an empty segment. The key alone names its
  # pool, and the position says which trait a value belongs to, so a prefix
  # ending at a dot (`portrait.golden.pg.f.`) matches every asset of the type
  # whose leading traits are equal.
  module TraitKey
    # Recorded with each registered type; changing the format re-derives keys.
    SCHEME = 2 # 1 lacked the type prefix

    SEPARATOR = '.'
    MEMBER    = ','

    # Keys are for matching, not display: Unicode case folding and NFC, with
    # runs of whitespace, dots and commas turned into a single `-`, so a value
    # never contains the separator. A blank value is no value.
    def self.normalize(value : String) : String?
      folded = value.unicode_normalize(:nfc).downcase(Unicode::CaseOptions::Fold).unicode_normalize(:nfc)
      words = folded.split(/[\s.,]+/, remove_empty: true)
      words.empty? ? nil : words.join("-")
    end

    # A set trait's value: its comma-separated members, each normalized,
    # without duplicates, sorted and joined by commas
    # (`"Troll dead, trapdoor open"` gives `trapdoor-open,troll-dead`). No
    # member can contain a comma, since normalizing turns commas into `-`.
    # An empty set is no value.
    def self.normalize_set(value : String) : String?
      members = value.split(MEMBER).compact_map { |member| normalize(member) }.uniq.sort
      members.empty? ? nil : members.join(MEMBER)
    end

    # The key of `type`'s `traits` (in registration order) over normalized
    # `values`. A trait with a label reads `value-label` (`tan-skin`), for
    # traits whose values alone would be ambiguous to a reader, such as
    # several colours.
    def self.key(type : String, traits : Array(String), values : Hash(String, String),
                 labels : Hash(String, String) = {} of String => String) : String
      String.build do |io|
        io << type
        traits.each do |trait|
          io << SEPARATOR
          if value = values[trait]?
            io << value
            io << '-' << labels[trait] if labels.has_key?(trait)
          end
        end
      end
    end

    # The prefix shared by every key of `type` whose first `size` traits have
    # these values; just the type for `size` 0. It ends at a separator, so it
    # never matches part of a value.
    def self.prefix(type : String, traits : Array(String), values : Hash(String, String), size : Int32,
                    labels : Hash(String, String) = {} of String => String) : String
      key(type, traits[0, size], values, labels) + SEPARATOR
    end
  end
end
