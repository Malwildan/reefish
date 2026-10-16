"use client";

import { useEffect, useRef, type ReactNode } from "react";

// Native <dialog>: focus trap, Esc to close and the scrim come from the browser.
export function Dialog({ open, onClose, title, children }: { open: boolean; onClose: () => void; title: string; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      aria-label={title}
      className="m-auto w-[560px] max-w-[calc(100vw-32px)] rounded-[20px] bg-surface p-7 text-ink backdrop:bg-black/30"
    >
      <div className="flex flex-col gap-5">
        <h2 className="t-title-m">{title}</h2>
        {children}
      </div>
    </dialog>
  );
}
