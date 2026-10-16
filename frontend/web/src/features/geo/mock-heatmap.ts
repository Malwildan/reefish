import { cellId, type Cell } from "./grid.ts";

// Simulated per-cell activity in open sea south of Pulau Sempu (port cell X095_Y160); rows above
// Y148 are land or the strait, checked on satellite imagery. Fields follow api_heatmap
// (fatigue, fatigue_level, has_coral) plus activity used by api_admin_preview_zone.
// shortcut: replace with api_heatmap + api_admin_preview_zone once the admin is wired.
export type FatigueLevel = "healthy" | "tired" | "critical";

export type HeatCell = {
  id: string;
  fishers: number; // unique fishers in the period; < 3 is hidden for privacy
  trips: number; // last 30 days
  hours: number;
  catchKg: number;
  fatigue: number; // 0..1
  fatigueLevel: FatigueLevel;
  hasCoral: boolean;
  gear: { pancing: number; bubu: number };
  trend: number[]; // trips per week, oldest first (8 weeks)
};

function rand(seed: number) {
  const x = Math.sin(seed * 12.9898) * 43758.5453;
  return x - Math.floor(x);
}

const REEF: Cell = { x: 100, y: 147 };

function build(): HeatCell[] {
  const out: HeatCell[] = [];
  for (let x = 88; x <= 112; x++) {
    for (let y = 134; y <= 148; y++) {
      const d = Math.hypot(x - 100, y - 145);
      const r = rand(x * 1000 + y);
      // more boats near the reef and the port, fewer offshore
      const fishers = Math.max(0, Math.round(6 - d * 0.45 + r * 2.5));
      if (fishers === 0) continue;
      const trips = fishers * 2 + Math.round(r * 3);
      const pancing = Math.round(trips * (0.5 + r * 0.3));
      const hasCoral = Math.hypot(x - REEF.x, y - REEF.y) < 2.6;
      const fatigue = Math.min(0.98, Math.round((0.15 + fishers * 0.08 + (hasCoral ? 0.25 : 0) + r * 0.1) * 100) / 100);
      out.push({
        id: cellId({ x, y }),
        fishers,
        trips,
        hours: Math.round(trips * 2.5),
        catchKg: Math.round(trips * (9 + r * 6)),
        fatigue,
        fatigueLevel: fatigue >= 0.7 ? "critical" : fatigue >= 0.4 ? "tired" : "healthy",
        hasCoral,
        gear: { pancing, bubu: trips - pancing },
        trend: Array.from({ length: 8 }, (_, i) => Math.max(1, Math.round(trips * (0.35 + i * 0.09) + rand(x + y + i) * 2))),
      });
    }
  }
  return out;
}

export const HEATMAP: HeatCell[] = build();
const BY_ID = new Map(HEATMAP.map((c) => [c.id, c]));
export const heatCell = (id: string) => BY_ID.get(id);
export const PRIVACY_MIN = 3;
export const REGION_UNIQUE_FISHERS = 12;
