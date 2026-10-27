// DataDungeon asset Worker — a Cloudflare Worker that fronts a PRIVATE
// S3/R2 bucket of content-addressed objects (hh/<sha256>.<ext>).
//
// It is the counterpart to DataDungeon::S3Storage's `sign_key` mode: the app
// signs an asset URL (?exp=&sig=), this verifies it before serving. The two
// MUST agree on the scheme — that's why they live in one repo:
//
//   subject = "<object>\n<exp>"            (object = path after the host, no leading slash)
//   sig     = lowercase hex HMAC-SHA256(ASSET_SIGNING_KEY, subject)
//   valid   = sig matches AND exp (unix seconds) is in the future
//
// The bucket stays private; this is its only public read path. Non-asset keys
// (e.g. _index/ DBs, backups) share the bucket but are never routable here, so
// they stay unreachable from the web. See ../DESIGN-store.md.
//
// UNWIRED: not deployed yet. See README.md for the deploy + signing wiring.

const KEY_RE = /^[0-9a-f]{2}\/[0-9a-f]{64}\.[a-z0-9]+$/; // hh/<sha256>.<ext>, root-level

export default {
  async fetch(req, env, ctx) {
    if (req.method !== "GET" && req.method !== "HEAD") {
      return new Response("method not allowed", { status: 405 });
    }

    const url = new URL(req.url);
    const key = decodeURIComponent(url.pathname).replace(/^\/+/, "");

    // Only content-addressed asset keys are servable. Everything else — the
    // index DBs, backups, anything — simply has no route here.
    if (!KEY_RE.test(key)) return new Response("not found", { status: 404 });

    const exp = url.searchParams.get("exp");
    const sig = url.searchParams.get("sig");
    if (!exp || !sig || !/^\d+$/.test(exp)) {
      return new Response("forbidden", { status: 403 });
    }
    if (Number(exp) * 1000 < Date.now()) {
      return new Response("expired", { status: 403 });
    }
    const expected = await hmacHex(env.ASSET_SIGNING_KEY, `${key}\n${exp}`);
    if (!timingSafeEqual(expected, sig.toLowerCase())) {
      return new Response("forbidden", { status: 403 });
    }

    // Edge-cache on the object (not the signature), so every player's freshly
    // signed URL for the same asset shares one cached copy.
    const cache = caches.default;
    const cacheKey = new Request(`${url.origin}/${key}`, { method: "GET" });
    let res = await cache.match(cacheKey);
    if (res) return res;

    const obj = await env.DUNGEON.get(key);
    if (!obj) return new Response("not found", { status: 404 });

    const headers = new Headers();
    obj.writeHttpMetadata(headers);
    headers.set("etag", obj.httpEtag);
    headers.set("cache-control", "public, max-age=31536000, immutable");
    res = new Response(obj.body, { headers });

    ctx.waitUntil(cache.put(cacheKey, res.clone()));
    return res;
  },
};

async function hmacHex(secret, msg) {
  const enc = new TextEncoder();
  const k = await crypto.subtle.importKey(
    "raw", enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const buf = await crypto.subtle.sign("HMAC", k, enc.encode(msg));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}
