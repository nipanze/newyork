"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Users,
  HandCoins,
  ArrowLeftRight,
  ShieldCheck,
  Receipt,
  ScrollText,
  Globe2,
  SlidersHorizontal,
  Megaphone,
} from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/dashboard", label: "Overview", icon: LayoutDashboard },
  { href: "/users", label: "Accounts", icon: Users },
  { href: "/loans", label: "Loans", icon: HandCoins },
  { href: "/forex", label: "Forex", icon: ArrowLeftRight },
  { href: "/marketers", label: "Marketers", icon: Megaphone },
  { href: "/kyc", label: "KYC review", icon: ShieldCheck },
  { href: "/transactions", label: "Transactions", icon: Receipt },
  { href: "/audit-logs", label: "Audit log", icon: ScrollText },
  { href: "/countries", label: "Markets", icon: Globe2 },
  { href: "/settings", label: "Settings", icon: SlidersHorizontal },
];

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="hidden w-60 shrink-0 flex-col border-r border-ink-800 bg-ink-950 text-paper-100 md:flex">
      <div className="flex h-16 items-center gap-2 border-b border-ink-800 px-5">
        <div className="flex h-7 w-7 items-center justify-center rounded-md bg-amber-signal text-sm font-bold text-ink-950">
          N
        </div>
        <div>
          <p className="text-sm font-semibold leading-none">newyork</p>
          <p className="text-[10px] uppercase tracking-wider text-ink-500">Control dashboard</p>
        </div>
      </div>

      <nav className="flex-1 space-y-0.5 overflow-y-auto px-3 py-4">
        {NAV_ITEMS.map((item) => {
          const active = pathname === item.href || pathname.startsWith(item.href + "/");
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors",
                active
                  ? "bg-ink-800 text-white"
                  : "text-ink-500 hover:bg-ink-900 hover:text-paper-100"
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="border-t border-ink-800 px-5 py-3 text-[11px] text-ink-500">
        Non-custodial marketplace — this console never moves user funds.
      </div>
    </aside>
  );
}
