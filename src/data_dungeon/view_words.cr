require "./asset_record"

module DataDungeon
  # A view or a light in words, for a prompt (from `@mj`'s camera, mj
  # `src/arcana/view.cr` at `f5c0f45`; Thomas, 2026-10-14: DataDungeon owns
  # turning its directions into words). Plain and short: models follow a
  # few words of direction far better than angles. The words say what was
  # asked, never what was drawn, and they're fragments, lowercase with no
  # full stop: where they go and how they're punctuated is the caller's.
  module ViewWords
    # Where the camera stands, in the thing's frame, and the picture's roll.
    def self.view(direction : Direction) : String
      parts = [face(direction)]
      height(direction).try { |words| parts << words }
      tilt(direction.roll).try { |words| parts << words }
      parts.join(", ")
    end

    # Where the light comes from, in the picture's frame.
    def self.light(direction : Direction) : String
      x, y, z = direction.vector
      vertical = if y >= 0.55
                   "from high above"
                 elsif y >= 0.15
                   "from above"
                 elsif y <= -0.55
                   "from below"
                 elsif y <= -0.15
                   "from slightly below"
                 end
      across = if x >= 0.15
                 "the right"
               elsif x <= -0.15
                 "the left"
               end
      behind = z <= -0.5
      return "lit behind the subject, rim-lit" if behind && vertical.nil? && across.nil?
      parts = [] of String
      vertical.try { |words| parts << words }
      across.try { |words| parts << "from #{words}" }
      parts << "from behind" if behind
      parts.empty? ? "evenly lit, no strong direction" : "lit #{parts.join(" and ")}"
    end

    # Which way the thing faces us. Yaw counts toward the thing's own right
    # on both faces, so a full profile at yaw +1 shows its right side, its
    # nose to the picture's left.
    private def self.face(direction : Direction) : String
      return "seen from directly overhead" if direction.pitch > 0.95
      return "seen from directly below" if direction.pitch < -0.95
      turn = direction.yaw.abs
      toward = direction.yaw > 0 ? "right" : "left"
      back = direction.side == "back"
      if turn < 0.12
        back ? "seen from directly behind" : "seen from straight on, facing the viewer"
      elsif turn < 0.45
        back ? "seen from behind, turned slightly to show its #{toward} side" : "seen from slightly to its #{toward}"
      elsif turn < 0.8
        back ? "seen from behind at three-quarters, its #{toward} side toward the viewer" : "a three-quarter view from its #{toward}"
      else
        "seen in full profile, its #{toward} side toward the viewer"
      end
    end

    # How high the camera stands, when it's neither level nor overhead.
    private def self.height(direction : Direction) : String?
      pitch = direction.pitch
      return nil if pitch.abs < 0.12 || pitch.abs > 0.95
      if pitch >= 0.55
        "from high above"
      elsif pitch >= 0.12
        "from slightly above"
      elsif pitch <= -0.55
        "from low down, looking up"
      else
        "from slightly below"
      end
    end

    private def self.tilt(roll : Float64) : String?
      return nil if roll.abs < 0.1
      degrees = (roll * 90).round.to_i
      "the whole image tilted #{degrees.abs}° #{roll > 0 ? "clockwise" : "anticlockwise"}"
    end
  end
end
