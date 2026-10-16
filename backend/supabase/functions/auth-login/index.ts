// POST { phone, password } -> 200 { user, session }
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { authResponse, fail, normalizePhone, phoneEmail, readBody } from "../_shared/auth.ts";

const anon = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
  auth: { persistSession: false },
});

const invalid = () => fail(401, "INVALID_CREDENTIALS", "Nomor telepon atau password salah");

Deno.serve(async (req) => {
  const body = await readBody(req);
  if (body instanceof Response) return body;

  const phone = normalizePhone(body.phone);
  if (!phone || typeof body.password !== "string") return invalid();

  const { data, error } = await anon.auth.signInWithPassword({ email: phoneEmail(phone), password: body.password });
  if (error || !data.session) {
    if (error && error.status !== 400) {
      console.error("sign in failed", error.status, error.message);
      return fail(error.status === 429 ? 429 : 500, "LOGIN_FAILED", "Login gagal, coba lagi");
    }
    return invalid();
  }
  return authResponse(200, data.user, data.session);
});
