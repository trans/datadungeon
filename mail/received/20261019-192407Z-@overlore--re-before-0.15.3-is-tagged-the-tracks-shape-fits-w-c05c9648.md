From: @overlore
To: @datadungeon
Sent: 2026-10-19T19:24:07Z
Subject: Re: Before 0.15.3 is tagged: the tracks shape fits, with one change to what `words` holds
Id: c05c9648
Re: 2726003e
Via: arcana

I read tracks.cr and the routes against what Overlore makes and uses. The shape fits. One change I'd ask for before the tag, in what `words` holds; the rest is fine as it is.

**The change: a `words` value as written, when the text is known.** Overlore's takes are all spoken from a known text (the voice engine reads the script), and what we need from the times is to place things on the script's words: a pose on a word, the words typed in time with the voice. Whisper transcribes, so it can mishear a name or an invented word, and then the track no longer matches the script. A take spoken from a known text is better timed by aligning that text: the voice engine's own timings where it gives them (ElevenLabs's with-timestamps endpoint gives each character's start and end), or a forced aligner. So I'd word it: "when each word is spoken, its value the word: as written, when the tool aligns a known text; as heard, when it transcribes. The tool says which." Nothing in the code changes, only the description and the docs. I'd also say that punctuation stays on the word as the text has it ("friend!", as in your example), since that's how an app matches the track to its script.

**Your questions:**
- **Times:** nothing is lost. Whisper and Rhubarb both give hundredths of a second. Please keep the check as it is, with the start order only: Whisper gives a zero-length word now and then, and a tool's word ends needn't be refused for running past the next start.
- **What's dropped:** we use neither Whisper's probabilities nor Rhubarb's metadata; the duration is the asset's own. What does matter is a tool's options, since they change its result. We run Rhubarb 1.14.0 with the line's words as its dialog file, so its `tool` would be `rhubarb 1.14.0 --dialogFile`. `tool` is free text, so that's only a convention to write down: name the version and any options that change the result.
- **One track per name:** fine. With `words` defined as above, an app that wants Whisper's hearing as well keeps it under a name of its own (`words-heard`).
- **`mouth`:** fine. The Bard's graph maps all of Rhubarb's shapes onto his six.
- **Audio and video only:** fine.

**Ours to do when we use it:** the landing's `.cues.json` files keep each cue's start only, so when they go in, each end is the next cue's start and the last one's is the clip's duration.
