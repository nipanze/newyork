"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { AccountStatus } from "@/lib/types";

const STATUS_OPTIONS: AccountStatus[] = ["active", "suspended", "pending_verification", "deactivated"];

export function AccountActions({
  userId,
  currentStatus,
  isAdmin,
}: {
  userId: string;
  currentStatus: AccountStatus;
  isAdmin: boolean;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function updateAccount(payload: { account_status?: AccountStatus; is_admin?: boolean }) {
    setLoading(true);
    setError(null);
    const res = await fetch(`/api/admin/users/${userId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    setLoading(false);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.error ?? "Update failed.");
      return;
    }
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <div>
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-ink-500">
          Account status
        </p>
        <div className="flex flex-wrap gap-2">
          {STATUS_OPTIONS.map((status) => (
            <Button
              key={status}
              size="sm"
              variant={status === currentStatus ? "default" : "outline"}
              disabled={loading || status === currentStatus}
              onClick={() => updateAccount({ account_status: status })}
            >
              {status.replace("_", " ")}
            </Button>
          ))}
        </div>
      </div>

      <div>
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-ink-500">Admin role</p>
        <Button
          size="sm"
          variant={isAdmin ? "destructive" : "confirm"}
          disabled={loading}
          onClick={() => updateAccount({ is_admin: !isAdmin })}
        >
          {isAdmin ? "Revoke admin access" : "Grant admin access"}
        </Button>
      </div>

      {error ? <p className="text-xs text-clay-alert">{error}</p> : null}
    </div>
  );
}
