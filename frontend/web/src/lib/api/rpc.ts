import { createClient } from "@/lib/supabase/client";
import { ApiError, toApiError } from "./error";

/**
 * Calls a Supabase RPC (PostgREST) as the signed-in user; RLS and the role checks inside each
 * api_* function apply. Failures come back as ApiError(code, hint, details).
 */
export async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  let res;
  try {
    res = await createClient().rpc(fn, args);
  } catch (e) {
    throw new ApiError("NETWORK_ERROR", "Server tidak bisa dihubungi. Periksa koneksi lalu coba lagi.", { cause: String(e) });
  }
  if (res.error) throw toApiError(res.error);
  return res.data as T;
}

export { ApiError };
