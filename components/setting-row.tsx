"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export function SettingRow({
  id,
  settingKey,
  country,
  value,
  category,
}: {
  id: string;
  settingKey: string;
  country: string | null;
  value: string | null;
  category: string | null;
}) {
  const router = useRouter();
  const [draft, setDraft] = useState(value ?? "");
  const [saving, setSaving] = useState(false);

  const dirty = draft !== (value ?? "");

  async function save() {
    setSaving(true);
    await fetch(`/api/admin/settings/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ setting_value: draft }),
    });
    setSaving(false);
    router.refresh();
  }

  return (
    <div className="flex items-center justify-between gap-4 border-b border-paper-200 px-4 py-3 last:border-0">
      <div className="min-w-0">
        <p className="truncate font-medium text-ink-900">{settingKey}</p>
        <p className="text-xs text-ink-500">
          {country ? `Override — ${country}` : "Global default"}
          {category ? ` · ${category}` : ""}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        <Input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          className="w-40 font-tabular"
        />
        <Button size="sm" disabled={!dirty || saving} onClick={save}>
          {saving ? "Saving…" : "Save"}
        </Button>
      </div>
    </div>
  );
}
