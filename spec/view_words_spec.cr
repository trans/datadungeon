require "spec"
require "../src/data_dungeon"

private def view(side, yaw, pitch, roll = 0.0) : String
  DataDungeon::ViewWords.view(DataDungeon::Direction.new(side, yaw, pitch, roll))
end

private def light(side, yaw, pitch) : String
  DataDungeon::ViewWords.light(DataDungeon::Direction.new(side, yaw, pitch))
end

describe DataDungeon::ViewWords do
  it "words a view and a light as @mj's camera does" do # mj's table, 2026-10-14
    view("front", 0.0, 0.0).should eq "seen from straight on, facing the viewer"
    view("front", 0.5, 0.3).should eq "a three-quarter view from its right, from slightly above"
    view("front", 1.0, 0.0).should eq "seen in full profile, its right side toward the viewer"
    view("back", 0.0, 0.0).should eq "seen from directly behind"
    view("front", 0.0, 0.7).should eq "seen from straight on, facing the viewer, from high above"
    light("front", -0.5, 0.5).should eq "lit from high above and from the left"
  end

  it "words the views and lights between" do
    view("front", -0.3, 0.0).should eq "seen from slightly to its left"
    view("back", 0.6, 0.0).should eq "seen from behind at three-quarters, its right side toward the viewer"
    view("front", 0.0, 1.0).should eq "seen from directly overhead"
    view("front", 0.0, -0.6).should eq "seen from straight on, facing the viewer, from low down, looking up"
    view("front", 0.0, 0.0, 0.5).should eq "seen from straight on, facing the viewer, the whole image tilted 45° clockwise"
    light("front", 0.0, 0.0).should eq "evenly lit, no strong direction"
    light("back", 0.0, 0.0).should eq "lit behind the subject, rim-lit"
    light("front", 0.5, 0.0).should eq "lit from the right"
    light("back", 0.0, 0.5).should eq "lit from high above and from behind"
  end
end
