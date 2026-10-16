import type { ComponentProps } from "react";

export function Card({ className = "", ...rest }: ComponentProps<"section">) {
  return <section className={`rounded-[20px] bg-surface p-5 ${className}`} {...rest} />;
}

const tones = {
  info: "bg-info-bg text-info",
  success: "bg-success-bg text-success",
  error: "bg-error-bg text-error",
  warning: "bg-warning-bg text-warning",
} as const;

export function Badge({ tone = "info", className = "", ...rest }: { tone?: keyof typeof tones } & ComponentProps<"span">) {
  return (
    <span
      className={`inline-flex min-h-8 items-center justify-center rounded-2xl px-3 py-[7px] t-caption uppercase ${tones[tone]} ${className}`}
      {...rest}
    />
  );
}

// Coloured info block (caution, status, notice) with 16 px radius.
export function Notice({ tone = "warning", className = "", ...rest }: { tone?: keyof typeof tones } & ComponentProps<"div">) {
  return <div className={`rounded-2xl p-4 t-body ${tones[tone]} ${className}`} {...rest} />;
}

export function Divider() {
  return <hr className="h-px w-full border-0 bg-line" />;
}
