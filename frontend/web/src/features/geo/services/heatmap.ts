import type { FeatureCollection, MultiPolygon } from "geojson";
import { rpc } from "@/lib/api/rpc";
import { applyChanges, decodeSeaMask, parseHeatmap, parseLayers, type Heatmap, type MlLayers, type RawChanges } from "../heatmap-parse";
import type { ZoneQuota, ZoneRules, ZoneStatus } from "@/features/decisions/types";

export const getHeatmap = async (window: "7d" | "30d"): Promise<Heatmap> =>
  parseHeatmap(await rpc("api_heatmap", { p_window: window }));

export const getHeatmapVersion = () => rpc<{ heatmap_version: number; updated_at: string }>("api_heatmap_version");

/** Delta since `h.version`; throws ApiError FULL_RELOAD_REQUIRED when too old (then reload). */
export async function updateHeatmap(h: Heatmap): Promise<Heatmap> {
  return applyChanges(h, await rpc<RawChanges>("api_heatmap_changes", { p_since: h.version, p_window: h.window }));
}

// The sea mask only changes with the grid version, so one fetch per page load is enough.
let sea: Promise<string[]> | null = null;
export function getSeaCells(): Promise<string[]> {
  sea ??= rpc<{ bits: string; cols: number; length: number }>("api_sea_mask").then(decodeSeaMask, (e) => {
    sea = null;
    throw e;
  });
  return sea;
}

export type ZoneOutline = {
  id: string;
  name: string;
  status: ZoneStatus;
  rules: ZoneRules | null;
  quota: ZoneQuota | null;
  grid_ids: string[];
  outline: MultiPolygon | null;
};

/** api_zones with outlines, as a FeatureCollection for the map. */
export async function getZoneOutlines(): Promise<FeatureCollection> {
  const res = await rpc<{ zones: ZoneOutline[] }>("api_zones", { p_include_outline: true });
  return {
    type: "FeatureCollection",
    features: res.zones
      .filter((z) => z.outline)
      .map((z) => ({
        type: "Feature",
        geometry: z.outline!,
        properties: {
          id: z.id,
          name: z.name,
          status: z.status,
          grid_count: z.grid_ids.length,
          remaining_kg: z.quota?.remaining_kg ?? null,
          remaining_trips: z.quota?.remaining_trips ?? null,
          exhausted: z.quota?.exhausted ?? false,
        },
      })),
  };
}

const layers = new Map<string, Promise<MlLayers>>();
/** api_layers for one period (null = latest); cached because a period never changes. */
export function getLayers(period: string | null): Promise<MlLayers> {
  const key = period ?? "latest";
  if (!layers.has(key)) {
    layers.set(
      key,
      rpc<Parameters<typeof parseLayers>[0]>("api_layers", { p_period: period }).then(parseLayers, (e) => {
        layers.delete(key);
        throw e;
      }),
    );
  }
  return layers.get(key)!;
}

export type Habitat = { coral: FeatureCollection; mangrove: FeatureCollection; coral_codebook_confirmed: boolean };
let habitat: Promise<Habitat> | null = null;
export function getHabitat(): Promise<Habitat> {
  habitat ??= rpc<Habitat>("api_habitat").catch((e) => {
    habitat = null;
    throw e;
  });
  return habitat;
}
