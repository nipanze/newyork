import Link from "next/link";
import { cn } from "@/lib/utils";

const ITEMS = [
  { href: "/marketers", label: "Overview" },
  { href: "/marketers/users", label: "Marketers" },
  { href: "/marketers/referrals", label: "Referrals" },
  { href: "/marketers/rewards", label: "Rewards" },
  { href: "/marketers/payouts", label: "Payouts" },
  { href: "/marketers/campaigns", label: "Campaigns" },
  { href: "/marketers/risk", label: "Fraud/Risk" },
];

export function MarketerNav({ active }: { active: string }) {
  return (
    <div className="flex flex-wrap gap-2">
      {ITEMS.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          className={cn(
            "rounded-md border px-3 py-1.5 text-xs font-medium",
            active === item.href
              ? "border-ink-800 bg-ink-900 text-white"
              : "border-paper-300 bg-white text-ink-700 hover:bg-paper-100"
          )}
        >
          {item.label}
        </Link>
      ))}
    </div>
  );
}
