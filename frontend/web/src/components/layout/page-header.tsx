import type { ReactNode } from "react";
import { Badge } from "@/components/ui/card";

// "REEFISH · KAWASAN" eyebrow + status pill, then the page title and subtitle (Figma Admin content header).
export function PageHeader({
  title,
  subtitle,
  badge,
  badgeTone = "info",
}: {
  title: string;
  subtitle: ReactNode;
  /** Status pill on the right; omitted when there is nothing to report. */
  badge?: string;
  badgeTone?: "info" | "success" | "error";
}) {
  return (
    <header className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <p className="t-caption text-ink-2">REEFISH · KAWASAN</p>
        {badge && (
          <Badge tone={badgeTone} role={badgeTone === "info" ? undefined : "status"}>
            {badge}
          </Badge>
        )}
      </div>
      <div className="flex max-w-[890px] flex-col gap-2">
        <h1 className="t-title-l text-ink">{title}</h1>
        <p className="t-body text-ink-2">{subtitle}</p>
      </div>
    </header>
  );
}
