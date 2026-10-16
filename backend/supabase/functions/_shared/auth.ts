// Shared rules for phone + password auth. Phones map to a synthetic email because
// Supabase phone+password login requires a paid SMS provider even without OTP.

// Never receives mail: email confirmations are off and users are created confirmed.
export const PHONE_EMAIL_DOMAIN = "phone.reefish.app";

/** Normalises Indonesian numbers to 62XXXXXXXXXX; returns null when invalid. */
export function normalizePhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let p = raw.replace(/[\s\-()]/g, "");
  if (p.startsWith("+")) p = p.slice(1);
  if (p.startsWith("0")) p = "62" + p.slice(1);
  return /^62\d{8,13}$/.test(p) ? p : null;
}

/** Returns the failed password rules in Indonesian; empty means the password is accepted. */
export function passwordProblems(pw: unknown): string[] {
  if (typeof pw !== "string") return ["Password wajib diisi"];
  const problems: string[] = [];
  if (pw.length < 8) problems.push("Minimal 8 karakter");
  if (!/[A-Z]/.test(pw)) problems.push("Harus mengandung huruf kapital");
  if (!/\d/.test(pw)) problems.push("Harus mengandung angka");
  if (!/[^A-Za-z0-9]/.test(pw)) problems.push("Harus mengandung simbol");
  return problems;
}

export const phoneEmail = (phone: string) => `${phone}@${PHONE_EMAIL_DOMAIN}`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

export const fail = (status: number, code: string, message: string, details?: unknown) =>
  json(status, { error: { code, message, ...(details === undefined ? {} : { details }) } });

/** Handles CORS preflight and method/body checks; returns the parsed body or a Response to send. */
export async function readBody(req: Request): Promise<Record<string, unknown> | Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return fail(405, "METHOD_NOT_ALLOWED", "Gunakan POST");
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) return body as Record<string, unknown>;
  } catch {
    // fall through
  }
  return fail(400, "INVALID_JSON", "Body harus objek JSON");
}

type Session = { access_token: string; refresh_token: string; expires_at?: number };
type User = { id: string; user_metadata?: Record<string, unknown> };

export const authResponse = (status: number, user: User, session: Session) =>
  json(status, {
    user: {
      id: user.id,
      phone: user.user_metadata?.phone ?? null,
      full_name: user.user_metadata?.full_name ?? null,
    },
    session: {
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      expires_at: session.expires_at ?? null,
    },
  });
