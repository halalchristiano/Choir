// Temporary, expiring uploader. Only exact, reviewed bytes in the deployment's
// allowlist can be written, and only to the Bible audio bucket.
const allowed: Record<string, {bytes: number; sha256: string; mime: string}> = __ALLOWLIST__;
const expires = __EXPIRY__;
const tokenDigest = "__TOKEN_DIGEST__";
const base = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const auth = {Authorization: `Bearer ${key}`, apikey: key};
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), {status, headers: {"Content-Type": "application/json"}});
async function digest(bytes: ArrayBuffer) {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))).map(b => b.toString(16).padStart(2, "0")).join("");
}
Deno.serve(async req => {
  if (Date.now() > expires) return json({error: "expired"}, 410);
  if (req.method !== "POST") return json({error: "method"}, 405);
  const token = req.headers.get("x-import-token") || "";
  if (token.length !== 64) return json({error: "unauthorized"}, 401);
  const actual = await digest(new TextEncoder().encode(token).buffer);
  let difference = 0;
  for (let i = 0; i < actual.length; i++) difference |= actual.charCodeAt(i) ^ tokenDigest.charCodeAt(i);
  if (difference) return json({error: "unauthorized"}, 401);
  const query = new URL(req.url).searchParams;
  if (query.get("action") === "init") {
    let response = await fetch(`${base}/storage/v1/bucket/bible-audio`, {headers: auth});
    if (!response.ok) {
      response = await fetch(`${base}/storage/v1/bucket`, {method: "POST", headers: {...auth, "Content-Type": "application/json"},
        body: JSON.stringify({id: "bible-audio", name: "bible-audio", public: true, file_size_limit: 50000000,
          allowed_mime_types: ["audio/mp4", "application/json"]})});
      if (!response.ok) return json({error: "bucket creation failed", status: response.status}, 502);
      response = await fetch(`${base}/storage/v1/bucket/bible-audio`, {headers: auth});
    }
    const bucket = await response.json();
    if (!response.ok || bucket.id !== "bible-audio" || bucket.public !== true || bucket.file_size_limit !== 50000000) {
      return json({error: "bucket configuration differs"}, 409);
    }
    return json({bucket: "bible-audio", public: true});
  }
  const path = query.get("path") || "";
  const item = Object.hasOwn(allowed, path) ? allowed[path] : null;
  if (!item || item.bytes > 50000000) return json({error: "path is not allowed"}, 403);
  if (Number(req.headers.get("content-length")) !== item.bytes) return json({error: "size differs"}, 400);
  const bytes = await req.arrayBuffer();
  if (bytes.byteLength !== item.bytes || await digest(bytes) !== item.sha256) return json({error: "content differs"}, 400);
  const objectPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${base}/storage/v1/object/bible-audio/${objectPath}`, {method: "POST",
    headers: {...auth, "Content-Type": item.mime, "x-upsert": "true", "Cache-Control": path.endsWith(".json") ? "max-age=60" : "max-age=31536000"}, body: bytes});
  if (!response.ok) return json({error: "storage upload failed", status: response.status}, 502);
  return json({path, sha256: item.sha256, bytes: item.bytes});
});
