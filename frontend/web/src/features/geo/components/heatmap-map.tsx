"use client";

import type { FeatureCollection } from "geojson";
import type { GeoJSONSource, MapLayerMouseEvent, Map as MlMap, Marker, StyleSpecification } from "maplibre-gl";
import { useEffect, useMemo, useRef, type ReactNode } from "react";
import { cellRing, parseCellId } from "../grid";
import { PRIVACY_MIN, type HeatCell } from "../mock-heatmap";

export type MapMarker = {
  id: string;
  label: string;
  lngLat: [number, number];
  active?: boolean;
  anchor?: "top" | "bottom";
  onClick?: () => void;
};
export type LegendItem = { label: string; color: string };

// Cell colours: fishers per cell (3, 4+, below the privacy minimum), zone status, live violations.
export const LEGEND = {
  low: { label: "3 nelayan", color: "#1e6387" },
  high: { label: "4+ nelayan", color: "#16415e" },
  none: { label: "Data belum cukup", color: "#eef1eb" },
  restricted: { label: "Restricted (kuota)", color: "#e0a43a" },
  rehab: { label: "Rehab (ditutup)", color: "#fceaec" },
  flag: { label: "Indikasi pelanggaran", color: "#a33e44" },
  selected: { label: "Dipilih", color: "#ffffff" },
} satisfies Record<string, LegendItem>;

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

type Props = {
  cells: HeatCell[];
  /** Cells of active rehab zones (zero tolerance, disabled). */
  rehab?: string[];
  /** Cells of active restricted zones (quota). */
  restricted?: string[];
  flagged?: string[];
  selected?: string[];
  markers?: MapMarker[];
  trails?: [number, number][][];
  onCellClick?: (id: string) => void;
  title: string;
  subtitle?: string;
  legend?: LegendItem[];
  height?: number;
  overlay?: ReactNode;
  /** Zoom to the selected cells instead of all cells (decision previews). */
  fitSelected?: boolean;
};

function toGeoJSON(
  cells: HeatCell[],
  rehab: Set<string>,
  restricted: Set<string>,
  flagged: Set<string>,
  selected: Set<string>,
): FeatureCollection {
  const ids = new Set([...cells.map((c) => c.id), ...rehab, ...restricted, ...selected]);
  const byId = new Map(cells.map((c) => [c.id, c]));
  const features: FeatureCollection["features"] = [];
  for (const id of ids) {
    const cell = parseCellId(id);
    if (!cell) continue;
    const fishers = byId.get(id)?.fishers ?? 0;
    const level = flagged.has(id)
      ? "flag"
      : rehab.has(id)
        ? "rehab"
        : restricted.has(id)
          ? "restricted"
          : fishers >= 4
          ? "high"
          : fishers >= PRIVACY_MIN
            ? "low"
            : "none";
    features.push({
      type: "Feature",
      properties: { id, level, selected: selected.has(id) },
      geometry: { type: "Polygon", coordinates: [cellRing(cell)] },
    });
  }
  return { type: "FeatureCollection", features };
}

export function HeatmapMap({
  cells,
  rehab = [],
  restricted = [],
  flagged = [],
  selected = [],
  markers = [],
  trails = [],
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
  const markerRefs = useRef<Marker[]>([]);
  const clickRef = useRef(onCellClick);
  useEffect(() => {
    clickRef.current = onCellClick;
  });

  const data = useMemo(
    () => toGeoJSON(cells, new Set(rehab), new Set(restricted), new Set(flagged), new Set(selected)),
    [cells, rehab, restricted, flagged, selected],
  );
  const trailData = useMemo<FeatureCollection>(
    () => ({
      type: "FeatureCollection",
      features: trails.map((t) => ({ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: t } })),
    }),
    [trails],
  );
  const dataRef = useRef({ data, trailData, fitSelected });
  useEffect(() => {
    dataRef.current = { data, trailData, fitSelected };
  });

  // Create the map once; maplibre touches window, so it is imported on the client only.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const ml = await import("maplibre-gl");
      if (cancelled || !box.current) return;
      // The bundler does not emit maplibre's worker; postinstall copies it to public/.
      ml.setWorkerUrl("/maplibre-gl-worker.mjs");
      const m = new ml.Map({ container: box.current, style: STYLE, attributionControl: { compact: true } });
      m.addControl(new ml.NavigationControl({ showCompass: false }), "top-right");
      map.current = m;
      m.on("load", () => {
        m.addSource("cells", { type: "geojson", data: dataRef.current.data });
        m.addSource("trails", { type: "geojson", data: dataRef.current.trailData });
        m.addLayer({
          id: "cells-fill",
          type: "fill",
          source: "cells",
          paint: {
            "fill-color": [
              "match",
              ["get", "level"],
              "flag", LEGEND.flag.color,
              "rehab", LEGEND.rehab.color,
              "restricted", LEGEND.restricted.color,
              "high", LEGEND.high.color,
              "low", LEGEND.low.color,
              LEGEND.none.color,
            ],
            "fill-opacity": ["match", ["get", "level"], "none", 0.35, "rehab", 0.75, "restricted", 0.7, 0.8],
          },
        });
        m.addLayer({
          id: "cells-line",
          type: "line",
          source: "cells",
          paint: { "line-color": "#ffffff", "line-opacity": 0.18, "line-width": 0.5 },
        });
        m.addLayer({
          id: "cells-zone",
          type: "line",
          source: "cells",
          filter: ["match", ["get", "level"], ["rehab", "restricted"], true, false],
          paint: {
            "line-color": ["match", ["get", "level"], "rehab", LEGEND.flag.color, "#b07a1a"],
            "line-width": 1.5,
          },
        });
        m.addLayer({
          id: "cells-selected",
          type: "line",
          source: "cells",
          filter: ["==", ["get", "selected"], true],
          paint: { "line-color": LEGEND.selected.color, "line-width": 3 },
        });
        m.addLayer({
          id: "trails",
          type: "line",
          source: "trails",
          paint: { "line-color": "#ffffff", "line-width": 2, "line-dasharray": [1, 1.5], "line-opacity": 0.85 },
        });
        fit(m, dataRef.current.data, dataRef.current.fitSelected);
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
      map.current?.remove();
      map.current = null;
    };
  }, []);

  useEffect(() => {
    (map.current?.getSource("cells") as GeoJSONSource | undefined)?.setData(data);
    (map.current?.getSource("trails") as GeoJSONSource | undefined)?.setData(trailData);
  }, [data, trailData]);

  // Violation pills as HTML markers (Figma "Violation marker").
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const ml = await import("maplibre-gl");
      if (cancelled) return;
      markerRefs.current.forEach((mk) => mk.remove());
      markerRefs.current = [];
      for (const mk of markers) {
        const el = document.createElement("button");
        el.type = "button";
        el.className =
          "flex min-h-11 items-center gap-2 rounded-[20px] bg-error px-[10px] py-2 t-body text-inverse " +
          (mk.active ? "border-[3px] border-white" : "border border-white");
        el.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 3 2 21h20L12 3z"/><path d="M12 10v5M12 18h.01" stroke-linecap="round"/></svg>`;
        el.append(mk.label);
        el.setAttribute("aria-label", `Indikasi ${mk.label}`);
        if (mk.onClick) el.addEventListener("click", mk.onClick);
        const wait = () => {
          if (cancelled) return;
          if (!map.current) return void setTimeout(wait, 100);
          markerRefs.current.push(new ml.Marker({ element: el, anchor: mk.anchor ?? "bottom" }).setLngLat(mk.lngLat).addTo(map.current));
        };
        wait();
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [markers]);

  return (
    <div className="relative overflow-hidden rounded-[20px] bg-blue-800" style={{ height }}>
      <div ref={box} className="h-full w-full" />
      <div className="absolute inset-x-0 top-0 z-10 flex min-h-14 items-center justify-between bg-blue-800 px-5 py-[19px] text-inverse">
        <p className="t-label uppercase">{title}</p>
        {subtitle && <p className="t-caption">{subtitle}</p>}
      </div>
      {overlay}
      {legend && (
        <ul className="absolute bottom-[16px] left-5 z-10 flex min-h-10 max-w-[calc(100%-40px)] flex-wrap items-center gap-4 rounded-[14px] bg-surface px-3 py-[10px]">
          {legend.map((l) => (
            <li key={l.label} className="flex items-center gap-2 t-caption whitespace-nowrap text-ink-2">
              <span className="size-3 rounded-[3px]" style={{ background: l.color }} />
              {l.label}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function fit(m: MlMap, data: FeatureCollection, selectedOnly: boolean) {
  const chosen = selectedOnly ? data.features.filter((f) => f.properties?.selected) : [];
  const pts = (chosen.length ? chosen : data.features).flatMap((f) =>
    f.geometry.type === "Polygon" ? f.geometry.coordinates[0] : [],
  );
  if (!pts.length) return m.jumpTo({ center: [112.68, -8.5], zoom: 11 });
  const lons = pts.map((p) => p[0]);
  const lats = pts.map((p) => p[1]);
  m.fitBounds(
    [
      [Math.min(...lons), Math.min(...lats)],
      [Math.max(...lons), Math.max(...lats)],
    ],
    { padding: { top: 120, bottom: 70, left: 20, right: 20 }, duration: 0, maxZoom: 12.5 },
  );
}
