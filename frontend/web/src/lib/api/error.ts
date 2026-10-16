// Error shape of the api_* RPCs: private.fail puts the code in `message`, the Indonesian text in
// `hint` and a JSON object in `details` (PostgREST passes them through).
export class ApiError extends Error {
  code: string;
  details?: Record<string, unknown>;
  constructor(code: string, hint: string, details?: Record<string, unknown>) {
    super(hint);
    this.code = code;
    this.details = details;
  }
}

const FALLBACK: Record<string, string> = {
  FORBIDDEN: "Akun ini tidak punya akses admin kawasan.",
  UNAUTHENTICATED: "Sesi berakhir. Silakan masuk lagi.",
  PGRST301: "Sesi berakhir. Silakan masuk lagi.",
};

export function toApiError(e: { message?: string; hint?: string | null; details?: string | null; code?: string }) {
  const code = /^[A-Z][A-Z_]+$/.test(e.message ?? "") ? e.message! : (e.code ?? "UNKNOWN");
  let details: Record<string, unknown> | undefined;
  try {
    details = e.details ? JSON.parse(e.details) : undefined;
  } catch {
    details = { raw: e.details };
  }
  return new ApiError(code, e.hint || FALLBACK[code] || e.message || "Terjadi kesalahan.", details);
}
