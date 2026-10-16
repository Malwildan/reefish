"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { getVersion, notifyChanged, subscribe } from "@/features/decisions/services/zones";
import { ApiError } from "@/lib/api/error";
import type { Heatmap } from "../heatmap-parse";
import { getHeatmap, getHeatmapVersion, updateHeatmap } from "../services/heatmap";

const POLL_MS = 60_000;

/**
 * api_heatmap kept current: polls api_heatmap_version every minute (and on tab focus / after any
 * admin mutation) and applies api_heatmap_changes; FULL_RELOAD_REQUIRED falls back to api_heatmap.
 */
export function useLiveHeatmap(win: "7d" | "30d") {
  const mutations = useSyncExternalStore(subscribe, getVersion, () => 0);
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState<{ key?: string; data?: Heatmap; error?: ApiError; live?: number }>({});
  const key = `${win}#${attempt}`;
  const current = useRef<Heatmap | undefined>(undefined);
  useEffect(() => {
    current.current = state.key === key ? state.data : undefined;
  });

  useEffect(() => {
    let alive = true;
    getHeatmap(win).then(
      (data) => alive && setState({ key, data }),
      (e) => alive && setState({ key, error: e instanceof ApiError ? e : new ApiError("UNKNOWN", String(e)) }),
    );
    return () => {
      alive = false;
    };
  }, [win, key]);

  useEffect(() => {
    let alive = true;
    async function check() {
      const h = current.current;
      if (!h) return;
      try {
        const { heatmap_version } = await getHeatmapVersion();
        if (heatmap_version <= h.version) return;
        let next: Heatmap;
        try {
          next = await updateHeatmap(h);
        } catch (e) {
          if (!(e instanceof ApiError) || e.code !== "FULL_RELOAD_REQUIRED") throw e;
          next = await getHeatmap(h.window);
        }
        if (!alive || current.current !== h) return;
        setState((s) => ({ ...s, data: next, live: next.version }));
        notifyChanged(); // zones, suggestions and stats follow the new version
      } catch {
        // polling is best effort; the next tick tries again
      }
    }
    void check();
    const id = setInterval(check, POLL_MS);
    const onFocus = () => document.visibilityState === "visible" && void check();
    document.addEventListener("visibilitychange", onFocus);
    return () => {
      alive = false;
      clearInterval(id);
      document.removeEventListener("visibilitychange", onFocus);
    };
  }, [mutations]);

  const mine = state.key === key;
  return {
    data: mine ? state.data : undefined,
    error: mine ? state.error : undefined,
    /** heatmap version applied by the live updater (not by the first load) */
    liveVersion: mine ? state.live : undefined,
    reload: () => setAttempt((a) => a + 1),
  };
}
