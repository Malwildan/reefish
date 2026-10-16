"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient, supabaseEnabled } from "@/lib/supabase/client";

export function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function signOut() {
    setBusy(true);
    setError("");
    try {
      if (supabaseEnabled) {
        const { error } = await createClient().auth.signOut();
        if (error) throw error;
      }
      router.replace("/login");
      router.refresh();
    } catch {
      setError("Belum dapat keluar. Coba lagi.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-2">
      <button type="button" disabled={busy} onClick={signOut} className="min-h-11 rounded-xl px-4 py-3 text-left t-label hover:bg-blue-700/50 disabled:opacity-60">
        {busy ? "Keluar…" : "Keluar akun"}
      </button>
      {error && <p role="alert" className="t-body">{error}</p>}
    </div>
  );
}
