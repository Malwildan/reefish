"use client";

import { useState } from "react";

// Period / layer / gear filters (Figma "Filter Periode/Lapisan/Alat"). Values only change the labels
// for now; they become RPC parameters once the dashboard reads real data.
const FILTERS = [
  { key: "periode", label: "Periode", width: 184, options: ["4 minggu tertutup", "8 minggu tertutup", "Bulan ini"] },
  { key: "lapisan", label: "Lapisan", width: 224, options: ["Trip tercatat", "Waktu menangkap", "Nelayan unik"] },
  { key: "alat", label: "Alat tangkap", width: 190, options: ["Semua alat", "Pancing ulur", "Bubu"] },
];

export function MapFilters() {
  const [values, setValues] = useState(() => FILTERS.map((f) => f.options[0]));
  return (
    <div className="flex flex-wrap items-center gap-7">
      {FILTERS.map((f, i) => (
        <label key={f.key} className="relative" style={{ width: f.width }}>
          <span className="sr-only">{f.label}</span>
          <select
            value={values[i]}
            onChange={(e) => setValues((v) => v.map((x, j) => (j === i ? e.target.value : x)))}
            className="min-h-12 w-full cursor-pointer appearance-none rounded-[14px] border border-line bg-surface px-[14px] py-[13px] pr-9 t-label text-ink focus:outline-2 focus:outline-primary"
          >
            {f.options.map((o) => (
              <option key={o}>{o}</option>
            ))}
          </select>
          <span aria-hidden className="pointer-events-none absolute top-1/2 right-4 -translate-y-1/2 text-ink-2">
            ▾
          </span>
        </label>
      ))}
    </div>
  );
}
