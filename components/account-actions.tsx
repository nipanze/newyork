"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { AccountStatus, SubscriptionPlan } from "@/lib/types";

const STATUS_OPTIONS: AccountStatus[] = ["active", "suspended", "pending_verification", "deactivated"];
const PLAN_OPTIONS: SubscriptionPlan[] = ["free", "lender", "pro"];

export function AccountActions({
  userId,
  currentStatus,
  currentPlan,
  isAdmin,
}: {
  userId: string;
  currentStatus: AccountStatus;
  currentPlan: SubscriptionPlan;
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

  async function updatePlan(newPlan: SubscriptionPlan) {
    setLoading(true);
    setError(null);
    const res = await fetch(`/api/admin/users/${userId}/plan`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ plan: newPlan }),
    });
    setLoading(false);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.error ?? "Plan update failed.");
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
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-ink-500">
          Subscription plan
        </p>
        <div className="flex flex-wrap gap-2">
          {PLAN_OPTIONS.map((plan) => (
            <Button
              key={plan}
              size="sm"
              variant={plan === currentPlan ? "default" : "outline"}
              disabled={loading || plan === currentPlan}
              onClick={() => updatePlan(plan)}
            >
              {plan}
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

