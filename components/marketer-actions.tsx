"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

type Action = {
  label: string;
  value: string;
  variant?: "default" | "outline" | "destructive" | "confirm";
  confirm?: string;
};

export function MarketerActions({
  endpoint,
  actions,
  bodyKey = "status",
}: {
  endpoint: string;
  actions: Action[];
  bodyKey?: string;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run(action: Action) {
    if (action.confirm && !window.confirm(action.confirm)) return;
    setLoading(action.value);
    setError(null);
    const res = await fetch(endpoint, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ [bodyKey]: action.value }),
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
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {actions.map((action) => (
          <Button
            key={action.value}
            size="sm"
            variant={action.variant ?? "outline"}
            disabled={loading !== null}
            onClick={() => run(action)}
          >
            {loading === action.value ? "Saving..." : action.label}
          </Button>
        ))}
      </div>
      {error ? <p className="text-xs text-clay-alert">{error}</p> : null}
    </div>
  );
}
