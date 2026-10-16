import Link from "next/link";
import type { ComponentProps } from "react";

// Pill buttons from the Figma admin frames: 48 px tall, radius 24, drop shadow.
const variants = {
  primary: "bg-primary text-inverse hover:bg-primary-pressed",
  secondary: "bg-secondary text-on-secondary hover:brightness-95",
  danger: "bg-error-bg text-error hover:brightness-95",
  warm: "bg-error-bg text-warm-ink border border-warm hover:brightness-95",
  success: "bg-success-bg text-success",
} as const;

export type ButtonVariant = keyof typeof variants;

export function buttonClass(variant: ButtonVariant = "primary", extra = "") {
  return [
    "inline-flex min-h-12 items-center justify-center rounded-3xl px-4 py-[13px] text-center t-label",
    "drop-shadow-[0px_4px_2px_rgba(0,0,0,0.28)] transition disabled:cursor-not-allowed disabled:opacity-60",
    "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
    variants[variant],
    extra,
  ].join(" ");
}

type Common = { variant?: ButtonVariant; className?: string };

export function Button({ variant, className, ...rest }: Common & ComponentProps<"button">) {
  return <button type="button" className={buttonClass(variant, className)} {...rest} />;
}

export function ButtonLink({ variant, className, ...rest }: Common & ComponentProps<typeof Link>) {
  return <Link className={buttonClass(variant, className)} {...rest} />;
}
