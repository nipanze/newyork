import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent } from "@/components/ui/card";
import { CountryToggles } from "@/components/country-toggles";
import { SubscriptionPricingManager } from "@/components/subscription-pricing-manager";

export const dynamic = "force-dynamic";

export default async function CountriesPage() {
  const supabase = await createClient();

  const [{ data: countries }, { data: prices }] = await Promise.all([
    supabase
      .from("countries")
      .select("code, name, currency_code, phone_prefix, is_active, forex_enabled")
      .order("code"),
    supabase
      .from("subscription_prices")
      .select("id, country_code, currency_code, plan, price_amount, price_minor_units, updated_at"),
  ]);

  return (
    <>
      <Header
        title="Markets & Subscription Pricing"
        description="Lending and forex live status per market, and subscription fee control per currency."
      />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <SubscriptionPricingManager
          countries={countries ?? []}
          initialPrices={prices ?? []}
        />

        <div className="space-y-3">
          <h2 className="text-sm font-semibold text-ink-900 tracking-tight">Market Live Status</h2>
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
        </div>
      </main>
    </>
  );
}
