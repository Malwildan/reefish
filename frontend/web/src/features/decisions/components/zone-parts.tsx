"use client";

import { Badge, Card, Notice } from "@/components/ui/card";
import { Field, SelectField } from "@/components/ui/field";
import type { FieldErrors } from "../schemas";
import { DAY_LABEL, fmtDate, num, STATUS_HINT, STATUS_LABEL } from "../format";
import type { ZoneAggregate, ZoneRules, ZoneStatus, ZoneSummary } from "../types";

// ---- quota rules (restricted) -------------------------------------------------------------

export type RulesDraft = {
  kg: string;
  trips: string;
  period: ZoneRules["period"];
  scheduled: boolean;
  days: number[];
  from: string;
  to: string;
};

export const emptyRules = (): RulesDraft => ({
  kg: "",
  trips: "",
  period: "monthly",
  scheduled: false,
  days: [1, 2, 3, 4, 5],
  from: "05:00",
  to: "17:00",
});

export const draftFromRules = (r: ZoneRules | null): RulesDraft =>
  r
    ? {
        kg: r.max_catch_kg_per_period?.toString() ?? "",
        trips: r.max_trips_per_period?.toString() ?? "",
        period: r.period,
        scheduled: !!r.open_schedule,
        days: r.open_schedule?.days ?? [1, 2, 3, 4, 5],
        from: r.open_schedule?.hours[0] ?? "05:00",
        to: r.open_schedule?.hours[1] ?? "17:00",
      }
    : emptyRules();

export const rulesFromDraft = (d: RulesDraft): ZoneRules => ({
  max_catch_kg_per_period: d.kg.trim() === "" ? null : Number(d.kg),
  max_trips_per_period: d.trips.trim() === "" ? null : Number(d.trips),
  period: d.period,
  open_schedule: d.scheduled ? { days: [...d.days].sort(), hours: [d.from, d.to] } : null,
});

export function RulesFields({
  value,
  onChange,
  errors,
  capacity,
  idPrefix = "r",
}: {
  value: RulesDraft;
  onChange: (v: RulesDraft) => void;
  errors: FieldErrors;
  capacity?: ZoneAggregate;
  idPrefix?: string;
}) {
  const set = <K extends keyof RulesDraft>(k: K, v: RulesDraft[K]) => onChange({ ...value, [k]: v });
  // capacity of the selected grids, scaled to the chosen quota period
  const scale = value.period === "monthly" ? 1 : 7 / 30;
  const capKg = capacity ? Math.round(capacity.catch_kg_30d * scale) : null;
  const capTrips = capacity ? Math.round(capacity.trip_count_30d * scale) : null;
  const pct = (v: string, cap: number | null) =>
    v.trim() && cap ? ` · ${Math.round((Number(v) / cap) * 100)}% dari aktivitas saat ini` : "";

  return (
    <fieldset className="flex flex-col gap-3">
      <legend className="mb-2 t-label">Kuota agregat seluruh grid zona</legend>
      {capacity && (
        <div className="grid grid-cols-3 gap-2 rounded-2xl bg-warning-bg p-3 text-warning">
          <Cap label={`Tangkapan ${value.period === "monthly" ? "/bulan" : "/minggu"}`} value={`${num(capKg)} kg`} />
          <Cap label={`Trip ${value.period === "monthly" ? "/bulan" : "/minggu"}`} value={num(capTrips)} />
          <Cap label="CPUE 30 hari" value={capacity.cpue_30d == null ? "—" : `${num(capacity.cpue_30d, 1)} kg/jam`} />
          <p className="col-span-3 t-caption">Kapasitas saat ini dari {capacity.grid_count} grid terpilih (data 30 hari).</p>
        </div>
      )}
      <SelectField
        id={`${idPrefix}-period`}
        label="Periode kuota"
        value={value.period}
        onChange={(e) => set("period", e.target.value as ZoneRules["period"])}
        error={errors.period}
      >
        <option value="monthly">Per bulan (mulai tanggal 1)</option>
        <option value="weekly">Per minggu (mulai Senin 00:00 WIB)</option>
      </SelectField>
      <div className="grid grid-cols-2 gap-3">
        <Field
          id={`${idPrefix}-kg`}
          label="Maks. tangkapan (kg)"
          type="number"
          min={1}
          inputMode="decimal"
          value={value.kg}
          onChange={(e) => set("kg", e.target.value)}
          error={errors.max_catch_kg_per_period}
        />
        <Field
          id={`${idPrefix}-trips`}
          label="Maks. trip"
          type="number"
          min={1}
          step={1}
          inputMode="numeric"
          value={value.trips}
          onChange={(e) => set("trips", e.target.value)}
          error={errors.max_trips_per_period}
        />
      </div>
      {(pct(value.kg, capKg) || pct(value.trips, capTrips)) && (
        <p className="t-caption text-ink-2">
          {value.kg && `Kuota tangkapan${pct(value.kg, capKg)}. `}
          {value.trips && `Kuota trip${pct(value.trips, capTrips)}.`}
        </p>
      )}
      {errors.rules && (
        <p className="t-caption text-error" role="alert">
          {errors.rules}
        </p>
      )}
      <label className="flex items-center gap-2 t-body">
        <input
          type="checkbox"
          checked={value.scheduled}
          onChange={(e) => set("scheduled", e.target.checked)}
          className="size-4 accent-[var(--reefish-action-primary)]"
        />
        Batasi hari &amp; jam buka (opsional)
      </label>
      {value.scheduled && (
        <div className="flex flex-col gap-3 rounded-2xl border border-line p-3">
          <div className="flex flex-wrap gap-2" role="group" aria-label="Hari buka">
            {DAY_LABEL.map((d, i) => {
              const day = i + 1;
              const on = value.days.includes(day);
              return (
                <button
                  key={d}
                  type="button"
                  aria-pressed={on}
                  onClick={() => set("days", on ? value.days.filter((x) => x !== day) : [...value.days, day])}
                  className={`min-h-9 rounded-full px-3 t-caption ${on ? "bg-primary text-inverse" : "bg-subtle text-ink-2"}`}
                >
                  {d}
                </button>
              );
            })}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field id={`${idPrefix}-from`} label="Buka (WIB)" type="time" value={value.from} onChange={(e) => set("from", e.target.value)} />
            <Field id={`${idPrefix}-to`} label="Tutup (WIB)" type="time" value={value.to} onChange={(e) => set("to", e.target.value)} />
          </div>
          {errors.open_schedule && <p className="t-caption text-error">{errors.open_schedule}</p>}
        </div>
      )}
    </fieldset>
  );
}

function Cap({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col">
      <span className="t-caption">{label}</span>
      <span className="t-label">{value}</span>
    </div>
  );
}

// ---- status choice ------------------------------------------------------------------------

export function StatusChoice({
  value,
  onChange,
  options = ["restricted", "rehab"],
  error,
}: {
  value: ZoneStatus | null;
  onChange: (s: ZoneStatus) => void;
  options?: ZoneStatus[];
  error?: string;
}) {
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-2 t-label">Status zona</legend>
      <div className="grid grid-cols-2 gap-3">
        {options.map((s) => {
          const on = value === s;
          return (
            <label
              key={s}
              className={`flex cursor-pointer flex-col gap-1 rounded-[14px] border-2 p-3 ${
                on ? (s === "rehab" ? "border-error bg-error-bg" : "border-warm bg-warning-bg") : "border-line bg-subtle"
              }`}
            >
              <span className="flex items-center gap-2">
                <input type="radio" name="zone-status" value={s} checked={on} onChange={() => onChange(s)} className="accent-[var(--reefish-action-primary)]" />
                <span className="t-label">{STATUS_LABEL[s]}</span>
              </span>
              <span className="t-caption text-ink-2">{STATUS_HINT[s]}</span>
            </label>
          );
        })}
      </div>
      {error && <p className="t-caption text-error">{error}</p>}
    </fieldset>
  );
}

// ---- aggregate ----------------------------------------------------------------------------

export function AggregatePanel({ a, title = "Agregat grid" }: { a: ZoneAggregate; title?: string }) {
  const dist = a.fatigue_distribution;
  const total = dist.healthy + dist.tired + dist.critical || 1;
  return (
    <Card className="flex flex-col gap-4">
      <h2 className="t-title-m">{title}</h2>
      <div className="grid grid-cols-4 gap-3">
        <Stat label="Grid" value={`${a.grid_count}`} sub={`${num(a.area_km2, 2)} km²`} />
        <Stat label="Terumbu karang" value={`${a.coral_grid_count} grid`} sub={a.coral_pct == null ? "—" : `${num(a.coral_pct, 1)}%`} />
        <Stat label="Fatigue rata-rata" value={num(a.fatigue_avg, 2)} sub={`maks ${num(a.fatigue_max, 2)}`} />
        <Stat label="Auto-flag" value={`${a.flagged_grid_count} grid`} sub="fatigue kritis" />
        <Stat label="Trip 30 hari" value={num(a.trip_count_30d)} />
        <Stat label="Tangkapan 30 hari" value={`${num(a.catch_kg_30d)} kg`} />
        <Stat label="Jam menangkap" value={`${num(a.fishing_hours_30d)} jam`} sub={a.cpue_30d == null ? undefined : `CPUE ${num(a.cpue_30d, 1)} kg/jam`} />
        <Stat label="Pelanggaran 30 hari" value={`${a.violation_count_30d}`} />
      </div>
      <div className="flex flex-col gap-2">
        <p className="t-caption text-ink-2">Sebaran fatigue</p>
        <div className="flex h-3 overflow-hidden rounded-full bg-subtle" role="img" aria-label={`Sehat ${dist.healthy}, lelah ${dist.tired}, kritis ${dist.critical} grid`}>
          <span className="bg-success" style={{ width: `${(dist.healthy / total) * 100}%` }} />
          <span className="bg-warm" style={{ width: `${(dist.tired / total) * 100}%` }} />
          <span className="bg-error" style={{ width: `${(dist.critical / total) * 100}%` }} />
        </div>
        <p className="t-caption text-ink-2">
          Sehat {dist.healthy} · Lelah {dist.tired} · Kritis {dist.critical}
        </p>
      </div>
      {a.quota && (
        <Notice tone={a.quota.exhausted ? "error" : "warning"} className="flex flex-col gap-1">
          <span className="t-label">{a.quota.exhausted ? "Kuota periode ini habis" : "Kuota periode berjalan"}</span>
          <span>
            {fmtDate(a.quota.period_start)} – {fmtDate(a.quota.period_end)} · terpakai {num(a.quota.used_kg)} kg / {num(a.quota.used_trips)} trip
          </span>
          <span>
            Sisa {a.quota.remaining_kg == null ? "—" : `${num(a.quota.remaining_kg)} kg`} ·{" "}
            {a.quota.remaining_trips == null ? "—" : `${num(a.quota.remaining_trips)} trip`}
          </span>
        </Notice>
      )}
    </Card>
  );
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="flex flex-col gap-1 rounded-[14px] bg-subtle p-3">
      <span className="t-caption text-ink-2">{label}</span>
      <span className="t-title-m">{value}</span>
      {sub && <span className="t-caption text-ink-2">{sub}</span>}
    </div>
  );
}

// ---- status of every zone -----------------------------------------------------------------

export function StatusOverview({ zones }: { zones: ZoneSummary[] }) {
  const active = zones.filter((z) => z.is_active);
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="t-caption text-ink-2">Status seluruh zona:</span>
      <Badge tone="warning">{active.filter((z) => z.status === "restricted").length} restricted</Badge>
      <Badge tone="error">{active.filter((z) => z.status === "rehab").length} rehab</Badge>
      <Badge tone="info">{zones.length - active.length} kembali normal</Badge>
    </div>
  );
}
