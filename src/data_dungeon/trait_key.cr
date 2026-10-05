module DataDungeon
  # Canonical trait keys. A key is the values of a type's traits, in the
  # order its registration gives them (most important first), joined by dots:
  # `golden.pg.f.human.tan-skin.long-hair.straight-hair.black-hair`. A trait
  # the asset lacks is an empty segment. The position says which trait a value
  # belongs to, so a prefix ending at a dot (`golden.pg.f.`) matches every
  # asset whose leading traits are equal.
  module TraitKey
    # Recorded with each registered type; changing the format re-derives keys.
    SCHEME = 1

    SEPARATOR = '.'

    # Keys are for matching, not display: Unicode case folding and NFC, with
    # runs of whitespace, dots and commas turned into a single `-`, so a value
    # never contains the separator. A blank value is no value.
    def self.normalize(value : String) : String?
      folded = value.unicode_normalize(:nfc).downcase(Unicode::CaseOptions::Fold).unicode_normalize(:nfc)
      words = folded.split(/[\s.,]+/, remove_empty: true)
      words.empty? ? nil : words.join("-")
    end

    # The key of `traits` (in registration order) over normalized `values`.
    # A trait with a label reads `value-label` (`tan-skin`), for traits whose
    # values alone would be ambiguous to a reader, such as several colours.
    def self.key(traits : Array(String), values : Hash(String, String),
                 labels : Hash(String, String) = {} of String => String) : String
      traits.join(SEPARATOR) do |trait|
        if value = values[trait]?
          (label = labels[trait]?) ? "#{value}-#{label}" : value
        else
          ""
        end
      end
    end

    # The prefix shared by every key whose first `size` traits have these
    # values; empty for `size` 0. It ends at a separator, so it never matches
    # part of a value.
    def self.prefix(traits : Array(String), values : Hash(String, String), size : Int32,
                    labels : Hash(String, String) = {} of String => String) : String
      return "" if size == 0
      key(traits[0, size], values, labels) + SEPARATOR
    end
  end
end
