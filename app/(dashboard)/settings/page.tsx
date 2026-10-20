import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { SettingRow } from "@/components/setting-row";
import { ShieldCheck, ArrowRight } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const supabase = await createClient();

  const { data: settings } = await supabase
    .from("system_settings")
    .select("setting_id, setting_key, country, setting_value, category")
    .order("category")
    .order("setting_key");

  const grouped = new Map<string, typeof settings>();
  for (const s of settings ?? []) {
    const key = s.category ?? "general";
    grouped.set(key, [...(grouped.get(key) ?? []), s]);
  }

  return (
    <>
      <Header title="Settings" description="Global defaults and per-market overrides (system_settings)" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <Link href="/settings/capabilities" className="block">
          <Card className="hover:border-ink-400 transition-colors bg-white border-l-4 border-l-amber-signal">
            <CardContent className="flex items-center justify-between p-4">
              <div className="flex items-center gap-3">
                <div className="rounded-md bg-amber-signal-soft p-2 text-ink-900">
                  <ShieldCheck className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold text-ink-900">Capability Policies & Verification Matrix</h3>
                  <p className="text-xs text-ink-500">Configure proof policies (Open, Optional, Required) and document rules for individuals and companies.</p>
                </div>
              </div>
              <ArrowRight className="h-4 w-4 text-ink-400" />
            </CardContent>
          </Card>
        </Link>
        {[...grouped.entries()].map(([category, rows]) => (
          <Card key={category}>
            <CardHeader>
              <CardTitle className="capitalize">{category}</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {rows?.map((row) => (
                <SettingRow
                  key={row.setting_id}
                  id={row.setting_id}
                  settingKey={row.setting_key}
                  country={row.country}
                  value={row.setting_value}
                  category={row.category}
                />
              ))}
            </CardContent>
          </Card>
        ))}
        {!settings?.length && (
          <p className="text-sm text-ink-500">No system settings found.</p>
        )}
      </main>
    </>
  );
}
