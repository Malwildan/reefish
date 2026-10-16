import { rpc } from "@/lib/api/rpc";
import { decodeSeaMask, parseHeatmap, type Heatmap } from "../heatmap-parse";

export const getHeatmap = async (window: "7d" | "30d"): Promise<Heatmap> =>
  parseHeatmap(await rpc("api_heatmap", { p_window: window }));

// The sea mask only changes with the grid version, so one fetch per page load is enough.
let sea: Promise<string[]> | null = null;
export function getSeaCells(): Promise<string[]> {
  sea ??= rpc<{ bits: string; cols: number; length: number }>("api_sea_mask").then(decodeSeaMask, (e) => {
    sea = null;
    throw e;
  });
  return sea;
}
