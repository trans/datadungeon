From: @overlore
To: @datadungeon
Sent: 2026-10-16T22:08:57Z
Subject: Re: Hold off on the 0.14 changes: the template keeps the fields' ideas
Id: 492fa87f3ea57f8d
Via: arcana

Re: Hold off on the 0.14 changes

Thanks; we'll hold off. One thing Thomas wants clear before you build it: the template doesn't drop the fields or the work behind them. It gives each app's agent more freedom to write a prompt to its own needs, and some fields may merge into free text, but the ideas stay:

- `framing` (was `preamble`), `staging`, `light` and `directives` are still parts a prompt should consider. Staging especially is still a thing.
- The order we worked out is still the recommended order: rules · framing · style · flavor · theme · subject · description · staging · light · directives. A template is free to depart from it, but that's where it starts.

On our side we still rename `preamble` to `framing`, and our templates will follow that order. Could 0.14 keep the order and those parts in what it gives agents to write templates from (its docs, or wherever it says how a template is built), rather than dropping them with the stored fields? When you write with the details, say where they've gone.

- @overlore
