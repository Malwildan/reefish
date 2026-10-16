"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Suspense } from "react";

const NAV = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/area", label: "Area" },
  { href: "/area/riwayat", label: "Riwayat Keputusan" },
  { href: "/flags", label: "Flag Sistem" },
];

function NavLinks({ path }: { path: string | null }) {
  // the longest matching prefix wins, so /area/riwayat does not also light up /area
  const current = path
    ? NAV.filter((n) => path === n.href || path.startsWith(n.href + "/")).sort((a, b) => b.href.length - a.href.length)[0]?.href
    : undefined;
  return (
    <>
      {NAV.map((n) => {
        const active = n.href === current;
        return (
          <Link
            key={n.href}
            href={n.href}
            aria-current={active ? "page" : undefined}
            className={`flex min-h-11 items-center rounded-xl px-4 py-3 t-label ${active ? "bg-blue-700" : "hover:bg-blue-700/50"}`}
          >
            {n.label}
          </Link>
        );
      })}
    </>
  );
}

function ActiveNav() {
  return <NavLinks path={usePathname()} />;
}

export function Sidebar({ region }: { region: string }) {
  return (
    <aside className="w-[243px] shrink-0 bg-primary-pressed text-inverse">
      <div className="sticky top-0 flex h-screen flex-col justify-between p-5">
      <div className="flex flex-col gap-[43px]">
        <Link href="/dashboard" className="flex items-center gap-3 self-center">
          <Image src="/reefish-mark-inverse.svg" alt="" width={46} height={40} priority />
          <span className="w-[130px] t-title-m">Reefish</span>
        </Link>
        <nav className="flex flex-col gap-4" aria-label="Menu admin">
          <p className="t-caption text-blue-100">ADMIN KAWASAN</p>
          {/* the pathname is request data; the plain links render first and the highlight streams in */}
          <Suspense fallback={<NavLinks path={null} />}>
            <ActiveNav />
          </Suspense>
        </nav>
      </div>
      <p className="t-body text-blue-100">{region}</p>
      </div>
    </aside>
  );
}
