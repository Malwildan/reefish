"use client";

import type { Feature, FeatureCollection, Polygon } from "geojson";
import type { GeoJSONSource, MapLayerMouseEvent, Map as MlMap, StyleSpecification } from "maplibre-gl";
import { useEffect, useMemo, useRef, type ReactNode } from "react";
import { cellRing, parseCellId } from "../grid";
import type { HeatCell, Layer, Scale } from "../heatmap-parse";

export type LegendItem = { label: string; color: string; dashed?: boolean };

const NONE = "#eef1eb";
const RAMP = ["#c9e2ee", "#7fb6d3", "#2f7fa8", "#16415e"];
const FATIGUE = { healthy: "#7fb6d3", tired: "#f08c5a", critical: "#a33e44" };
export const ZONE_COLOR = { restricted: "#e0a43a", rehab: "#fceaec" };

export function legendFor(layer: Layer, scale?: Scale, cpueMax?: number): LegendItem[] {
  const zones: LegendItem[] = [
    { label: "Restricted (flag sistem)", color: "#b07a1a", dashed: true },
    { label: "Restricted (zona admin)", color: ZONE_COLOR.restricted },
    { label: "Rehab (ditutup)", color: ZONE_COLOR.rehab },
  ];
  if (layer === "fatigue") {
    const t = scale?.fatigue.thresholds ?? { tired: 0.4, critical: 0.7 };
    return [
      { label: `Sehat < ${t.tired}`, color: FATIGUE.healthy },
      { label: `Lelah ${t.tired}–${t.critical}`, color: FATIGUE.tired },
      { label: `Kritis ≥ ${t.critical}`, color: FATIGUE.critical },
      { label: "Belum ada data", color: NONE },
      ...zones,
    ];
  }
  const max = layer === "pressure" ? (scale?.pressure.max ?? 1) : (cpueMax ?? 0);
  const unit = layer === "cpue" ? " kg/jam" : "";
  const steps = RAMP.map((color, i) => ({
    label: `${fmt((max * i) / 4)}–${fmt((max * (i + 1)) / 4)}${unit}`,
    color,
  }));
  return [...steps, { label: "Belum ada data", color: NONE }, ...zones];
}

const fmt = (v: number) => (Math.round(v * 100) / 100).toLocaleString("id-ID");

function fillFor(c: HeatCell | undefined, layer: Layer, max: number): [string, number] {
  if (!c) return [NONE, 0.12];
  if (layer === "fatigue") return c.fatigueLevel ? [FATIGUE[c.fatigueLevel], 0.8] : [NONE, 0.3];
  const v = layer === "pressure" ? c.pressure : c.cpue;
  if (v == null || !max) return [NONE, 0.3];
  return [RAMP[Math.min(3, Math.floor((v / max) * 4))], 0.8];
}

const STYLE: StyleSpecification = {
  version: 8,
  sources: {
    sat: {
      type: "raster",
      tiles: ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],
      tileSize: 256,
      maxzoom: 17,
      attribution: "Citra © Esri",
    },
  },
  layers: [
    { id: "bg", type: "background", paint: { "background-color": "#0d2a36" } },
    { id: "sat", type: "raster", source: "sat", paint: { "raster-brightness-max": 0.75 } },
  ],
};

// Rings are pure functions of the cell ID; cache them so selection changes only rebuild properties.
const rings = new Map<string, [number, number][]>();
function ring(id: string) {
  let r = rings.get(id);
  if (!r) {
    const c = parseCellId(id);
    if (!c) return null;
    r = cellRing(c);
    rings.set(id, r);
  }
  return r;
}

type Props = {
  /** Every clickable sea cell (api_sea_mask); cells without heatmap data are drawn faintly. */
  sea: string[];
  cells: HeatCell[];
  layer?: Layer;
  scale?: Scale;
  rehab?: string[];
  restricted?: string[];
  autoFlag?: string[];
  selected?: string[];
  onCellClick?: (id: string) => void;
  title: string;
  subtitle?: string;
  legend?: LegendItem[];
  height?: number;
  overlay?: ReactNode;
  /** Zoom to the selected cells instead of the cells with data. */
  fitSelected?: boolean;
};

export function HeatmapMap({
  sea,
  cells,
  layer = "fatigue",
  scale,
  rehab = [],
  restricted = [],
  autoFlag = [],
  selected = [],
  onCellClick,
  title,
  subtitle,
  legend,
  height = 430,
  overlay,
  fitSelected = false,
}: Props) {
  const box = useRef<HTMLDivElement>(null);
  const map = useRef<MlMap | null>(null);
  const clickRef = useRef(onCellClick);
  useEffect(() => {
    clickRef.current = onCellClick;
  });

  const data = useMemo<FeatureCollection>(() => {
    const byId = new Map(cells.map((c) => [c.id, c]));
    const max =
      layer === "pressure" ? (scale?.pressure.max ?? 1) : (scale?.cpue.max ?? Math.max(0, ...cells.map((c) => c.cpue ?? 0)));
    const rh = new Set(rehab);
    const rs = new Set(restricted);
    const af = new Set(autoFlag);
    const sel = new Set(selected);
    const ids = new Set([...sea, ...cells.map((c) => c.id), ...rehab, ...restricted, ...selected]);
    const features: Feature<Polygon>[] = [];
    for (const id of ids) {
      const r = ring(id);
      if (!r) continue;
      const cell = byId.get(id);
      let [fill, opacity] = fillFor(cell, layer, max);
      if (rh.has(id)) [fill, opacity] = [ZONE_COLOR.rehab, 0.8];
      else if (rs.has(id)) [fill, opacity] = [ZONE_COLOR.restricted, 0.75];
      features.push({
        type: "Feature",
        properties: {
          id,
          fill,
          opacity,
          data: !!cell,
          zone: rh.has(id) ? "rehab" : rs.has(id) ? "restricted" : null,
          auto: af.has(id) && !rh.has(id) && !rs.has(id),
          selected: sel.has(id),
        },
        geometry: { type: "Polygon", coordinates: [r] },
      });
    }
    return { type: "FeatureCollection", features };
  }, [sea, cells, layer, scale, rehab, restricted, autoFlag, selected]);

  const fitted = useRef(false);
  const dataRef = useRef({ data, fitSelected });
  useEffect(() => {
    dataRef.current = { data, fitSelected };
  });

  // Create the map once; maplibre touches window, so it is imported on the client only.
  useEffect(() => {
    let cancelled = false;
    let created: MlMap | null = null;
    (async () => {
      const ml = await import("maplibre-gl");
      if (cancelled || !box.current) return;
      // The bundler does not emit maplibre's worker; postinstall copies it to public/.
      ml.setWorkerUrl("/maplibre-gl-worker.mjs");
      const m = new ml.Map({ container: box.current, style: STYLE, attributionControl: { compact: true } });
      created = m;
      m.addControl(new ml.NavigationControl({ showCompass: false }), "top-right");
      m.on("load", () => {
        m.addSource("cells", { type: "geojson", data: dataRef.current.data });
        m.addLayer({
          id: "cells-fill",
          type: "fill",
          source: "cells",
          paint: { "fill-color": ["get", "fill"], "fill-opacity": ["get", "opacity"] },
        });
        m.addLayer({
          id: "cells-line",
          type: "line",
          source: "cells",
          minzoom: 11,
          paint: { "line-color": "#ffffff", "line-opacity": 0.15, "line-width": 0.5 },
        });
        m.addLayer({
          id: "cells-zone",
          type: "line",
          source: "cells",
          filter: ["!=", ["get", "zone"], null],
          paint: { "line-color": ["match", ["get", "zone"], "rehab", "#a33e44", "#b07a1a"], "line-width": 1.5 },
        });
        // dashed outline = flag sistem, not yet decided by an admin
        m.addLayer({
          id: "cells-auto",
          type: "line",
          source: "cells",
          filter: ["==", ["get", "auto"], true],
          paint: { "line-color": "#f4d58d", "line-width": 2, "line-dasharray": [2, 1.5] },
        });
        m.addLayer({
          id: "cells-selected",
          type: "line",
          source: "cells",
          filter: ["==", ["get", "selected"], true],
          paint: { "line-color": "#ffffff", "line-width": 3 },
        });
        // only now is the source ready for the data effect below
        map.current = m;
        if (dataRef.current.data.features.length) {
          fitted.current = true;
          fit(m, dataRef.current.data, dataRef.current.fitSelected);
        }
      });
      m.on("click", "cells-fill", (e: MapLayerMouseEvent) => {
        const id = e.features?.[0]?.properties?.id;
        if (typeof id === "string") clickRef.current?.(id);
      });
      m.on("mouseenter", "cells-fill", () => {
        if (clickRef.current) m.getCanvas().style.cursor = "pointer";
      });
      m.on("mouseleave", "cells-fill", () => (m.getCanvas().style.cursor = ""));
    })();
    return () => {
      cancelled = true;
      created?.remove();
      map.current = null;
    };
  }, []);

  // Push data changes; the first time real data arrives (sea mask/heatmap load after the map), zoom to it.
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    (m.getSource("cells") as GeoJSONSource | undefined)?.setData(data);
    if (!fitted.current && data.features.length) {
      fitted.current = true;
      fit(m, data, fitSelected);
    }
  }, [data, fitSelected]);

  return (
    <div className="relative overflow-hidden rounded-[20px] bg-blue-800" style={{ height }}>
      <div ref={box} className="h-full w-full" />
      <div className="absolute inset-x-0 top-0 z-10 flex min-h-14 items-center justify-between bg-blue-800 px-5 py-[19px] text-inverse">
        <p className="t-label uppercase">{title}</p>
        {subtitle && <p className="t-caption">{subtitle}</p>}
      </div>
      {overlay}
      {legend && (
        <ul className="absolute bottom-[16px] left-5 z-10 flex max-w-[calc(100%-120px)] flex-wrap items-center gap-x-4 gap-y-1 rounded-[14px] bg-surface px-3 py-[8px]">
          {legend.map((l) => (
            <li key={l.label} className="flex items-center gap-2 t-caption whitespace-nowrap text-ink-2">
              <span
                className="size-3 rounded-[3px]"
                style={l.dashed ? { border: `2px dashed ${l.color}` } : { background: l.color, border: "1px solid #d6deda" }}
              />
              {l.label}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function fit(m: MlMap, data: FeatureCollection, selectedOnly: boolean) {
  const pick = (f: Feature) => (selectedOnly ? f.properties?.selected : f.properties?.data || f.properties?.zone);
  let chosen = data.features.filter(pick);
  if (!chosen.length) chosen = data.features;
  const pts = chosen.flatMap((f) => (f.geometry.type === "Polygon" ? f.geometry.coordinates[0] : []));
  if (!pts.length) return m.jumpTo({ center: [112.68, -8.5], zoom: 10 });
  const lons = pts.map((p) => p[0]);
  const lats = pts.map((p) => p[1]);
  m.fitBounds(
    [
      [Math.min(...lons), Math.min(...lats)],
      [Math.max(...lons), Math.max(...lats)],
    ],
    { padding: { top: 90, bottom: 80, left: 30, right: 30 }, duration: 0, maxZoom: 13 },
  );
}
