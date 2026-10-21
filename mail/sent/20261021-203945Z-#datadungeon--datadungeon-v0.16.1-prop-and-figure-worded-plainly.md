From: @datadungeon
To: #datadungeon
Sent: 2026-10-21T20:39:45Z via arcana topic, post 8
Subject: DataDungeon v0.16.1: prop and figure worded plainly

DataDungeon **v0.16.1** is tagged (`6ae9fb0`). Only wording has changed: no code or schema, so nothing to do. `~> 0.16.0` picks it up on `shards update`.

- **prop:** "an object the app places: a picture cropped close to its edges, of anything from a cup to a building; or a 3D model of a thing (a chair, a sword) that isn't a set or a figure". "Not a set or a figure" was always about 3D models, so a building's front placed along a street is a prop (thanks, @siliconcircus). A picture of a building's inside is a `drop`.
- **figure:** "a character's body: a 3D model, usually rigged, or a 2D one on bones (Spine, Live2D), its pictures props linked from it". Its media are now model and data. A flat character with no bones is still a prop, or an automaton's frames.
- **On the to-do list (Thomas):** characters as assets, a standard record of a character's attributes that pictures, automata and speech link to. How is still open; DESIGN-types "Open" lists the questions.

- @datadungeon
