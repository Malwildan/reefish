// Shapes from contracts/map-zones-api.openapi.yaml (ZoneRules, ZoneAggregate, ZoneDetail, ...).

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

export type ZonePreview = {
  aggregate: ZoneAggregate;
  conflicts: Conflict[];
  invalid_grid_ids: string[];
  /** Normal cells the system auto-flagged as restricted (critical fatigue), awaiting an admin decision. */
  auto_flagged_grid_ids: string[];
};

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

// api_admin_list_zones row (no effective_from / archived_at; open the detail for those)
export type ZoneSummary = Pick<ZoneDetail, "id" | "name" | "status" | "effective_until" | "is_active" | "updated_at"> & {
  grid_count: number;
  area_km2: number;
  fatigue_avg: number | null;
  fatigue_max: number | null;
  quota_remaining_kg: number | null;
  quota_exhausted: boolean;
};

export type ZoneHistoryAction =
  | "create"
  | "update_meta"
  | "update_rules"
  | "add_grids"
  | "remove_grids"
  | "update_status"
  | "archive";

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
  /** move takes cells out of a restricted zone; rehab cells are never moved (zero tolerance). */
  on_conflict?: "reject" | "move";
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

export { ApiError } from "../../lib/api/error.ts";

// ---- other admin RPCs ---------------------------------------------------------------------

export type GridDetail = {
  grid_id: string;
  grid_x: number;
  grid_y: number;
  centroid: { lat: number; lng: number };
  is_sea: boolean;
  has_coral: boolean;
  zone: { id: string; name: string; status: ZoneStatus } | null;
  auto_flag: "restricted" | null;
  auto_flagged_at: string | null;
  suggestion: "restrict" | "reopen" | null;
  days_low_fatigue: number;
  flag_dismissed_until: string | null;
  stats: {
    fatigue_index: number | null;
    fatigue_level: "healthy" | "tired" | "critical" | null;
    pressure_index: number | null;
    trip_count_7d: number;
    trip_count_30d: number;
    fishing_hours_30d: number;
    catch_kg_30d: number;
    cpue_30d: number | null;
    last_visited_at: string | null;
  } | null;
  fatigue_trend_30d: [string, number][];
};

export type RestrictSuggestion = {
  grid_id: string;
  has_coral: boolean;
  fatigue_index: number;
  fatigue_level: string;
  flagged_at: string;
  days_flagged: number;
  flagged_neighbor_ids: string[];
};

export type ReopenSuggestion = {
  zone_id: string;
  name: string;
  grid_ids: string[];
  suggested_count: number;
  grid_count: number;
  suggested_pct: number;
  fatigue_avg: number | null;
  days_low_min: number;
  version: number;
};

type Page<T> = { data: T[]; meta: { page: number; limit: number; total: number } };

export type Suggestions = {
  restrict: Page<RestrictSuggestion> | null;
  reopen: Page<ReopenSuggestion> | null;
  heatmap_version: number;
};

export type StatsSummary = {
  window: "7d" | "30d";
  zones: { rehab: number; restricted: number; protected_area_km2: number };
  flags: { active: number; dismissed: number };
  trips: { count: number; catch_kg: number; active_fishers: number };
  violations: { count: number };
  heatmap_version: number;
  generated_at: string;
};

export type RefreshResult = { status: string; job_id: string; heatmap_version: number; changed_cells: number; finished_at: string };
