"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

type ModerationAction = "cancel" | "mark_review" | "restore";

export function LoanModerationActions({
  loanId,
  currentStatus,
}: {
  loanId: string;
  currentStatus: string;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<ModerationAction | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function moderate(action: ModerationAction) {
    if (action === "cancel" && !confirm("Are you sure you want to cancel this loan listing?")) {
      return;
    }
    if (action === "restore" && !confirm("Restore this loan listing back to active status?")) {
      return;
    }

    setLoading(action);
    setError(null);
    try {
      const res = await fetch(`/api/admin/loans/${loanId}`, {
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
    } catch (e: any) {
      setLoading(null);
      setError(e.message || "Network error");
    }
  }

  const isCancelled = currentStatus === "cancelled";

  return (
    <div className="space-y-3">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-500">
        Moderation controls
      </p>
      <div className="flex flex-wrap gap-2">
        {isCancelled ? (
          <Button
            size="sm"
            variant="confirm"
            disabled={!!loading}
            onClick={() => moderate("restore")}
          >
            {loading === "restore" ? "Restoring…" : "Restore listing to active"}
          </Button>
        ) : (
          <>
            <Button
              size="sm"
              variant="destructive"
              disabled={!!loading}
              onClick={() => moderate("cancel")}
            >
              {loading === "cancel" ? "Cancelling…" : "Cancel listing"}
            </Button>
            <Button
              size="sm"
              variant="signal"
              disabled={!!loading}
              onClick={() => moderate("mark_review")}
            >
              {loading === "mark_review" ? "Flagging…" : "Flag for review"}
            </Button>
          </>
        )}
      </div>
      <p className="text-xs text-ink-500">
        These actions are non-financial — they only control listing visibility. All moderation
        events are written to the audit log.
      </p>
      {error && <p className="text-xs text-clay-alert">{error}</p>}
    </div>
  );
}
