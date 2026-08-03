import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium",
  {
    variants: {
      variant: {
        neutral: "border-paper-300 bg-paper-100 text-ink-700",
        confirm: "border-transparent bg-teal-confirm-soft text-teal-confirm",
        signal: "border-transparent bg-amber-signal-soft text-[#8a5a1a]",
        alert: "border-transparent bg-clay-alert-soft text-clay-alert",
        outline: "border-ink-700 text-ink-700 bg-transparent",
      },
    },
    defaultVariants: {
      variant: "neutral",
    },
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />;
}

export { Badge, badgeVariants };
