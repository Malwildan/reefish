"use client";

import type { Layer } from "../heatmap-parse";

export type MapWindow = "7d" | "30d";

const WINDOWS: { value: MapWindow; label: string }[] = [
  { value: "30d", label: "30 hari terakhir" },
  { value: "7d", label: "7 hari terakhir" },
];
const LAYERS: { value: Layer; label: string }[] = [
  { value: "fatigue", label: "Fatigue (kelelahan grid)" },
  { value: "pressure", label: "Tekanan penangkapan" },
  { value: "cpue", label: "CPUE (kg/jam)" },
];

/** Period = api_heatmap p_window; layer = which heatmap column colours the cells. */
export function MapFilters({
  window,
  layer,
  onWindow,
  onLayer,
}: {
  window: MapWindow;
  layer: Layer;
  onWindow: (w: MapWindow) => void;
  onLayer: (l: Layer) => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-7">
      <Select label="Periode" width={200} value={window} onChange={(v) => onWindow(v as MapWindow)} options={WINDOWS} />
      <Select label="Lapisan" width={240} value={layer} onChange={(v) => onLayer(v as Layer)} options={LAYERS} />
    </div>
  );
}

function Select({
  label,
  width,
  value,
  onChange,
  options,
}: {
  label: string;
  width: number;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <label className="relative" style={{ width }}>
      <span className="sr-only">{label}</span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="min-h-12 w-full cursor-pointer appearance-none rounded-[14px] border border-line bg-surface px-[14px] py-[13px] pr-9 t-label text-ink focus:outline-2 focus:outline-primary"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
      <span aria-hidden className="pointer-events-none absolute top-1/2 right-4 -translate-y-1/2 text-ink-2">
        ▾
      </span>
    </label>
  );
}
