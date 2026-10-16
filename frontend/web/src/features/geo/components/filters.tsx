"use client";

export function MapFilters({ value, onChange }: { value: "7d" | "30d"; onChange: (value: "7d" | "30d") => void }) {
  return (
    <label className="relative block w-[184px]">
      <span className="sr-only">Periode heatmap</span>
      <select
        value={value}
        onChange={(event) => onChange(event.target.value as "7d" | "30d")}
        className="min-h-12 w-full cursor-pointer appearance-none rounded-[14px] border border-line bg-surface px-[14px] py-[13px] pr-9 t-label text-ink focus:outline-2 focus:outline-primary"
      >
        <option value="7d">7 hari</option>
        <option value="30d">30 hari</option>
      </select>
      <span aria-hidden className="pointer-events-none absolute top-1/2 right-4 -translate-y-1/2 text-ink-2">
        ▾
      </span>
    </label>
  );
}
