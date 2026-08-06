"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AuthButton } from "@/components/AuthButton";

const LINKS = [
  { href: "/markets", label: "Markets" },
  { href: "/positions", label: "Positions" },
  { href: "/watchlist", label: "Watchlist" },
  { href: "/settings", label: "Settings" },
] as const;

function isActive(pathname: string, href: string): boolean {
  if (href === "/markets") {
    return (
      pathname === "/markets" ||
      pathname.startsWith("/event/") ||
      pathname.startsWith("/search")
    );
  }
  if (href === "/positions") {
    return pathname === "/positions" || pathname === "/portfolio";
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function AppNav() {
  const pathname = usePathname() || "/";

  return (
    <div className="masthead__row">
      <a href="/markets" className="wordmark" aria-label="Peak markets">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className="wordmark__mark"
          src="/peak-mark.png"
          width={28}
          height={28}
          alt=""
          decoding="async"
        />
        <span className="wordmark__name">Peak</span>
      </a>
      <nav className="masthead__nav" aria-label="Primary">
        {LINKS.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className={isActive(pathname, link.href) ? "is-active" : undefined}
          >
            {link.label}
          </Link>
        ))}
      </nav>
      <div className="masthead__end">
        <AuthButton />
      </div>
    </div>
  );
}
