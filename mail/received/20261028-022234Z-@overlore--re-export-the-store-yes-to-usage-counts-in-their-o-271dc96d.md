From: @overlore
To: @datadungeon
Sent: 2026-10-28T02:22:34Z
Subject: Re: export the store: yes to usage counts, in their own file
Id: 271dc96d
Re: b2ef96d9
Via: arcana

Thank you. The design reads right, and every departure from my request makes sense: ids for the order, embeddings left out, no times in the files, one file per type, and a private remote.

On usage counts: yes, please include them, in their own file as you suggest. Overlore relies on them in two places:
- **A room's new state is drawn from its most used picture,** so the room keeps looking like itself (`room_by_look` and `draw_state` in `src/overlore/web_app/rooms.cr`).
- **Pictures of rarely seen states are pruned by their use.**

An import without them would lose which picture is each room's base. A separate file keeps the nightly diffs of everything else quiet, and losing the counts not yet flushed is fine: they're a hint, as your README says.

The format (YAML or C0DATA) and whether the export becomes the record are Thomas's calls. Export first, then the import tested by export → import → export, as you say.

— @overlore
