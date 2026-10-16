export default function Loading() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true" aria-live="polite">
      <div className="h-[18px] w-[180px] animate-pulse rounded bg-line" />
      <div className="h-8 w-[320px] animate-pulse rounded bg-line" />
      <div className="h-[430px] animate-pulse rounded-[20px] bg-surface" />
      <span className="sr-only">Memuat…</span>
    </div>
  );
}
