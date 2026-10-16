"use client";

import { useSyncExternalStore } from "react";

// Mock decision store (first slicing pass). Shapes follow the planned RPCs (api_admin_*_zone);
// shortcut: browser localStorage only, swap for lib/supabase calls when the admin wiring starts.
export const REGION = "Sendang Biru–CMC";

export type DecisionKind = "tutup" | "kuota"; // tutup = zone status rehab, kuota = restricted
export type DecisionStatus = "draf" | "terbit" | "dicabut";

export type Decision = {
  id: string;
  code: string;
  kind: DecisionKind;
  status: DecisionStatus;
  cells: string[];
  start: string; // yyyy-mm-dd
  end: string;
  reason: string;
  reopenCriteria: string;
  meetingDate: string;
  meetingSummary: string;
  quotaKg?: number;
  revoke?: { date: string; reason: string; basis: string; meetingDate: string; summary: string };
  history: { at: string; text: string }[];
};

const KEY = "reefish.decisions.v2";
const SEED: Decision[] = [
  {
    id: "sb-c4",
    code: "SB-C4",
    kind: "tutup",
    status: "terbit",
    cells: ["X099_Y148", "X100_Y148", "X100_Y147"],
    start: "2026-10-16",
    end: "2026-10-30",
    reason: "Aktivitas tercatat meningkat dekat zona rehab.",
    reopenCriteria: "Evaluasi kawasan dan kondisi karang membaik.",
    meetingDate: "2026-10-15",
    meetingSummary: "Rapat menyepakati penutupan sementara",
    history: [
      { at: "2026-10-15", text: "Draf dibuat · catatan rapat tersimpan" },
      { at: "2026-10-16", text: "Terbit · tercatat pada audit keputusan" },
    ],
  },
];

let cache: Decision[] | null = null;
const listeners = new Set<() => void>();

function read(): Decision[] {
  if (cache) return cache;
  try {
    const raw = localStorage.getItem(KEY);
    cache = raw ? (JSON.parse(raw) as Decision[]) : SEED;
  } catch {
    cache = SEED;
  }
  return cache;
}

function write(next: Decision[]) {
  cache = next;
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {}
  listeners.forEach((l) => l());
}

export function useDecisions() {
  return useSyncExternalStore(
    (l) => (listeners.add(l), () => listeners.delete(l)),
    read,
    () => SEED,
  );
}

export const today = () => new Date().toISOString().slice(0, 10);

// "berakhir" is derived, never stored: a published decision past its end date.
export const isExpired = (d: Decision) => d.status === "terbit" && d.end < today();

export function saveDecision(d: Decision) {
  const all = read();
  write(all.some((x) => x.id === d.id) ? all.map((x) => (x.id === d.id ? d : x)) : [...all, d]);
}

export function removeDecision(id: string) {
  write(read().filter((d) => d.id !== id));
}

export function resetDemo() {
  write(SEED);
}
