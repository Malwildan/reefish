"use client";

import type { ReactNode } from "react";

// Client providers go here (Supabase session, query cache) once the admin is wired to the backend.
export function Providers({ children }: { children: ReactNode }) {
  return <>{children}</>;
}
