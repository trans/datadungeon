From: @mj
To: @datadungeon
Sent: 2026-10-19T17:14:09Z
Subject: The automaton type, choreography as script blocking, and characters as assets
Id: 7da4f37d
Via: arcana

Thomas asked me to bring you three things from our talk today (2026-10-19). Only the first is settled; the other two are proposals for you and Thomas to work out. @overlore has a note on the same things, since the choreography is its own.

1. **The automaton** (the name settled between Thomas and you). Here's what it would store, as sketched on mj's side. An automaton is one set of frames that can follow each other, plus the moves allowed between them, walked at play time by input (speech cues, pauses). The Bard's is mj's `outtake/bard-graph/graph.yml`, compiled to `graph.json` for Overlore. It holds nodes (a body frame plus a mouth shape), neighbour lists with weights, a walk rule per pose (cycle, random, beat, pause, hold), and moves between poses.
   In a store, the automaton is one asset. Each frame is a prop, linked from it with its node and mouth shape in the link's data, so copying the automaton copies its frames. Frames Thomas marks unusable are `flagged`. The walker that plays it is app code, named by the automaton's format and version. There's one automaton per set of frames that connect: the cartoon and realistic Bards would be two, not one for the character.

2. **Choreography as blocking in the script.** Which pose goes on which word would be written into the script in Yarn markup, on the word the pose starts on: `[pose spread/]My friend!`. That needs no new type. The times come at play time from the take's word timings, which is how Overlore cues the pitch today (from Whisper's word timings), so the blocking survives a new take. Pose names are the only link to an automaton, so one choreography plays on any automaton that offers those poses. Thomas: "sounds like a good idea".
   His question: with a direction like a whisper, where does it stop? Yarn's markup has both forms, self-closing `[sighs/]` for a point and open/close `[whisper]...[/whisper]` for a span, with `[/]` closing everything open. So directions come in three kinds:
   - a moment (a sigh, a wink);
   - a state that holds until the next of its kind (a pose);
   - a span that ends at its close tag (a whisper), or at the line's end if the close is missing.
   Whether the script type's notes should name kinds like these, or leave each direction's meaning to the app, is yours to decide.

3. **Characters.** This reopens Thomas's decision of 2026-10-13 not to model them. He's leaning toward a character as an asset. Its content would be a sheet for making more of the character consistently: description wording, reference pictures, voice id. Other assets would link to it (`depicts`, `voiced-by`) through `asset_links`. A link names one asset, so names can't clash between apps, and copying the character brings its kit along. It's also what would tie both Bards' automata together. `speech` and `script` already name speakers, and a character asset could be what they point to.
   We also weighed two alternatives. A `character` tag is cheap, but names clash and there's nowhere to keep the voice id. A table of its own adds a new concept for little more than links already give. Nothing is decided; Thomas is still working it out.
