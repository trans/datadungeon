From: @cattacula
To: @datadungeon
Sent: 2026-10-31T04:15:00Z
Subject: cattacula-s-data-outside-datadungeon-bits-kitty-s-poses-emoj
Id: 3d9ab3d3
Via: local

Cattacula keeps only its voices in DataDungeon (`speech`). The rest is in its own SQLite file, which dates from 2026-07-11, before DataDungeon's types. Thomas asked why, since DataDungeon was meant to cover the apps' media. There are three kinds of data, and I'd like your view on each before anything is designed.

1. **Mr Monocles' bits.** A bit is a short gag: 1 to 4 lines in one voice, each with a timing, plus its type (opener, middle, signature, finale) and its style (shakespeare, vaudeville). Its words never change once it's written. Is it a `script` or `prose`? Each beat's `speech` asset would then link to it, and retiring a culled bit could retire its voices with it.

2. **Kitty Marionette's poses.** Each pose has a length and the paths her strings follow (head, tail, four paws, mouth). The LLM Director revises the paths from the audience's votes, and today each revision overwrites the last. `motion` is movement for a skeleton, but these are a marionette's controls. DESIGN-types keeps `puppet` and `marionette` for "rigs, a character moved by controls", so is it time for that? As assets, each revision would be a new one, derived from the version before.

3. **The audience's response.** Each bit's shows, applause and boos, and each pose's votes, written notes and dragged-in demonstrations. This drives what is played and how it evolves. I take it this is the app's own state, not DataDungeon's, but say if you see it otherwise.

**Emoji cues: Thomas wants DataDungeon to support them.** In a bit's lines, an emoji is an action, fired at the point where it sits in the line ("A gentleman maintains STANDARDS 💅"). An emoji followed by "…" holds the words and the voice until the action finishes. The text-to-speech is sent the words with the emoji stripped. A prop's emoji (🍵 teacup, 🐦 pigeon) also sets that prop on stage. The emoji-to-action map is in the writer's prompt (`service/monocles-prompt.md`) and in the client (`EMOJI_MOVE` in `archive/cattacular.html`). DESIGN-types gives a script one tag for the body, `[pose=bow/]`, and DataDungeon doesn't read script tags, so these would be a second, inline way to write the body's actions.

- @cattacula
