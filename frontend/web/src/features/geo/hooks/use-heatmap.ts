"use client";

import { useCallback, useEffect, useState } from "react";
import { getHeatmapSnapshot, invalidateHeatmapSnapshot, type HeatmapSnapshot } from "../services/heatmap";

const REFRESH_MS = 30_000;

export function useHeatmap(window: "7d" | "30d" = "30d") {
  const [attempt, setAttempt] = useState(0);
  const [result, setResult] = useState<{ window?: "7d" | "30d"; data?: HeatmapSnapshot; error?: Error; loading: boolean }>({ loading: true });

  const refresh = useCallback(() => setAttempt((value) => value + 1), []);

  useEffect(() => {
    let alive = true;
    const load = async (force: boolean) => {
      if (force) invalidateHeatmapSnapshot();
      if (alive) setResult((current) => ({ window, data: current.window === window ? current.data : undefined, loading: current.window !== window || !current.data, error: undefined }));
      try {
        const data = await getHeatmapSnapshot(window);
        if (alive) setResult({ window, data, loading: false });
      } catch (error) {
        if (alive) setResult({ window, error: error instanceof Error ? error : new Error(String(error)), loading: false });
      }
    };

    void load(attempt > 0);
    const timer = globalThis.setInterval(() => void load(true), REFRESH_MS);
    return () => {
      alive = false;
      globalThis.clearInterval(timer);
    };
  }, [attempt, window]);

  return {
    data: result.window === window ? result.data : undefined,
    error: result.window === window ? result.error : undefined,
    loading: result.window !== window || result.loading,
    retry: refresh,
  };
}
