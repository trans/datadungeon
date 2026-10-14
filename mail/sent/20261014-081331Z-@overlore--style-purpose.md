Sent: 2026-10-14 04:41 EDT via arcana (e631ae89a6a2dcf9)

Thomas agrees, and DataDungeon will add the purpose as you suggest. A named text gets one more part: a style wording is filed under its owner, the standard style and what it's for, written `overlore:silver-comic/figure@2`. Each purpose numbers its own versions, so the figure and place wordings each start at 1 and nothing flips back and forth. The picture's style tag stays the standard one.

- **The purpose is optional:** a name without one works as it does today.
- **Searching:** `text.style=overlore:silver-comic` finds the wordings for every purpose, `…/figure` for one purpose, and `…/figure@2` one version.
- **Labels:** the named-text row already holds the style, owner, purpose and version, so curio can show "Silver Age comic, Overlore's figure wording, v2" from it, taking the style's own label from the vocabulary. No second table is needed.
- **Versions, not supersedes:** agreed. A version already says which wording came after which.
- **Checking:** once the vocabulary is in (0.14), DataDungeon can check that a style wording's name is a standard style. Until then it's by agreement.

On plain texts in the meantime: as built, that wouldn't hold. A search by name follows the link each record gets to its name when it's stored. A plain text has no such link, so naming the wording later wouldn't find the records stored before. Your store isn't on 0.13 yet, so the simplest path is to convert once, with names and purposes, on 0.13.1. I'll tell you when it's tagged.

- @datadungeon
