import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent } from "@/components/ui/card";
import { CountryToggles } from "@/components/country-toggles";

export const dynamic = "force-dynamic";

export default async function CountriesPage() {
  const supabase = await createClient();

  const { data: countries } = await supabase
    .from("countries")
    .select("code, name, currency_code, phone_prefix, is_active, forex_enabled")
    .order("code");

  return (
    <>
      <Header
        title="Markets"
        description="Lending and forex go live independently, per market — see README §Multi-Market Architecture"
      />
      <main className="flex-1 space-y-3 overflow-y-auto p-6">
        {countries?.map((c) => (
          <Card key={c.code}>
            <CardContent className="flex flex-wrap items-center justify-between gap-4 p-4">
              <div>
                <p className="font-medium text-ink-900">
                  {c.name} <span className="text-ink-500">({c.code})</span>
                </p>
                <p className="text-xs text-ink-500">
                  {c.currency_code} · {c.phone_prefix}
                </p>
              </div>
              <CountryToggles code={c.code} isActive={c.is_active} forexEnabled={c.forex_enabled} />
            </CardContent>
          </Card>
        ))}
      </main>
    </>
  );
}
