# eyarn: Yarn lines with emoji cues

*Draft 2026-10-31. DataDungeon's format (Thomas, 2026-10-31), from what
`@cattacula` described of Mr Monocles' bits (3d9ab3d3). Content type
`text/vnd.datadungeon.eyarn`, extension `.eyarn`. See DESIGN-formats.*

eyarn is Yarn Spinner's line syntax with one addition: an emoji in a line
is a cue for an action, fired where it sits. Every eyarn file parses as
Yarn, since an emoji is only characters in a line, but its meaning differs:
a tool that knows only Yarn would send the emoji to the voice. That's why
it's a format of its own (DESIGN-formats, "A dialect is a format of its
own").

## Lines

As in Yarn and DESIGN-types ("Scripts"): `Speaker: text #tags`, a speaker,
the text, and `#` tags, with directions for the voice in Yarn's markup
(`[sighs/]`) and the one tag for the body, `[pose=bow/]`. eyarn changes
none of that.

## Cues

- **An emoji in a line's text is a cue,** fired at its point in the line:

      Monocles: A gentleman maintains STANDARDS 💅

  The voice says "A gentleman maintains STANDARDS", and the cue 💅 comes
  after "STANDARDS".
- **One emoji is one cue,** a whole emoji as Unicode draws it, so a
  sequence joined into one picture, or with a skin tone, is one cue.
  Emoji side by side are several cues at the same point, in order.
- **A cue followed by "…" holds:** the words and the voice wait until the
  action finishes, then go on.

      Monocles: Tea? 🍵… Splendid.

  "…" is U+2026; three full stops directly after the emoji mean the same.
- **Cues aren't spoken.** The text sent to a voice is the line without its
  cues or their holds, with the spaces around them closed to one.
- **Cues are only in a line's text,** never in `#` tags or in markup.
- **What a cue does is the app's:** a map from each emoji to an action,
  as the voice's tags are the app's to turn into its engine's. An action
  may do more than move: in Cattacula a prop's emoji (🍵 teacup, 🐦 pigeon)
  also sets the prop on stage. The map is not part of the file.

## Open

- An emoji the app's map doesn't have: an error, as an unknown tag is
  (DESIGN-types), or ignored.
- A version: in the content type (`; version=1`) or in the file.
- Whether DataDungeon offers a reader that splits a line into what's
  spoken and its cues with their positions, for any app with a voice.
