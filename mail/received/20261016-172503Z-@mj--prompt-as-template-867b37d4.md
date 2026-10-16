From: @mj
To: @datadungeon
Sent: 2026-10-16T17:25:03Z
Subject: Proposal: a picture's prompt as one template
Id: 867b37d4
Via: local

Thomas and I have been rethinking how a picture's prompt is stored, and this is a proposal. It comes before 0.14 is tagged, so the stored recipes would be converted once, not twice.

**Why.** Thomas's first reason for the fields was storage: the same words in every record. Since then:
- Most fields turn out to be registered choices: rules (by rating), framing and the kind's own rules (by kind), style, flavor, theme, a stored character's appearance, and light (computed from the place's measured direction). What's written for each picture is a little free text: description, staging, an edit's change.
- A hand-written prompt doesn't split into fields cleanly. The Bard pictures mj made for Overlore (2026-10-15) were written as one running sentence, with the framing a phrase inside the subject's sentence and "keep the reference's style" in the middle. In 0.14 they'd be stored with no fields and the whole prompt in `prompt_sent`.

**The proposal: one prompt, with Mustache tags for the registered parts.** The app writes its own words with tags around them:

    {{rules}} {{framing overlore:room}} {{style}} {{flavor overlore:golden-comic/place}} {{theme}} A damp cellar, a ladder on the left wall, seen from the doorway. {{light}} {{kind-rules overlore:room}}

- A bare tag takes its value from the asset, where the asset says it: `{{style}}` from its art style, `{{rules}}` from its rating. Otherwise the app names the wording.
- DataDungeon pins every tag to the exact wording and version when it expands the prompt: `{{style}}` becomes `{{style datadungeon:golden-comic@1}}`. The pinned prompt is what's stored, and expanding it gives exactly the text the provider got.
- So the asset's category says what the picture is, and may change later; the stored prompt says what was sent, and doesn't. A picture classified afterwards keeps a true record, and dropping the pins redraws it in its new category.
- A prompt with no tags is plain text. The Bard's would be stored as written, with its art style on the asset.

**What goes away:** the field order (each prompt has its own, and the order we worked out becomes the standard template: advice to apps, not schema); `prompt_sent`, which is always the expansion; the order 1 and 2 recipes; the case of a custom prompt.

**What stays:**
- Named wordings as they are (`named_texts`: field, owner, name, purpose, version), never changed or deleted once a prompt uses them.
- 0.14's checks, made when the prompt is expanded, before anything is paid for: an unknown tag or wording is refused, a style must be DataDungeon's, a flavor must be for the picture's style.
- Looking up the pictures that used a wording (`with_text`). Thomas doesn't expect prompts to be searched, so it can scan the stored prompts rather than keep an index of their references.

**Short references (Thomas).** The pinned references should be short. Two ways:
- **Codes:** `{{style dd:gc@1}}` for `{{style datadungeon:golden-comic@1}}`. Readable in the raw text and the same in every database, but every owner and wording needs a code, unique and never reused.
- **Row ids:** `{{style 12}}`, the wording's `named_texts` row. Nothing new to name, and DataDungeon shows the names when it reads a prompt back. Local to one database, so an export or the hub writes names instead; it has to carry the wordings with the record anyway.

For the six tags in the example: 192 bytes with full names, 118 with codes, 84 with row ids. Thomas prefers row ids, though a person can't easily read them in the raw text.

**Converting what's stored:** each named field becomes a pinned tag and each other field its own words, joined in the recipe's order with one space; a recipe with only `prompt_sent` becomes that text. Expanded, each reads back exactly as it was sent. A repeated text that was never named could be registered as it's converted, so it's still stored once.

**Still to settle:**
- A pinned tag isn't plain Mustache, whose tags are names without arguments, so DataDungeon expands them itself. Should an ordinary Mustache renderer still be able to fill the bare form?
- Light pins the direction and the version of `ViewWords` that turned it into words. How is that written?
- Where is a character's appearance registered, for `{{character overlore:bard}}`?
- A literal `{{` in an app's own words: refused or escaped?

- @mj
