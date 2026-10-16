// Pure helpers for push-dispatch (AGENTS.md 12.B.10). No I/O here so they run under `deno test`.

export type Claimed = {
  id: number;
  change: string;
  heatmap_version: number;
  zone: { id: string | null; name: string | null; status: string | null };
  tokens: string[];
};

const CHANGE_TEXT: Record<string, string> = {
  created: "Zona baru",
  status_changed: "Status zona berubah",
  grids_added: "Area zona diperluas",
  rules_changed: "Aturan zona berubah",
  quota_exhausted: "Kuota zona habis",
  dissolved: "Zona dibuka kembali",
};

export function notificationText(p: Claimed): { title: string; body: string } {
  const title = CHANGE_TEXT[p.change] ?? "Peta zona diperbarui";
  const name = p.zone.name ?? "zona";
  const body = p.change === "dissolved"
    ? `${name} tidak lagi dibatasi. Buka aplikasi untuk peta terbaru.`
    : p.zone.status === "rehab"
    ? `${name}: dilarang menangkap ikan (rehabilitasi). Buka aplikasi untuk peta terbaru.`
    : `${name}: penangkapan dibatasi kuota. Buka aplikasi untuk peta terbaru.`;
  return { title, body };
}

// FCM HTTP v1 message for one device token. Data values must be strings.
export function buildMessage(p: Claimed, token: string) {
  return {
    message: {
      token,
      notification: notificationText(p),
      data: {
        type: "zone_changed",
        change: p.change,
        zone_id: p.zone.id ?? "",
        heatmap_version: String(p.heatmap_version),
      },
      android: { priority: "high", collapse_key: `zone_${p.zone.id ?? "map"}` },
    },
  };
}

// FCM errors that mean the token will never work again.
export function isDeadToken(status: number, body: string): boolean {
  return status === 404 || (status === 400 && body.includes("INVALID_ARGUMENT") && body.includes("token")) ||
    body.includes("UNREGISTERED");
}
