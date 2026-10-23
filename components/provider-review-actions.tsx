"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

type TargetType =
  | { type: "capability"; id: string }
  | { type: "company"; userId: string; categorySlug: string; documentType: string }
  | { type: "role"; id: string };

export function ProviderReviewActions({
  target,
  currentStatus,
}: {
  target: TargetType;
  currentStatus?: string;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<"approve" | "reject" | "expire" | null>(null);
  const [reason, setReason] = useState("");
  const [showReject, setShowReject] = useState(false);
  const [showExpiry, setShowExpiry] = useState(false);
  const [expiresAt, setExpiresAt] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const isApproved = currentStatus === "approved" || currentStatus === "verified";

  async function submit(decision: "approve" | "reject" | "expire") {
    if (decision === "reject" && !reason.trim()) {
      setError("Please provide a rejection reason.");
      return;
    }

    setLoading(decision);
    setError(null);

    let url = "";
    let body: Record<string, unknown> = {
      decision,
      rejection_reason: decision === "reject" ? reason.trim() : undefined,
    };

    if (target.type === "capability") {
      url = `/api/admin/verifications/capability/${target.id}`;
      if (decision === "approve" && expiresAt) {
        body.expires_at = new Date(expiresAt).toISOString();
      }
    } else if (target.type === "company") {
      url = `/api/admin/verifications/company`;
      body.user_id = target.userId;
      body.category_slug = target.categorySlug;
      body.document_type = target.documentType;
    } else if (target.type === "role") {
      url = `/api/admin/verifications/role/${target.id}`;
      if (decision === "approve" && expiresAt) {
        body.expires_at = new Date(expiresAt).toISOString();
      }
    }

    try {
      const res = await fetch(url, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });

      setLoading(null);
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError(data.error ?? "Operation failed.");
        return;
      }

      setShowReject(false);
      setShowExpiry(false);
      router.refresh();
    } catch (e: any) {
      setLoading(null);
      setError(e.message || "Network error");
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <Button
          size="sm"
          variant="confirm"
          disabled={!!loading || isApproved}
          onClick={() => submit("approve")}
        >
          {loading === "approve" ? "Approving…" : "Approve"}
        </Button>

        <Button
          size="sm"
          variant="destructive"
          disabled={!!loading || currentStatus === "rejected"}
          onClick={() => {
            if (!showReject) {
              setShowReject(true);
            } else {
              submit("reject");
            }
          }}
        >
          {loading === "reject" ? "Rejecting…" : showReject ? "Confirm Reject" : "Reject"}
        </Button>

        {target.type !== "company" && (
          <Button
            size="sm"
            variant="outline"
            disabled={!!loading || currentStatus === "expired"}
            onClick={() => submit("expire")}
          >
            {loading === "expire" ? "Expiring…" : "Mark Expired"}
          </Button>
        )}

        {target.type !== "company" && !showExpiry && (
          <button
            type="button"
            className="text-xs text-ink-500 hover:text-ink-800 underline ml-1"
            onClick={() => setShowExpiry(true)}
          >
            + Expiry
          </button>
        )}
      </div>

      {showReject && (
        <div className="flex items-center gap-2 pt-1">
          <Input
            placeholder="Rejection reason (shown to provider)"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="max-w-xs text-xs"
            autoFocus
          />
          <Button
            size="sm"
            variant="ghost"
            className="h-8 text-xs text-ink-500"
            onClick={() => setShowReject(false)}
          >
            Cancel
          </Button>
        </div>
      )}

      {showExpiry && (
        <div className="flex items-center gap-2 pt-1">
          <label className="text-xs text-ink-500">Expires on:</label>
          <Input
            type="date"
            value={expiresAt}
            onChange={(e) => setExpiresAt(e.target.value)}
            className="max-w-xs text-xs"
          />
          <Button
            size="sm"
            variant="ghost"
            className="h-8 text-xs text-ink-500"
            onClick={() => setShowExpiry(false)}
          >
            Clear
          </Button>
        </div>
      )}

      {error ? <p className="text-xs text-clay-alert">{error}</p> : null}
    </div>
  );
}
