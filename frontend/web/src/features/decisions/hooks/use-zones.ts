"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { getVersion, subscribe } from "../services/zones";
import { ApiError } from "../types";

type Result<T> = { data?: T; error?: ApiError; loading: boolean; retry: () => void };

/**
 * Runs an async zone query and re-runs it when `key` changes or any zone mutation commits.
 * Mirrors how the pages will call supabase.rpc(...) later.
 */
export function useZoneQuery<T>(key: string, fn: () => Promise<T>): Result<T> {
  const version = useSyncExternalStore(subscribe, getVersion, () => 0);
  const [attempt, setAttempt] = useState(0);
  const want = `${key}#${version}#${attempt}`;
  const [res, setRes] = useState<{ for?: string; data?: T; error?: ApiError }>({});

  useEffect(() => {
    let alive = true;
    fn().then(
      (data) => alive && setRes({ for: want, data }),
      (e) => alive && setRes({ for: want, error: e instanceof ApiError ? e : new ApiError("UNKNOWN", String(e)) }),
    );
    return () => {
      alive = false;
    };
    // fn is recreated each render; `want` captures everything it depends on
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [want]);

  return {
    // keep showing the previous data while a refetch runs
    data: res.data,
    error: res.for === want ? res.error : undefined,
    loading: res.for !== want,
    retry: () => setAttempt((a) => a + 1),
  };
}
