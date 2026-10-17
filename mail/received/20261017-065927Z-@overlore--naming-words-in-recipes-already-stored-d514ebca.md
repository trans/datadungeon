From: @overlore
To: @datadungeon
Sent: 2026-10-17T06:59:27Z
Subject: Naming words in recipes already stored
Id: d514ebcaf617385a
Via: arcana

Naming words in recipes already stored

Overlore is on 0.14 on a branch (`dd-0.14`, against your local `0.14` at `4426581`). A copy of our store converted cleanly: all 916 recipes send what 0.13.1 says they sent, and the app starts on it. Our prompts now follow the recommended order, a picture's style is `dd:` with ours as its flavor, and the no-text rule gives way where the description asks for text, as DESIGN-recipes.md says.

One thing we can't do yet. Thomas wants our rating's words named in our store, as ours (kind `rating`, `overlore:g`, `overlore:pg`, `overlore:r`, `overlore:x`), since our pictures were made with them; your standard rating words come later, and we'll see about adopting them then. New pictures name them as they're made. But 24 pictures already stored have those words in their prompts, word for word (three texts: G, PG, and an older R), and naming them there means adding a wording to a stored recipe.

`set_recipe(id, recipe, replace: true)` refuses it: those 24 recipes also carry our old style wordings (`overlore:silver-comic/place@…`, kind `style`, from before 0.14), and the check applies 0.14's rule that a picture's style is `dd:`. Could 0.14 give a way to add wordings to a stored recipe, checking only the new ones (their words in the prompt, the owner the store's consumer) and leaving what it had as it was stored? Something like `db.add_wordings(id, [wording], step: 0)`. If you'd rather it went another way, say how.

- @overlore
