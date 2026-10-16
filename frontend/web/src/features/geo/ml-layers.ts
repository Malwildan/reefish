import type { LegendItem } from "./components/heatmap-map";
import type { MlColumn, MlLayers } from "./heatmap-parse";

// api_layers columns; units are unconfirmed in the contract, so values are labelled "nilai".
export const ML_LAYERS: { key: MlColumn; label: string }[] = [
  { key: "level", label: "Level ML (cluster)" },
  { key: "potential_score", label: "Skor potensi" },
  { key: "potensi_ikan", label: "Potensi ikan" },
  { key: "sst", label: "Suhu laut" },
  { key: "chlor_a", label: "Klorofil-a" },
  { key: "depth_m", label: "Kedalaman" },
];

const RAMP = ["#440154", "#3b528b", "#21918c", "#5ec962", "#fde725"];
const fmt = (v: number) => (Math.round(v * 100) / 100).toLocaleString("id-ID");

/** Colour function + legend for one api_layers column. Missing values stay "Tidak ada data", never 0. */
export function mlStyle(l: MlLayers, col: MlColumn): { paint: (id: string) => [string, number] | undefined; legend: LegendItem[] } {
  if (col === "level") {
    const byLevel = new Map(l.levels.map((x) => [x.level, x.color]));
    return {
      paint: (id) => {
        const v = l.cells.get(id)?.level;
        const c = v == null ? undefined : byLevel.get(v);
        return c ? [c, 0.8] : undefined;
      },
      legend: [...l.levels.map((x) => ({ label: x.label, color: x.color })), { label: "Tidak ada data", color: "#eef1eb" }],
    };
  }
  let min = Infinity;
  let max = -Infinity;
  for (const c of l.cells.values()) {
    const v = c[col];
    if (v == null) continue;
    if (v < min) min = v;
    if (v > max) max = v;
  }
  if (!Number.isFinite(min)) return { paint: () => undefined, legend: [{ label: "Tidak ada data", color: "#eef1eb" }] };
  const span = max - min || 1;
  const step = (v: number) => Math.min(RAMP.length - 1, Math.floor(((v - min) / span) * RAMP.length));
  return {
    paint: (id) => {
      const v = l.cells.get(id)?.[col];
      return v == null ? undefined : [RAMP[step(v)], 0.8];
    },
    legend: [
      ...RAMP.map((color, i) => ({
        label: `${fmt(min + (span * i) / RAMP.length)}–${fmt(min + (span * (i + 1)) / RAMP.length)} nilai`,
        color,
      })),
      { label: "Tidak ada data", color: "#eef1eb" },
    ],
  };
}
