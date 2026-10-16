import { cellCenter, parseCellId } from "../geo/grid.ts";

// Simulated live indications (Figma flow 07). shortcut: no backend source yet; needs a monitoring
// RPC fed by live trip points before this page can show real boats.
export type Violation = {
  id: string;
  fisher: string;
  pattern: "linger" | "circle";
  cell: string;
  minutes: number;
  laps: number;
  distanceM: number;
  updatedAt: string; // HH.MM WIB
};

export const VIOLATIONS: Violation[] = [
  { id: "v1", fisher: "N-012", pattern: "linger", cell: "X099_Y148", minutes: 18, laps: 0, distanceM: 80, updatedAt: "10.42" },
  { id: "v2", fisher: "N-027", pattern: "circle", cell: "X101_Y146", minutes: 26, laps: 3, distanceM: 120, updatedAt: "10.42" },
];

export const PATTERN = {
  linger: { short: "Lama di area", title: "Lama di sekitar terumbu", activity: "menetap di area yang sama" },
  circle: { short: "Berputar di area", title: "Berputar di sekitar terumbu", activity: "berputar di area yang sama" },
} as const;

export const pillLabel = (v: Violation) =>
  v.pattern === "linger" ? `${v.fisher} · ${v.minutes} mnt` : `${v.fisher} · ${v.laps} putaran`;

export const center = (v: Violation) => cellCenter(parseCellId(v.cell)!);

// Short track ending at the boat, for the "Jejak pergerakan" layer.
export function trail(v: Violation): [number, number][] {
  const [lon, lat] = center(v);
  if (v.pattern === "circle") {
    return Array.from({ length: 13 }, (_, i) => {
      const a = (i / 12) * Math.PI * 2;
      return [lon + Math.cos(a) * 0.0018, lat + Math.sin(a) * 0.0015] as [number, number];
    });
  }
  return [
    [lon - 0.02, lat - 0.012],
    [lon - 0.011, lat - 0.006],
    [lon - 0.004, lat - 0.002],
    [lon, lat],
  ];
}
