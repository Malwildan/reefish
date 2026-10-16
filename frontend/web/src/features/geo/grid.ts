// TypeScript port of backend/api/internal/domain/gridindex (contracts/grid-index.md):
// WGS84 <-> UTM 49S (EPSG:32749) <-> cell X{xxx}_Y{yyy}. Checked against contracts/fixtures/grid-index-vectors.json.

export const ORIGIN_E = 637500;
export const ORIGIN_N = 8988000;
export const CELL = 500;

export type Cell = { x: number; y: number };

const A = 6378137;
const F = 1 / 298.257223563;
const K0 = 0.9996;
const LON0 = (111 * Math.PI) / 180;
const FALSE_E = 500000;
const FALSE_N = 10000000;
const E2 = F * (2 - F);
const EP2 = E2 / (1 - E2);
const RAD = Math.PI / 180;

function meridianArc(phi: number) {
  const e4 = E2 * E2;
  const e6 = e4 * E2;
  return (
    A *
    ((1 - E2 / 4 - (3 * e4) / 64 - (5 * e6) / 256) * phi -
      ((3 * E2) / 8 + (3 * e4) / 32 + (45 * e6) / 1024) * Math.sin(2 * phi) +
      ((15 * e4) / 256 + (45 * e6) / 1024) * Math.sin(4 * phi) -
      ((35 * e6) / 3072) * Math.sin(6 * phi))
  );
}

export function toUTM(lat: number, lon: number): [number, number] {
  const phi = lat * RAD;
  const lam = lon * RAD;
  const sin = Math.sin(phi);
  const cos = Math.cos(phi);
  const tan = Math.tan(phi);
  const nu = A / Math.sqrt(1 - E2 * sin * sin);
  const t = tan * tan;
  const c = EP2 * cos * cos;
  const a = (lam - LON0) * cos;
  const e =
    FALSE_E + K0 * nu * (a + ((1 - t + c) * a ** 3) / 6 + ((5 - 18 * t + t * t + 72 * c - 58 * EP2) * a ** 5) / 120);
  const n =
    FALSE_N +
    K0 *
      (meridianArc(phi) +
        nu *
          tan *
          ((a * a) / 2 +
            ((5 - t + 9 * c + 4 * c * c) * a ** 4) / 24 +
            ((61 - 58 * t + t * t + 600 * c - 330 * EP2) * a ** 6) / 720));
  return [e, n];
}

export function toLatLon(e: number, n: number): [number, number] {
  const m = (n - FALSE_N) / K0;
  const e4 = E2 * E2;
  const e6 = e4 * E2;
  const mu = m / (A * (1 - E2 / 4 - (3 * e4) / 64 - (5 * e6) / 256));
  const e1 = (1 - Math.sqrt(1 - E2)) / (1 + Math.sqrt(1 - E2));
  const phi1 =
    mu +
    ((3 * e1) / 2 - (27 * e1 ** 3) / 32) * Math.sin(2 * mu) +
    ((21 * e1 * e1) / 16 - (55 * e1 ** 4) / 32) * Math.sin(4 * mu) +
    ((151 * e1 ** 3) / 96) * Math.sin(6 * mu) +
    ((1097 * e1 ** 4) / 512) * Math.sin(8 * mu);
  const sin = Math.sin(phi1);
  const cos = Math.cos(phi1);
  const tan = Math.tan(phi1);
  const c1 = EP2 * cos * cos;
  const t1 = tan * tan;
  const n1 = A / Math.sqrt(1 - E2 * sin * sin);
  const r1 = (A * (1 - E2)) / (1 - E2 * sin * sin) ** 1.5;
  const d = (e - FALSE_E) / (n1 * K0);
  const phi =
    phi1 -
    ((n1 * tan) / r1) *
      ((d * d) / 2 -
        ((5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * EP2) * d ** 4) / 24 +
        ((61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * EP2 - 3 * c1 * c1) * d ** 6) / 720);
  const lam =
    LON0 +
    (d - ((1 + 2 * t1 + c1) * d ** 3) / 6 + ((5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * EP2 + 24 * t1 * t1) * d ** 5) / 120) /
      cos;
  return [phi / RAD, lam / RAD];
}

export function cellFromLatLon(lat: number, lon: number): Cell {
  const [e, n] = toUTM(lat, lon);
  return { x: Math.floor((e - ORIGIN_E) / CELL) + 1, y: Math.floor((n - ORIGIN_N) / CELL) + 1 };
}

export function cellId({ x, y }: Cell) {
  return `X${String(x).padStart(3, "0")}_Y${String(y).padStart(3, "0")}`;
}

export function parseCellId(id: string): Cell | null {
  const m = /^X(\d{3})_Y(\d{3})$/.exec(id);
  return m ? { x: Number(m[1]), y: Number(m[2]) } : null;
}

// Cell outline as a closed GeoJSON ring of [lon, lat]. UTM edges are straight lines in 500 m, so 4 corners suffice.
export function cellRing({ x, y }: Cell): [number, number][] {
  const e0 = ORIGIN_E + (x - 1) * CELL;
  const n0 = ORIGIN_N + (y - 1) * CELL;
  return [
    [e0, n0],
    [e0 + CELL, n0],
    [e0 + CELL, n0 + CELL],
    [e0, n0 + CELL],
    [e0, n0],
  ].map(([e, n]) => {
    const [lat, lon] = toLatLon(e, n);
    return [lon, lat];
  });
}

export function cellCenter({ x, y }: Cell): [number, number] {
  const [lat, lon] = toLatLon(ORIGIN_E + (x - 0.5) * CELL, ORIGIN_N + (y - 0.5) * CELL);
  return [lon, lat];
}
