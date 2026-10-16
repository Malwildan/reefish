import type { Metadata } from "next";
import localFont from "next/font/local";
import { Providers } from "./providers";
import "./globals.css";

// Same DM Sans file as the Flutter app (frontend/mobile/assets/fonts), so the build needs no Google Fonts fetch.
const dmSans = localFont({
  src: "./fonts/DM-Sans-Variable.ttf",
  variable: "--font-dm-sans",
  weight: "100 1000",
});

export const metadata: Metadata = {
  title: "Reefish · Admin Kawasan",
  description: "Kelola keputusan kawasan dan pantau aktivitas nelayan di sekitar terumbu karang.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="id" className={dmSans.variable}>
      <body className="antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
