"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { createClient, supabaseEnabled } from "@/lib/supabase/client";

// "0812…" or "62812…" -> "+62812…"; anything with "@" is treated as an email.
export function toPhone(raw: string) {
  const digits = raw.replace(/\D/g, "");
  return "+" + (digits.startsWith("0") ? "62" + digits.slice(1) : digits);
}

export function LoginForm() {
  const router = useRouter();
  const [id, setId] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    if (!supabaseEnabled) return setError("Supabase belum diatur (NEXT_PUBLIC_SUPABASE_URL / ANON_KEY di .env.local).");
    if (!id.trim() || !password) return setError("Isi nomor telepon (atau email) dan kata sandi.");
    setBusy(true);
    try {
      const supabase = createClient();
      const creds = id.includes("@") ? { email: id.trim(), password } : { phone: toPhone(id), password };
      const { error: authError } = await supabase.auth.signInWithPassword(creds);
      if (authError) return setError("Nomor/email atau kata sandi salah.");
      const { data: me, error: profileError } = await supabase.rpc("api_me");
      if (profileError) {
        await supabase.auth.signOut();
        return setError("Profil akun belum dapat dimuat. Coba lagi.");
      }
      if (me?.role !== "konservatif") {
        await supabase.auth.signOut();
        return setError("Akun ini bukan admin kawasan. Gunakan aplikasi Reefish untuk nelayan.");
      }
      router.replace("/dashboard");
      router.refresh();
    } catch {
      setError("Layanan akun belum dapat dihubungi. Coba lagi.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} noValidate className="flex flex-col gap-3">
      {!supabaseEnabled && (
        <Notice tone="error">Supabase belum diatur. Isi NEXT_PUBLIC_SUPABASE_URL dan NEXT_PUBLIC_SUPABASE_ANON_KEY di .env.local.</Notice>
      )}
      <Field
        id="login-id"
        label="Nomor telepon atau email"
        autoComplete="username"
        inputMode="tel"
        value={id}
        onChange={(e) => setId(e.target.value)}
        placeholder="0812 3456 7890"
      />
      <Field
        id="login-password"
        label="Kata sandi"
        type="password"
        autoComplete="current-password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
      />
      {error && (
        <p className="t-caption text-error" role="alert">
          {error}
        </p>
      )}
      <Button type="submit" disabled={busy} className="mt-2">
        {busy ? "Memeriksa…" : "Masuk"}
      </Button>
    </form>
  );
}
