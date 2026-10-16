import type { ComponentProps, ReactNode } from "react";

// Figma "Decision type / reason" boxes: caption label over a semibold value, subtle fill, 14 px radius.
const box =
  "flex min-h-[59px] flex-col gap-[3px] rounded-[14px] border border-line bg-subtle px-[14px] py-2 " +
  "focus-within:border-primary focus-within:ring-2 focus-within:ring-primary/20";
const valueClass = "w-full bg-transparent t-label text-ink outline-none placeholder:font-normal placeholder:text-ink-2";

type Base = { label: string; error?: string; className?: string };

function Shell({ label, error, className = "", children, htmlFor }: Base & { children: ReactNode; htmlFor?: string }) {
  return (
    <div className={className}>
      <label htmlFor={htmlFor} className={box}>
        <span className="t-caption uppercase text-ink-2">{label}</span>
        {children}
      </label>
      {error && <p className="mt-1 t-caption text-error">{error}</p>}
    </div>
  );
}

export function Field({ label, error, className, id, ...rest }: Base & ComponentProps<"input">) {
  return (
    <Shell label={label} error={error} className={className} htmlFor={id}>
      <input id={id} aria-invalid={!!error} className={valueClass} {...rest} />
    </Shell>
  );
}

export function TextAreaField({ label, error, className, id, ...rest }: Base & ComponentProps<"textarea">) {
  return (
    <Shell label={label} error={error} className={className} htmlFor={id}>
      <textarea id={id} aria-invalid={!!error} rows={2} className={`${valueClass} resize-none`} {...rest} />
    </Shell>
  );
}

export function SelectField({ label, error, className, id, children, ...rest }: Base & ComponentProps<"select">) {
  return (
    <Shell label={label} error={error} className={className} htmlFor={id}>
      <select id={id} className={`${valueClass} -ml-1 cursor-pointer`} {...rest}>
        {children}
      </select>
    </Shell>
  );
}

// Read-only version of the same box (detail pages).
export function InfoBox({ label, children, className = "" }: { label: string; children: ReactNode; className?: string }) {
  return (
    <div className={`${box} ${className}`}>
      <span className="t-caption uppercase text-ink-2">{label}</span>
      <span className="t-label text-ink">{children}</span>
    </div>
  );
}
