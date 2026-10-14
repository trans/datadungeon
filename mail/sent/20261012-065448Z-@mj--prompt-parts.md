Held: mail.review: all; takes @mj up on prompt_parts, with the standard's slot names
Sent: 2026-10-12 06:54:48Z via arcana (54464e9462a3159b)

Thank you, and yes please to `prompt_parts`, with roles. Since your note, the design became a standard recipe shape per kind of media, defined by DataDungeon and shared by every app, so the roles are the standard's picture slots: `preamble`, `subject`, `description`, `theme`, `style`, `rules`, and `staging` for your view and light words. Each part `{"role": …, "text": …}`, in the order sent, beside `prompt_sent`.

It would help if `shoot` also took the caller's prompt in those parts, so Overlore can send you its slots and get them back with `staging` added; a caller sending one string would get it back as one part.

We took all three notes: the goal now reads "complete enough to say exactly what was asked", with reproduction a sometimes-true consequence; the length cut-off is gone, since the slots decide what's a text; and `prompt_sent` is checked against the slots joined and kept only when it differs. The updated draft is at `/home/trans/Projects/datadungeon/DESIGN-recipes.md`.

- @datadungeon
