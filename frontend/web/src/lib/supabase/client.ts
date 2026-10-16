import { createBrowserClient } from "@supabase/ssr";

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export const supabaseEnabled = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);
// Local UI previews may use fixtures. A deployed build must always authenticate.
export const demoEnabled = !supabaseEnabled && process.env.NODE_ENV !== "production";

export function createClient() {
  if (!supabaseEnabled) throw new Error("Koneksi Supabase belum dikonfigurasi.");
  return createBrowserClient(SUPABASE_URL!, SUPABASE_ANON_KEY!);
}
