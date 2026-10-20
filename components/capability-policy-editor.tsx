"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

export function CapabilityPolicyEditor({
  slug,
  currentPolicy,
  isActive,
}: {
  slug: string;
  currentPolicy: string;
  isActive: boolean;
}) {
  const router = useRouter();
  const [policy, setPolicy] = useState(currentPolicy);
  const [active, setActive] = useState(isActive);
  const [loading, setLoading] = useState(false);
  const [saved, setSaved] = useState(false);

  async function update(newPolicy: string, newActive: boolean) {
    setLoading(true);
    setSaved(false);
    try {
      const res = await fetch(`/api/admin/settings/capabilities/${slug}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          verification_policy: newPolicy,
          is_active: newActive,
        }),
      });
      setLoading(false);
      if (res.ok) {
        setPolicy(newPolicy);
        setActive(newActive);
        setSaved(true);
        setTimeout(() => setSaved(false), 2000);
        router.refresh();
      }
    } catch {
      setLoading(false);
    }
  }

  return (
    <div className="flex items-center gap-2">
      <select
        value={policy}
        disabled={loading}
        onChange={(e) => update(e.target.value, active)}
        className="rounded border border-paper-300 bg-white px-2 py-1 text-xs font-medium text-ink-900 focus:border-ink-800 focus:outline-none"
      >
        <option value="open">Open (No Proof)</option>
        <option value="optional_proof">Optional Proof</option>
        <option value="required_proof">Required Proof (Gate)</option>
      </select>

      <Button
        size="sm"
        variant={active ? "outline" : "destructive"}
        className="h-7 text-xs px-2"
        disabled={loading}
        onClick={() => update(policy, !active)}
      >
        {active ? "Active" : "Disabled"}
      </Button>

      {saved && <span className="text-[10px] text-teal-confirm font-medium">Saved</span>}
    </div>
  );
}

