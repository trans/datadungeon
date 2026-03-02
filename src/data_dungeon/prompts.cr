require "yaml"

module DataDungeon
  module Prompts
    VALID_ART_STYLES = %w[golden silver fantasy realism 3d manga pixel retro]
    VALID_RACES      = %w[human elf dwarf halfling orc gnome]
    VALID_GENDERS    = %w[m f x]
    VALID_RATINGS    = %w[g pg r x]

    ART_STYLES_YAML = YAML.parse({{ read_file("#{__DIR__}/../../data/art_styles.yml") }})

    SCENE_CONTEXT = ART_STYLES_YAML["scene_context"].as_s + " "

    CHARACTER_FRAMINGS = begin
      arr = [] of String
      ART_STYLES_YAML["character_framings"].as_a.each { |v| arr << v.as_s }
      arr
    end

    ART_STYLES = begin
      h = {} of String => NamedTuple(bg: String, tile: String)
      ART_STYLES_YAML["styles"].as_h.each do |k, v|
        h[k.as_s] = {bg: v["bg"].as_s, tile: v["tile"].as_s}
      end
      h
    end

    DESCRIBE_CHARACTER_PROMPT = <<-PROMPT
      You write image generation prompts. Given character data as JSON, output a comma-separated physical description. Max 50 words. Start with "A" — no "this male" or "standing at."
      Format: "A [height] [body shape] [race] [gender] with [skin] skin, [hair], [facial hair], wearing [outfit]."
      The JSON has measurements in inches and a "phy" score (1-20): 1-4=gaunt, 5-8=soft/doughy, 9-12=average, 13-16=athletic, 17-20=heavily muscular.
      Derive body shape from measurement proportions: broad-shouldered, narrow-waisted, pear-shaped, top-heavy, lanky, stocky, etc. Use relative terms, not raw numbers except height (as X'Y").
      Output ONLY the description. No commentary, no opinions, no narrative.
      PROMPT

    def self.build_portrait_prompt(character_desc : String, art_style : String = "silver") : String
      style = ART_STYLES[art_style]? || ART_STYLES["silver"]
      prompt = String.build do |io|
        io << "Full body character portrait, front view, head to toe. "
        io << character_desc.strip << " "
        io << "Standing pose, facing the viewer. "
        io << "In the style of " << style[:tile].lstrip
        io << "No text, no speech bubbles, no captions."
      end
      clip(prompt, 1500)
    end

    def self.build_prompt(raw_output : String, dm_text : String?, memory_context : String, kind : Symbol, character_desc : String? = nil, art_style : String = "silver", has_reference : Bool = false, player_action : String? = nil, pronoun : String = "they", recent_actions : Array(String)? = nil) : String
      style = ART_STYLES[art_style]? || ART_STYLES["silver"]

      case kind
      when :background
        build_background_prompt(raw_output, style[:bg], character_desc, has_reference)
      when :tile
        build_tile_prompt(raw_output, style[:tile], character_desc, pronoun, recent_actions || [] of String)
      else
        raise ArgumentError.new("Unknown image kind: #{kind}")
      end
    end

    def self.build_centerfold_prompt(raw_output : String, character_desc : String?, art_style : String = "silver") : String
      style = ART_STYLES[art_style]? || ART_STYLES["silver"]
      room_desc = extract_room_description(raw_output)
      char_line = ""
      if cd = character_desc
        stripped = cd.strip.rstrip('.')
        unless stripped.empty?
          framing = CHARACTER_FRAMINGS.sample
          char_line = "Hero shot: #{framing} #{stripped}, prominently featured in the scene. "
        end
      end
      prompt = String.build do |io|
        io << "Wide landscape format. "
        io << room_desc << " "
        io << char_line
        io << "Depict only what is described — nothing more. "
        io << "In the style of " << style[:bg].lstrip
        io << "No text, no UI, no speech bubbles, no captions."
      end
      clip(prompt, 1500)
    end

    private def self.build_background_prompt(raw_output : String, style_prefix : String, character_desc : String?, has_reference : Bool = false) : String
      room_desc = extract_room_description(raw_output)

      char_threshold = has_reference ? 0.50 : 0.25
      include_character = rand < char_threshold
      char_line = ""
      if include_character && character_desc
        stripped = character_desc.strip.rstrip('.')
        unless stripped.empty?
          framing = CHARACTER_FRAMINGS.sample
          if has_reference
            char_line = "The character from the reference image, #{framing} #{stripped}. "
          else
            char_line = "In the scene, #{framing} #{stripped}. "
          end
        end
      end

      prompt = String.build do |io|
        io << "Wide landscape format. "
        io << room_desc << " "
        io << char_line
        io << "Depict only what is described — nothing more. "
        io << "In the style of " << style_prefix.lstrip
        io << "No text, no UI, no speech bubbles, no captions."
      end
      clip(prompt, 1500)
    end

    private def self.build_tile_prompt(raw_output : String, style_prefix : String, character_desc : String?, pronoun : String, recent_actions : Array(String)) : String
      char_line = character_desc.try(&.strip) || ""

      actions = recent_actions.reject { |a|
        a.empty? || a == "(session start)" || a == "(chat)"
      }.last(3)

      room_title = raw_output.lines.map(&.strip).reject(&.empty?).reject { |l| l == ">" }.first? || ""

      prompt = String.build do |io|
        unless actions.empty?
          io << pronoun.upcase << " " << actions.join(" THEN ").upcase << ". "
        end
        io << char_line << ". " unless char_line.empty?
        io << "Location: " << room_title << ". " unless room_title.empty?
        io << "In the style of " << style_prefix.lstrip
        io << "No speech bubbles, no text, no captions, no people being harmed."
      end
      clip(prompt, 1500)
    end

    private def self.extract_room_description(raw_output : String) : String
      lines = raw_output.lines.map(&.strip).reject(&.empty?).reject { |l| l == ">" }
      return clip(raw_output, 500) if lines.size < 2

      title = lines[0]
      desc_lines = lines[1, Math.min(5, lines.size - 1)]
      result = "#{title}. #{desc_lines.join(" ")}"
      clip(result, 500)
    end

    def self.clip(text : String, max_chars : Int32) : String
      stripped = text.strip
      return stripped if stripped.size <= max_chars
      "#{stripped[0, max_chars - 3]}..."
    end
  end
end
