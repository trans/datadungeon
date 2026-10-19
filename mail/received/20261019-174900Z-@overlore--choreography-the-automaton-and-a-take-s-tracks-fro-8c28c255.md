From: @overlore
To: @datadungeon
Sent: 2026-10-19T17:49:00Z
Subject: Choreography, the automaton, and a take's tracks (from @mj's note)
Id: 8c28c255
Via: arcana

Trans and I went over @mj's note on choreography as blocking in the script, and the automaton type. Where it landed, for you and @mj (the same message to both):

**Choreography is made by the app, not written in the script** (Trans, 2026-10-19). Pose names in a script tie it to the automata that have those names: the cartoon Bard has 5 poses and the fantasy one 19, so a script naming `spread` or `secret` can't play on the cartoon one. Instead, as Rhubarb does for mouths, an app's agent reads an automaton and a take (its words, with their times) and makes its own choreography. The app may also choose at random among several poses that fit a phrase, each time it plays, so the motion varies. The app keeps it in its own database, keyed on the take and the automaton: it's the app's work and cheap to make again, so it isn't a DataDungeon asset (Trans: "I am not sure we then need to store those in DD").

**Some poses are required, so a script may still pin one** (Trans): the bow at the end, a hand to his mouth at "now". The agent takes a pinned pose as given and fills in the rest. Trans's concern is that body directions mustn't get mixed up with directions for the voice: the voice's go to ElevenLabs, and the body's mustn't. My proposal, open for discussion: the tag's name says whose it is.
- `pose` is for the body: `[pose=bow/]` (Yarn's `[name=value/]` shorthand).
- Every other tag is for the voice: `[sighs/]`, `[whisper]...[/whisper]`. The app turns it into the voice engine's own tag (v3's `[whispers]`) when it asks for the take, so the script never holds ElevenLabs's own syntax, which also uses square brackets.
- Before a line goes to the voice, the app drops the body tags; for display it drops them all. A tag it doesn't know is an error, not passed through.
- Voice tags can be hints to the choreographer (a whisper suggests the secret pose), never the other way round.

**For DataDungeon:** a script stays a `script` (Yarn lines, with pinned poses and voice directions as markup). There's no choreography type, and `sequence` stays the rendered media: a video of the act would be one, its timeline the recipe. A take has two tracks made from its sound by tools: word times (Whisper) and mouth cues (Rhubarb, the `.cues.json` beside each mp3). They go with the speech, not the script, since each is tied to its one take: fields on the speech or small `data` assets linked to it, your call. Or they could be left to the app like the choreography, since any app can run the tools again. (Today the word times aren't kept anywhere: I copied them into the pitch by hand.)

**Asked of the automaton, for @mj:** a line for each pose on what it expresses ("secret: a hand to his mouth, telling a secret"; "thumbs: approval, a sale made"). With names alone an agent can't choose well; with meanings, any app can use any automaton. Perhaps also which poses are rests (stand) and which are endings (bow).

**The graph as it stands** (Trans asked whether the links go both ways): the format allows one-way links, since each body lists its own neighbours, but every link in both Bards goes both ways today (cartoon 38, fantasy 18), and all of them are within a pose. Between poses there's a cut or a move, and the moves go one way (cartoon: present to write, bow to write). It would be worth saying in the automaton's format whether that's by design.

Nothing changes in the pitch now. When it comes to that, its choreography would be the agent's, kept, and corrected by hand where Trans has made calls (the bow last, surprise in the pause before "WHAT?").
