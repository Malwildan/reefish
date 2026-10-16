// push-dispatch: sends queued zone_changed pushes (push_outbox) through FCM HTTP v1.
// Called every minute by pg_cron (see supabase/setup/README.md) with the service role key.
// Secret FCM_SERVICE_ACCOUNT = the Firebase service account JSON. Without it the function claims
// nothing, so pushes stay queued until the secret is set.
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { buildMessage, type Claimed, isDeadToken } from "../_shared/push.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

async function rpc(name: string, body: unknown) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status} ${await res.text()}`);
  return res.json();
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const jwt = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(await importPKCS8(sa.private_key, "RS256"));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`oauth: HTTP ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

// Sends one claimed push to all its tokens.
// shortcut: a push with only transient errors (429/5xx) is retried whole, so devices that already
// got it may get it twice; track per-token delivery if that becomes a problem.
async function send(p: Claimed, sa: ServiceAccount, token: string) {
  const dead: string[] = [];
  let ok = 0, transient = 0;
  await Promise.all(p.tokens.map(async (t) => {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(buildMessage(p, t)),
    });
    const body = res.ok ? "" : await res.text();
    if (res.ok) ok++;
    else if (isDeadToken(res.status, body)) dead.push(t);
    else transient++;
  }));
  const status = ok > 0 || transient === 0 ? "sent" : "failed";
  return rpc("api_internal_push_done", { p_id: p.id, p_status: status, p_invalid_tokens: dead });
}

Deno.serve(async (req) => {
  if (req.headers.get("Authorization") !== `Bearer ${SERVICE_KEY}`) {
    return Response.json({ error: "service role only" }, { status: 403 });
  }
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return Response.json({ skipped: "FCM_SERVICE_ACCOUNT not set" });

  const sa: ServiceAccount = JSON.parse(raw);
  const token = await accessToken(sa);
  const claimed: Claimed[] = await rpc("api_internal_push_claim", { p_limit: 20 });
  const results = [];
  for (const p of claimed) {
    try {
      results.push(await send(p, sa, token));
    } catch (e) {
      // the row stays 'sending' and is requeued by the next claim after 10 minutes
      results.push({ id: p.id, error: String(e) });
    }
  }
  return Response.json({ claimed: claimed.length, results });
});
