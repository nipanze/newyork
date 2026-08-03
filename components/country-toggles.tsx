"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

export function CountryToggles({
  code,
  isActive,
  forexEnabled,
}: {
  code: string;
  isActive: boolean;
  forexEnabled?: boolean;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<"lending" | "forex" | null>(null);

  async function toggle(field: "is_active" | "forex_enabled", current: boolean | undefined, kind: "lending" | "forex") {
    setLoading(kind);
    await fetch(`/api/admin/countries/${code}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ [field]: !current }),
    });
    setLoading(null);
    router.refresh();
  }

  return (
    <div className="flex gap-2">
      <Button
        size="sm"
        variant={isActive ? "confirm" : "outline"}
        disabled={loading !== null}
        onClick={() => toggle("is_active", isActive, "lending")}
      >
        {loading === "lending" ? "…" : isActive ? "Lending live" : "Activate lending"}
      </Button>
      <Button
        size="sm"
        variant={forexEnabled ? "confirm" : "outline"}
        disabled={loading !== null}
        onClick={() => toggle("forex_enabled", forexEnabled, "forex")}
      >
        {loading === "forex" ? "…" : forexEnabled ? "Forex live" : "Activate forex"}
      </Button>
    </div>
  );
}
