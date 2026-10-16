import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// Server Components / Route Handlers. Cookie writes from a Server Component are ignored;
// src/proxy.ts refreshes the session instead.
export async function createClient() {
  const store = await cookies();
  return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try {
          list.forEach(({ name, value, options }) => store.set(name, value, options));
        } catch {}
      },
    },
  });
}
