import { createBrowserClient } from "@supabase/ssr";

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

// Both are required; without them login shows a configuration error (see README).
export const supabaseEnabled = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);

export function createClient() {
  return createBrowserClient(SUPABASE_URL!, SUPABASE_ANON_KEY!);
}
