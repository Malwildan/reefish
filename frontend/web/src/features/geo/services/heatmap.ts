import { HEATMAP as DEMO_HEATMAP } from "../mock-heatmap.ts";
import { createClient, demoEnabled, supabaseEnabled } from "../../../lib/supabase/client.ts";

export type FatigueLevel = "healthy" | "tired" | "critical";

/** Values exposed by api_heatmap. The RPC does not expose fisher counts or trip/hour trends. */
export type HeatCell = {
  id: string;
  fatigue: number | null;
  fatigueLevel: FatigueLevel | null;
  pressure: number | null;
  cpue: number | null;
  hasCoral: boolean;
  zoneId: string | null;
  autoFlag: string | null;
  fishers: number | null;
  trips: number | null;
  hours: number | null;
  catchKg: number | null;
  trend: number[] | null;
};

export type HeatmapSnapshot = {
  heatmap_version: number;
  generated_at: string | null;
  window: "7d" | "30d";
  smooth: boolean;
  cells: HeatCell[];
  zones: Record<string, unknown>;
  source: "supabase" | "demo";
};

type ApiCell = [string, number | null, FatigueLevel | null, number | null, number | null, boolean, string | null, string | null];
type ApiHeatmap = {
  heatmap_version: number;
  generated_at: string | null;
  window: "7d" | "30d";
  smooth: boolean;
  columns: string[];
  cells: ApiCell[];
  zones: Record<string, unknown>;
};

const cached = new Map<"7d" | "30d", Promise<HeatmapSnapshot>>();

export function invalidateHeatmapSnapshot() {
  cached.clear();
}

export function parseHeatmapSnapshot(value: unknown): HeatmapSnapshot {
  if (!value || typeof value !== "object") throw new Error("api_heatmap returned an invalid response.");
  const raw = value as Partial<ApiHeatmap>;
  if (
    !Number.isInteger(raw.heatmap_version) ||
    (raw.window !== "7d" && raw.window !== "30d") ||
    typeof raw.smooth !== "boolean" ||
    !Array.isArray(raw.columns) ||
    raw.columns.join(",") !== "grid_id,fatigue,fatigue_level,pressure,cpue,has_coral,zone_id,auto_flag" ||
    !Array.isArray(raw.cells) ||
    !raw.zones ||
    typeof raw.zones !== "object"
  ) {
    throw new Error("api_heatmap response is missing required snapshot metadata.");
  }
  const seen = new Set<string>();
  const cells = raw.cells.map((tuple, index): HeatCell => {
    if (!Array.isArray(tuple) || tuple.length !== 8) throw new Error(`api_heatmap cell ${index} is not an 8-value tuple.`);
    const [id, fatigue, fatigueLevel, pressure, cpue, hasCoral, zoneId, autoFlag] = tuple;
    if (
      typeof id !== "string" ||
      !/^X\d{3}_Y\d{3}$/.test(id) ||
      (fatigue !== null && (typeof fatigue !== "number" || !Number.isFinite(fatigue))) ||
      (fatigueLevel !== null && !["healthy", "tired", "critical"].includes(fatigueLevel)) ||
      (pressure !== null && (typeof pressure !== "number" || !Number.isFinite(pressure))) ||
      (cpue !== null && (typeof cpue !== "number" || !Number.isFinite(cpue))) ||
      typeof hasCoral !== "boolean" ||
      (zoneId !== null && typeof zoneId !== "string") ||
      (autoFlag !== null && typeof autoFlag !== "string")
    ) {
      throw new Error(`api_heatmap cell ${index} does not match the documented tuple contract.`);
    }
    if (seen.has(id)) throw new Error(`api_heatmap contains duplicate grid_id ${id}.`);
    seen.add(id);
    return {
      id,
      fatigue,
      fatigueLevel,
      pressure,
      cpue,
      hasCoral,
      zoneId,
      autoFlag,
      fishers: null,
      trips: null,
      hours: null,
      catchKg: null,
      trend: null,
    };
  });
  if (raw.generated_at !== null && typeof raw.generated_at !== "string") throw new Error("api_heatmap generated_at is invalid.");
  return {
    heatmap_version: raw.heatmap_version!,
    generated_at: raw.generated_at ?? null,
    window: raw.window,
    smooth: raw.smooth,
    cells,
    zones: raw.zones as Record<string, unknown>,
    source: "supabase",
  };
}

function demoSnapshot(window: "7d" | "30d"): HeatmapSnapshot {
  return {
    heatmap_version: 0,
    generated_at: null,
    window,
    smooth: false,
    cells: DEMO_HEATMAP.map((cell) => ({
      id: cell.id,
      fatigue: cell.fatigue,
      fatigueLevel: cell.fatigueLevel,
      pressure: null,
      cpue: null,
      hasCoral: cell.hasCoral,
      zoneId: null,
      autoFlag: null,
      fishers: cell.fishers,
      trips: cell.trips,
      hours: cell.hours,
      catchKg: cell.catchKg,
      trend: cell.trend,
    })),
    zones: {},
    source: "demo",
  };
}

async function loadHeatmapSnapshot(window: "7d" | "30d"): Promise<HeatmapSnapshot> {
  if (supabaseEnabled) {
    const { data, error } = await createClient().rpc("api_heatmap", {
      p_window: window,
      p_smooth: false,
      p_include_empty: true,
      p_include_zone_outline: false,
    });
    if (error) throw new Error(`Tidak dapat memuat heatmap Supabase: ${error.message}`);
    return parseHeatmapSnapshot(data);
  }
  if (demoEnabled) return demoSnapshot(window);
  throw new Error("Supabase belum dikonfigurasi. Mode demo hanya tersedia saat development.");
}

export function getHeatmapSnapshot(window: "7d" | "30d" = "30d"): Promise<HeatmapSnapshot> {
  let request = cached.get(window);
  if (!request) {
    request = loadHeatmapSnapshot(window).catch((error) => {
      cached.delete(window);
      throw error;
    });
    cached.set(window, request);
  }
  return request;
}
