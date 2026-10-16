// Shapes from contracts/map-zones-api.openapi.yaml (ZoneRules, ZoneAggregate, ZoneDetail, ...).
// The mock service returns exactly these, so wiring the real RPCs only swaps services/zones.ts.

export type ZoneStatus = "restricted" | "rehab";
export type GridStatus = ZoneStatus | "normal";

export type ZoneRules = {
  max_catch_kg_per_period: number | null;
  max_trips_per_period: number | null;
  period: "weekly" | "monthly";
  open_schedule: { days: number[]; hours: [string, string] } | null;
};

export type ZoneQuota = {
  period_start: string;
  period_end: string;
  used_kg?: number;
  used_trips?: number;
  remaining_kg: number | null;
  remaining_trips: number | null;
  exhausted: boolean;
};

export type ZoneAggregate = {
  grid_count: number;
  area_km2: number;
  coral_grid_count: number;
  coral_pct: number | null;
  fatigue_avg: number | null;
  fatigue_max: number | null;
  fatigue_distribution: { healthy: number; tired: number; critical: number };
  flagged_grid_count: number;
  trip_count_30d: number;
  catch_kg_30d: number;
  fishing_hours_30d: number;
  cpue_30d: number | null;
  violation_count_30d: number;
  quota: ZoneQuota | null;
};

export type Conflict = { grid_id: string; zone_id: string; zone_name: string; zone_status: ZoneStatus };

export type ZonePreview = { aggregate: ZoneAggregate; conflicts: Conflict[]; invalid_grid_ids: string[] };

export type ZoneDetail = {
  id: string;
  name: string;
  status: ZoneStatus;
  rules: ZoneRules | null;
  reason: string;
  note: string | null;
  effective_from: string; // ISO date-time
  effective_until: string | null;
  grid_ids: string[];
  is_active: boolean;
  archived_at: string | null;
  version: number;
  created_at: string;
  updated_at: string;
};

export type ZoneDetailWithAggregate = ZoneDetail & { aggregate: ZoneAggregate };

export type ZoneSummary = Pick<
  ZoneDetail,
  "id" | "name" | "status" | "effective_from" | "effective_until" | "is_active" | "archived_at" | "updated_at"
> & {
  grid_count: number;
  area_km2: number;
  fatigue_avg: number | null;
  fatigue_max: number | null;
  quota_remaining_kg: number | null;
  quota_exhausted: boolean;
};

export type ZoneHistoryAction = "create" | "update_meta" | "update_rules" | "update_status" | "archive";

export type ZoneHistoryItem = {
  id: number;
  zone_id: string;
  zone_name: string;
  action: ZoneHistoryAction;
  before: { status?: GridStatus; [k: string]: unknown } | null;
  after: { status?: GridStatus; [k: string]: unknown } | null;
  reason: string | null;
  changed_by: { id: string; name: string | null } | null;
  changed_at: string;
};

export type CreateZoneInput = {
  name: string;
  status: ZoneStatus;
  grid_ids: string[];
  rules: ZoneRules | null;
  effective_from: string | null;
  effective_until: string | null;
  reason: string;
  note: string | null;
};

export type EditZoneInput = Partial<Pick<CreateZoneInput, "name" | "rules" | "effective_from" | "effective_until" | "note">> & {
  reason: string;
  version: number;
};

export type EditStatusInput = {
  status: GridStatus;
  reason: string;
  rules?: ZoneRules | null;
  version: number;
};

// PostgREST error shape produced by private.fail: message = code, hint = text, details = JSON.
export class ApiError extends Error {
  code: string;
  details?: Record<string, unknown>;
  constructor(code: string, hint: string, details?: Record<string, unknown>) {
    super(hint);
    this.code = code;
    this.details = details;
  }
}
