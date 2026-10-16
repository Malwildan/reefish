import Link from "next/link";
import { Badge } from "@/components/ui/card";
import { ACTION_LABEL, fmtDateTime, rulesText, STATUS_LABEL, STATUS_TONE } from "../format";
import type { GridStatus, ZoneHistoryItem, ZoneRules } from "../types";

function change(h: ZoneHistoryItem) {
  const b = h.before;
  const a = h.after;
  if (h.action === "create" && a?.status) return `Dibuat sebagai ${STATUS_LABEL[a.status]} · ${(a.grid_ids as string[] | undefined)?.length ?? 0} grid`;
  if (h.action === "update_status" && b?.status && a?.status) return `${STATUS_LABEL[b.status]} → ${STATUS_LABEL[a.status]}`;
  if (h.action === "update_rules") return `Kuota: ${rulesText((a?.rules as ZoneRules | null) ?? null)}`;
  if (h.action === "archive") return `${(a?.released_grid_ids as string[] | undefined)?.length ?? 0} grid kembali normal`;
  return "Nama, masa berlaku, atau catatan diubah";
}

export function HistoryList({ items, showZone }: { items: ZoneHistoryItem[]; showZone?: boolean }) {
  if (!items.length) return <p className="t-body text-ink-2">Belum ada riwayat.</p>;
  return (
    <ol className="flex flex-col">
      {items.map((h) => {
        const to = (h.after?.status ?? null) as GridStatus | null;
        return (
          <li key={h.id} className="relative flex gap-4 border-l-2 border-line pb-5 pl-5 last:pb-0">
            <span className="absolute top-1 -left-[7px] size-3 rounded-full bg-primary" aria-hidden />
            <div className="flex min-w-0 flex-1 flex-col gap-1">
              <p className="t-caption text-ink-2">
                {fmtDateTime(h.changed_at)} · {h.changed_by?.name ?? "Sistem"}
              </p>
              <p className="flex flex-wrap items-center gap-2 t-label">
                {showZone && (
                  <Link href={`/area/${h.zone_id}`} className="underline decoration-line underline-offset-4 hover:decoration-primary">
                    {h.zone_name}
                  </Link>
                )}
                <span>{ACTION_LABEL[h.action]}</span>
                {to && h.action !== "create" && <Badge tone={STATUS_TONE[to]}>{STATUS_LABEL[to]}</Badge>}
              </p>
              <p className="t-body text-ink-2">{change(h)}</p>
              {h.reason && <p className="t-body">Alasan: {h.reason}</p>}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
