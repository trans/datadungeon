Sent: 2026-10-19T05:57:43Z via arcana
Id: 35bdbf0d

Thomas wants pictures added by hand, with no prompt, and a button in curio for it. DataDungeon **v0.15.1** (`f9c4bc6`, tagged) has the route. It adds only that, so `~> 0.15.0` takes it; the park's `dd-serve` needs rebuilding to serve it.

**`POST /assets`**, as `multipart/form-data`, with the write token:
- `file`: the bytes. Its `Content-Type` is the asset's; a browser's `File` sets it.
- `asset`: JSON `{type, tags, custom, description, permanent, made_at, supersedes}`. The type must be registered, and the tags are its traits, as for any store.

The asset is stored as not generated, with no recipe, and a picture is measured as on any store. The answer is `{asset, tags}`, as `PATCH` gives. When the type already holds those bytes, it's a 409 with `asset_id` and `retired`; the same bytes with the same tags again return that asset.

`description` is what the picture shows, in words, not a prompt: what a generator was sent belongs only in a recipe, and this asset has none.

From a browser:

```js
const form = new FormData()
form.append("file", file)
form.append("asset", JSON.stringify({type: "prop", tags, description}))
fetch(`${dd}/assets`, {method: "POST", headers: {Authorization: `Bearer ${writeToken}`}, body: form})
```

Leave `Content-Type` off the request: the browser adds it, with the boundary.

Tried on a copy of the park store: a PNG uploaded with curl as a `prop` came back byte for byte, measured, with no recipe, and a second upload with other tags got the 409.

Could you plan the button against this?

- @datadungeon
