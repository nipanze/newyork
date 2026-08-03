import { cn } from "@/lib/utils";
import { Card, CardContent } from "@/components/ui/card";
import type { LucideIcon } from "lucide-react";

export function StatCard({
  label,
  value,
  icon: Icon,
  tone = "neutral",
  hint,
}: {
  label: string;
  value: string | number;
  icon?: LucideIcon;
  tone?: "neutral" | "signal" | "confirm" | "alert";
  hint?: string;
}) {
  const toneClasses = {
    neutral: "text-ink-900",
    signal: "text-[#8a5a1a]",
    confirm: "text-teal-confirm",
    alert: "text-clay-alert",
  } as const;

  return (
    <Card>
      <CardContent className="flex items-start justify-between gap-3 p-5">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-ink-500">{label}</p>
          <p className={cn("mt-1 font-tabular text-2xl font-semibold", toneClasses[tone])}>{value}</p>
          {hint ? <p className="mt-1 text-xs text-ink-500">{hint}</p> : null}
        </div>
        {Icon ? (
          <div className="rounded-md bg-paper-100 p-2">
            <Icon className="h-4 w-4 text-ink-700" />
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
