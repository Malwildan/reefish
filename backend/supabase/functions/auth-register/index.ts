// POST { phone, password, full_name? } -> 201 { user, session }
// Only registration path: public signup is disabled in config.toml, so these checks cannot be bypassed.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { authResponse, fail, normalizePhone, passwordProblems, phoneEmail, readBody } from "../_shared/auth.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  const body = await readBody(req);
  if (body instanceof Response) return body;

  const phone = normalizePhone(body.phone);
  if (!phone) return fail(422, "INVALID_PHONE", "Nomor telepon tidak valid. Contoh: 081234567890");
  const problems = passwordProblems(body.password);
  if (problems.length) return fail(422, "WEAK_PASSWORD", "Password belum memenuhi syarat", problems);
  const fullName = typeof body.full_name === "string" ? body.full_name.trim().slice(0, 100) || null : null;
  const password = body.password as string;

  const { error: createError } = await admin.auth.admin.createUser({
    email: phoneEmail(phone),
    password,
    email_confirm: true,
    user_metadata: { phone, full_name: fullName },
  });
  if (createError) {
    if (createError.status === 422 && /already|registered|exists/i.test(createError.message)) {
      return fail(409, "PHONE_TAKEN", "Nomor telepon sudah terdaftar");
    }
    console.error("createUser failed", createError.status, createError.message);
    return fail(500, "REGISTER_FAILED", "Pendaftaran gagal, coba lagi");
  }

  const { data, error } = await anon.auth.signInWithPassword({ email: phoneEmail(phone), password });
  if (error || !data.session) {
    console.error("sign in after register failed", error?.status, error?.message);
    return fail(500, "REGISTER_FAILED", "Akun dibuat tetapi login gagal, silakan login");
  }
  return authResponse(201, data.user, data.session);
});
