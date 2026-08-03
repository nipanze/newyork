"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function KycReviewActions({ kycId }: { kycId: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState<"approve" | "reject" | null>(null);
  const [reason, setReason] = useState("");
  const [showReject, setShowReject] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(decision: "approve" | "reject") {
    setLoading(decision);
    setError(null);
    const res = await fetch(`/api/admin/kyc/${kycId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        decision,
        rejection_reason: decision === "reject" ? reason : undefined,
      }),
    });
    setLoading(null);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.error ?? "Update failed.");
      return;
    }
    router.refresh();
  }

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <Button size="sm" variant="confirm" disabled={!!loading} onClick={() => submit("approve")}>
          {loading === "approve" ? "Approving…" : "Approve"}
        </Button>
        <Button
          size="sm"
          variant="destructive"
          disabled={!!loading}
          onClick={() => (showReject ? submit("reject") : setShowReject(true))}
        >
          {loading === "reject" ? "Rejecting…" : showReject ? "Confirm reject" : "Reject"}
        </Button>
      </div>
      {showReject && (
        <Input
          placeholder="Rejection reason (shown to the user)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className="max-w-xs"
        />
      )}
      {error ? <p className="text-xs text-clay-alert">{error}</p> : null}
    </div>
  );
}
