"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

type ModerationAction = "cancel" | "mark_review" | "restore";

const ACTIONS: { action: ModerationAction; label: string; variant: "destructive" | "signal" | "outline" }[] = [
  { action: "cancel", label: "Cancel request", variant: "destructive" },
  { action: "mark_review", label: "Flag for review", variant: "signal" },
  { action: "restore", label: "Restore / clear flag", variant: "outline" },
];

export function ForexModerationActions({
  requestId,
  currentStatus,
}: {
  requestId: string;
  currentStatus: string;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<ModerationAction | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function moderate(action: ModerationAction) {
    setLoading(action);
    setError(null);
    const res = await fetch(`/api/admin/forex/${requestId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action }),
    });
    setLoading(null);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.error ?? "Action failed.");
      return;
    }
    router.refresh();
  }

  const isCancelled = currentStatus === "cancelled";

  return (
    <div className="space-y-3">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-500">
        Moderation controls
      </p>
      <div className="flex flex-wrap gap-2">
        {ACTIONS.map(({ action, label, variant }) => {
          if (action === "cancel" && isCancelled) return null;
          if (action === "restore" && !isCancelled) return null;
          return (
            <Button
              key={action}
              size="sm"
              variant={variant as any}
              disabled={!!loading}
              onClick={() => moderate(action)}
            >
              {loading === action ? "Processing…" : label}
            </Button>
          );
        })}
      </div>
      <p className="text-xs text-ink-500">
        These actions are non-financial — they only control listing visibility. All moderation
        events are written to the audit log.
      </p>
      {error && <p className="text-xs text-clay-alert">{error}</p>}
    </div>
  );
}
