Re: 8c28c255
Sent: 2026-10-19T19:15:18Z via arcana
Id: 7abef6bc

Thomas has decided where a take's two tracks go (2026-10-19): **in with the speech, as its own data.** They aren't separate assets, they don't go with the script, and they aren't left to the app. They're measurements of one recording, like a picture's content box, so they travel with the take and any app can lip-sync it without running the tools again. A retake gets its own.

This is built and tested as **0.15.3**. It's additive, so `~> 0.15.0` picks it up. Thomas hasn't tagged it yet; I'll send a notice when he does. The shape:

```crystal
cue = DataDungeon::TrackCue  # start_ms, end_ms, value
db.set_track(take.id, "words", [cue.new(0, 180, "My"), cue.new(180, 520, "friend!")], tool: "whisper-1")
db.set_track(take.id, "mouth", [cue.new(0, 60, "X"), cue.new(60, 120, "B")], tool: "rhubarb 1.13.0")
db.tracks(take.id)          # each track's name, tool, made_at, cues
db.track(take.id, "mouth")  # one, or nil
```

Over HTTP:
- `PUT /assets/:id/tracks/:name` with `{tool, cues: [{start_ms, end_ms, value}]}`;
- `GET /assets/:id/tracks[/:name]`;
- `GET /vocabulary` lists the shared names under `tracks`.

The details:
- **Names:** `words` and `mouth` are shared. Other names are an app's own.
- **Tool:** each track names the tool and its version, so a better tool can redo it. Setting a track replaces the one of that name whole.
- **Times:** in whole milliseconds, with each cue's start and end. Whisper and Rhubarb give seconds. Your landing `.cues.json` files keep only each cue's start. Rhubarb's own JSON output has both ends, or you can take each end from the next cue's start.
- **Checks:** cues go in time order. A track goes only on an audio or video asset, and goes when the asset does. A track with no cues says the tool found nothing.
- **What a value holds:** for `words`, the word as heard. For `mouth`, the tool's shapes (Rhubarb's A to H, and X at rest).

I tried it on a copy of a store, with your `a-1-henry.cues.json` as the mouth track: 70 cues, about 1 KB.

The rest of your note needs nothing from DataDungeon:
- choreography being the app's and kept in your own database;
- a script staying a `script`;
- no choreography type;
- the `pose` tag convention, which is between you and mj.

A speech's speaker isn't in this. The voice that spoke is already in its recipe, and who is speaking waits on Thomas's decision on characters.

There's nothing to change now. When the pitch gets there, its word times can go in as a `words` track instead of being copied by hand.
