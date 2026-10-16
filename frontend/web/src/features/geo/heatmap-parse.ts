// Pure parsers for api_heatmap and api_sea_mask (contracts/map-zones-api.openapi.yaml).
import type { ZoneStatus } from "../decisions/types.ts";

export type Layer = "fatigue" | "pressure" | "cpue";
export type FatigueLevel = "healthy" | "tired" | "critical";

export type HeatCell = {
  id: string;
  fatigue: number | null;
  fatigueLevel: FatigueLevel | null;
  pressure: number | null;
  cpue: number | null;
  hasCoral: boolean;
  zoneId: string | null;
  /** "restricted" when the system auto-flagged a cell outside any zone */
  autoFlag: "restricted" | null;
};

export type ZoneEntry = {
  id: string;
  name: string;
  status: ZoneStatus;
  grid_ids: string[];
  zone_version: number;
};

export type Scale = {
  fatigue: { min: number; max: number; thresholds: { tired: number; critical: number } };
  pressure: { min: number; max: number };
  cpue: { min: number; max: number | null; unit: string };
};

export type Heatmap = {
  version: number;
  window: "7d" | "30d";
  generatedAt: string;
  scale: Scale;
  cells: HeatCell[];
  zones: Record<string, ZoneEntry>;
};

type RawHeatmap = {
  heatmap_version: number;
  window: "7d" | "30d";
  generated_at: string;
  scale: Scale;
  columns: string[];
  cells: unknown[][];
  zones: Record<string, ZoneEntry>;
};

export function parseHeatmap(raw: RawHeatmap): Heatmap {
  const col = (name: string) => {
    const i = raw.columns.indexOf(name);
    if (i < 0) throw new Error(`api_heatmap: missing column ${name}`);
    return i;
  };
  const [id, f, fl, p, c, coral, zone, flag] = [
    "grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag",
  ].map(col);
  return {
    version: raw.heatmap_version,
    window: raw.window,
    generatedAt: raw.generated_at,
    scale: raw.scale,
    zones: raw.zones ?? {},
    cells: raw.cells.map((r) => ({
      id: r[id] as string,
      fatigue: r[f] as number | null,
      fatigueLevel: r[fl] as FatigueLevel | null,
      pressure: r[p] as number | null,
      cpue: r[c] as number | null,
      hasCoral: r[coral] === true,
      zoneId: r[zone] as string | null,
      autoFlag: r[flag] === "restricted" ? "restricted" : null,
    })),
  };
}

/** api_sea_mask: bit (grid_y−1)·cols + (grid_x−1), MSB first in each byte → sea cell IDs. */
export function decodeSeaMask(m: { bits: string; cols: number; length: number }): string[] {
  const bin = atob(m.bits);
  const out: string[] = [];
  for (let i = 0; i < m.length; i++) {
    if ((bin.charCodeAt(i >> 3) >> (7 - (i & 7))) & 1) {
      const x = (i % m.cols) + 1;
      const y = Math.floor(i / m.cols) + 1;
      out.push(`X${String(x).padStart(3, "0")}_Y${String(y).padStart(3, "0")}`);
    }
  }
  return out;
}

/** Zone (restricted/rehab) per grid, from the heatmap's zone entries. */
export function zoneIndex(h: Heatmap): Record<string, { id: string; name: string; status: ZoneStatus }> {
  const out: Record<string, { id: string; name: string; status: ZoneStatus }> = {};
  for (const z of Object.values(h.zones)) for (const g of z.grid_ids) out[g] = { id: z.id, name: z.name, status: z.status };
  return out;
}

/** Normal cells the system flagged restricted and that wait for an admin decision. */
export const autoFlags = (h: Heatmap) => h.cells.filter((c) => c.autoFlag && !c.zoneId).map((c) => c.id);

// ---- api_heatmap_changes ------------------------------------------------------------------

export type RawChanges = {
  from_version: number;
  to_version: number;
  columns: string[];
  upserts: unknown[][];
  zones_upserted: Record<string, ZoneEntry>;
  zones_removed: string[];
  scale: Scale;
};

/** Applies a delta from api_heatmap_changes to a loaded heatmap (cells replaced by grid_id). */
export function applyChanges(h: Heatmap, ch: RawChanges): Heatmap {
  const delta = parseHeatmap({
    heatmap_version: ch.to_version,
    window: h.window,
    generated_at: new Date().toISOString(),
    scale: ch.scale ?? h.scale,
    columns: ch.columns,
    cells: ch.upserts,
    zones: {},
  });
  const byId = new Map(h.cells.map((c) => [c.id, c]));
  for (const c of delta.cells) byId.set(c.id, c);
  const zones = { ...h.zones, ...ch.zones_upserted };
  for (const id of ch.zones_removed) delete zones[id];
  return { ...h, version: ch.to_version, scale: delta.scale, cells: [...byId.values()], zones };
}

// ---- api_layers ---------------------------------------------------------------------------

export type MlColumn = "level" | "potential_score" | "sst" | "chlor_a" | "depth_m" | "potensi_ikan";
export type MlCell = Record<MlColumn, number | null> & { imputed: boolean };
export type MlLayers = {
  period: string;
  periods: string[];
  levels: { level: number; label: string; color: string }[];
  cells: Map<string, MlCell>;
};

export function parseLayers(raw: {
  period: string;
  periods: string[];
  columns: string[];
  cells: unknown[][];
  levels: { level: number; label: string; color: string }[];
}): MlLayers {
  const at = (name: string) => raw.columns.indexOf(name);
  const id = at("grid_id");
  const cols: MlColumn[] = ["level", "potential_score", "sst", "chlor_a", "depth_m", "potensi_ikan"];
  const idx = cols.map(at);
  const imp = at("imputed");
  const cells = new Map<string, MlCell>();
  for (const r of raw.cells) {
    const c = { imputed: r[imp] === true } as MlCell;
    cols.forEach((k, i) => (c[k] = idx[i] < 0 ? null : (r[idx[i]] as number | null)));
    cells.set(r[id] as string, c);
  }
  return { period: raw.period, periods: raw.periods, levels: raw.levels ?? [], cells };
}
