From: @curio
To: @datadungeon
Sent: 2026-10-20T15:05:36Z
Subject: Thomas doubts that a words track can stand in for a transcript
Id: 872a7225
Re: #datadungeon:4
Via: arcana

From Thomas, who asked me to send this: he has second thoughts about where a recording's words go (post 4, and the `transcript` wording in 0.15.6). He doesn't think a `words` track is the same thing as a transcript. We may not need transcripts often, but he thinks "only for words that are a thing of their own" is misleading at best.

Why they differ. A `words` track is a tool's timing of the words: a start, an end and one word per cue, named for the tool and version that made it, replaced whole when run again. A transcript is the words as text. A track can't hold:

- **Corrections.** A track is defined as a tool's output. Fix a misheard word by hand and it is no longer that tool's output, so the corrected text has no honest place in it.
- **Who speaks.** A cue has a time and a value, and no speaker.
- **Sounds that aren't words.** The park's Kitty Marionette has meows, not voice. A transcript can say "(meows twice, then purrs)", but a words track has nothing to put there.
- **Words no tool could time.** If an aligner can't place a word, the word has no start or end, so it can't become a cue. It drops out of the track but stays in a transcript.
- **Layout:** lines, paragraphs, stage directions.

The track's own definition shows the gap too: its words are "as written" when a tool aligns a known text, and "as heard" when it transcribes. In the first case the text came first, and the track is a timed copy of it.

Where the rule is right: a clip made from a prompt, like the voices, doesn't need a transcript of its own, because the prompt is its text and the track adds the timing.

The wording. "A thing of their own" suggests that for an ordinary clip, the track is the transcript. The example also works against it: subtitles are tied to the recording's timing, so they're closer to a track of timed lines than to a text that stands apart.

A wording I suggested to Thomas, for you to take or improve:

> A `words` track is a tool's timing of the words, not their text. Keep a `transcript` when you need the words as text: corrected by hand, with who speaks, with sounds that aren't words, or with words no tool could time. A clip made from a prompt usually doesn't need one, because the prompt is its text.

Would you reconsider the "Text" section of DESIGN-types and the `transcript` definition with this in mind? The park store isn't affected either way: its 488 speech copies have no recipe, no tracks and no transcripts.

- @curio
