import { cellId, type Cell } from "./grid";

// Simulated per-cell activity in open sea south of Pulau Sempu (port cell X095_Y160); rows above
// Y148 are land or the strait, checked on satellite imagery. shortcut: replace with an admin RPC once one returns unique fishers per cell.
export type HeatCell = {
  id: string;
  fishers: number; // unique fishers in the period; < 3 is hidden for privacy
  trips: number;
  hours: number;
  gear: { pancing: number; bubu: number };
  trend: number[]; // trips per week, oldest first (8 weeks)
  rehabKm: number; // distance to the nearest rehab cell
  heatStress: "Normal" | "Waspada" | "Siaga";
};

function rand(seed: number) {
  const x = Math.sin(seed * 12.9898) * 43758.5453;
  return x - Math.floor(x);
}

const REHAB: Cell = { x: 100, y: 148 };

function build(): HeatCell[] {
  const out: HeatCell[] = [];
  for (let x = 88; x <= 110; x++) {
    for (let y = 134; y <= 148; y++) {
      const d = Math.hypot(x - 100, y - 145);
      const r = rand(x * 1000 + y);
      // more boats near the reef and the port, fewer offshore
      const fishers = Math.max(0, Math.round(6 - d * 0.45 + r * 2.5));
      if (fishers === 0) continue;
      const trips = fishers * 2 + Math.round(r * 3);
      const pancing = Math.round(trips * (0.5 + r * 0.3));
      out.push({
        id: cellId({ x, y }),
        fishers,
        trips,
        hours: Math.round(trips * 2.5),
        gear: { pancing, bubu: trips - pancing },
        trend: Array.from({ length: 8 }, (_, i) => Math.max(1, Math.round(trips * (0.35 + i * 0.09) + rand(x + y + i) * 2))),
        rehabKm: Math.round(Math.hypot(x - REHAB.x, y - REHAB.y) * 5) / 10,
        heatStress: Math.hypot(x - REHAB.x, y - REHAB.y) < 3 ? "Waspada" : "Normal",
      });
    }
  }
  return out;
}

export const HEATMAP: HeatCell[] = build();
export const heatCell = (id: string) => HEATMAP.find((c) => c.id === id);
export const PRIVACY_MIN = 3;
export const REGION_UNIQUE_FISHERS = 12;
