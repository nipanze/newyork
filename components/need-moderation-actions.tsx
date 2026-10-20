"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

export function NeedModerationActions({
  needId,
  currentStatus,
}: {
  needId: string;
  currentStatus: string;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleAction(action: "cancel" | "reactivate") {
    if (action === "cancel" && !confirm("Are you sure you want to cancel/moderate this need request?")) {
      return;
    }

    setLoading(action);
    setError(null);

    try {
      const res = await fetch(`/api/admin/needs/${needId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action }),
      });

      setLoading(null);
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError(data.error ?? "Failed to update need request.");
        return;
      }

      router.refresh();
    } catch (e: any) {
      setLoading(null);
      setError(e.message || "Network error");
    }
  }

  return (
    <div className="flex items-center gap-2">
      {currentStatus === "active" ? (
        <Button
          size="sm"
          variant="destructive"
          disabled={!!loading}
          onClick={() => handleAction("cancel")}
        >
          {loading === "cancel" ? "Cancelling…" : "Cancel / Moderate Request"}
        </Button>
      ) : currentStatus === "cancelled" ? (
        <Button
          size="sm"
          variant="confirm"
          disabled={!!loading}
          onClick={() => handleAction("reactivate")}
        >
          {loading === "reactivate" ? "Reactivating…" : "Reactivate Request"}
        </Button>
      ) : null}

      {error ? <p className="text-xs text-clay-alert">{error}</p> : null}
    </div>
  );
}

