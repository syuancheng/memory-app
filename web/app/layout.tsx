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
        <div className="appShell">
          <header className="topbar">
            <div className="brand">
              <Link className="brandMark" href="/cards">
                M
              </Link>
              <div>
                <strong>Memory</strong>
                <span>Study sets</span>
              </div>
            </div>
            <nav className="topnav" aria-label="Primary navigation">
              <Link href="/cards">Library</Link>
              <Link href="/subjects">Subjects</Link>
            </nav>
            <div className="topbarActions">
              <Link className="ghostButton" href="/cards">
                Search sets
              </Link>
              <Link className="primaryButton" href="/cards/new">
                Create
              </Link>
            </div>
          </header>
          <main className="main">{children}</main>
        </div>
      </body>
    </html>
  );
}
