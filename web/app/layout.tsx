import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Memory App",
  description: "Card management for the Minimal English Memory App"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <div className="shell">
          <aside className="sidebar">
            <div className="brand">
              <span className="brandMark">M</span>
              <div>
                <strong>Memory</strong>
                <span>Card admin</span>
              </div>
            </div>
            <nav>
              <Link href="/cards">Cards</Link>
              <Link href="/cards/new">New Card</Link>
              <Link href="/subjects">Subjects</Link>
            </nav>
          </aside>
          <main className="main">{children}</main>
        </div>
      </body>
    </html>
  );
}
