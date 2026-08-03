import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { SettingRow } from "@/components/setting-row";

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
