"use client";

import type { Layer, MlColumn } from "../heatmap-parse";
import { ML_LAYERS } from "../ml-layers";

export type MapWindow = "7d" | "30d";
/** Heatmap column (api_heatmap) or ML layer (api_layers) shown on the map. */
export type MapLayer = Layer | `ml:${MlColumn}`;

const WINDOWS: { value: MapWindow; label: string }[] = [
  { value: "30d", label: "30 hari terakhir" },
  { value: "7d", label: "7 hari terakhir" },
];
const HEAT: { value: Layer; label: string }[] = [
  { value: "fatigue", label: "Fatigue (kelelahan grid)" },
  { value: "pressure", label: "Tekanan penangkapan" },
  { value: "cpue", label: "CPUE (kg/jam)" },
];

export function MapFilters({
  window,
  layer,
  onWindow,
  onLayer,
  periods,
  period,
  onPeriod,
  habitat,
  onHabitat,
}: {
  window: MapWindow;
  layer: MapLayer;
  onWindow: (w: MapWindow) => void;
  onLayer: (l: MapLayer) => void;
  periods?: string[];
  period?: string | null;
  onPeriod?: (p: string) => void;
  habitat?: { coral: boolean; mangrove: boolean };
  onHabitat?: (h: { coral: boolean; mangrove: boolean }) => void;
}) {
  const ml = layer.startsWith("ml:");
  return (
    <div className="flex flex-wrap items-center gap-5">
      <label className="relative w-[260px]">
        <span className="sr-only">Lapisan</span>
        <select
          value={layer}
          onChange={(e) => onLayer(e.target.value as MapLayer)}
          className={selectClass}
        >
          <optgroup label="Heatmap aktivitas">
            {HEAT.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </optgroup>
          <optgroup label="Lapisan ML">
            {ML_LAYERS.map((o) => (
              <option key={o.key} value={`ml:${o.key}`}>
                {o.label}
              </option>
            ))}
          </optgroup>
        </select>
        <Caret />
      </label>
      {ml ? (
        <label className="relative w-[170px]">
          <span className="sr-only">Periode data ML</span>
          <select value={period ?? ""} onChange={(e) => onPeriod?.(e.target.value)} className={selectClass} disabled={!periods?.length}>
            {(periods ?? []).map((p) => (
              <option key={p} value={p}>
                Periode {p}
              </option>
            ))}
          </select>
          <Caret />
        </label>
      ) : (
        <label className="relative w-[200px]">
          <span className="sr-only">Periode</span>
          <select value={window} onChange={(e) => onWindow(e.target.value as MapWindow)} className={selectClass}>
            {WINDOWS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
          <Caret />
        </label>
      )}
      {habitat && onHabitat && (
        <fieldset className="flex items-center gap-4 t-body">
          <legend className="sr-only">Habitat</legend>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={habitat.coral}
              onChange={(e) => onHabitat({ ...habitat, coral: e.target.checked })}
              className="size-4 accent-[var(--reefish-action-primary)]"
            />
            Terumbu karang
          </label>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={habitat.mangrove}
              onChange={(e) => onHabitat({ ...habitat, mangrove: e.target.checked })}
              className="size-4 accent-[var(--reefish-action-primary)]"
            />
            Mangrove
          </label>
        </fieldset>
      )}
    </div>
  );
}

const selectClass =
  "min-h-12 w-full cursor-pointer appearance-none rounded-[14px] border border-line bg-surface px-[14px] py-[13px] pr-9 t-label text-ink focus:outline-2 focus:outline-primary disabled:opacity-60";

function Caret() {
  return (
    <span aria-hidden className="pointer-events-none absolute top-1/2 right-4 -translate-y-1/2 text-ink-2">
      ▾
    </span>
  );
}
