"use client";

import { useDecisions } from "../services/store";

export function useDecision(id: string) {
  return useDecisions().find((d) => d.id === id);
}
