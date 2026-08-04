"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Country, SubscriptionPrice } from "@/lib/types";

interface MarketPricingRowProps {
  country: Country;
  lenderPrice?: SubscriptionPrice;
  proPrice?: SubscriptionPrice;
}

export function SubscriptionPricingManager({
  countries,
  initialPrices,
}: {
  countries: Country[];
  initialPrices: SubscriptionPrice[];
}) {
  const [search, setSearch] = useState("");
  const [pricesMap, setPricesMap] = useState<Record<string, { lender?: number; pro?: number }>>(() => {
    const map: Record<string, { lender?: number; pro?: number }> = {};
    for (const p of initialPrices) {
      if (!map[p.country_code]) map[p.country_code] = {};
      map[p.country_code][p.plan] = p.price_amount;
    }
    return map;
  });

  // Default fallbacks per country currency if not set in DB
  const defaultFallbackPrices: Record<string, { lender: number; pro: number }> = {
    UG: { lender: 19900, pro: 49900 },
    KE: { lender: 690, pro: 1790 },
    TZ: { lender: 12900, pro: 32900 },
    RW: { lender: 6500, pro: 16500 },
    BI: { lender: 15000, pro: 38000 },
    SS: { lender: 2500, pro: 6500 },
    CD: { lender: 14000, pro: 35000 },
    SO: { lender: 3000, pro: 7500 },
  };

  const filteredCountries = [...countries]
    .filter(
      (c) =>
        c.name.toLowerCase().includes(search.toLowerCase()) ||
        c.code.toLowerCase().includes(search.toLowerCase()) ||
        c.currency_code.toLowerCase().includes(search.toLowerCase())
    )
    .sort((a, b) => {
      if (a.is_active !== b.is_active) {
        return a.is_active ? -1 : 1;
      }
      return a.name.localeCompare(b.name);
    });

  return (
    <Card className="border-paper-300 shadow-sm">
      <CardHeader className="border-b border-paper-200 bg-paper-50/50 pb-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <CardTitle className="text-lg font-semibold text-ink-900">
              Subscription Fee & Pricing Control
            </CardTitle>
            <CardDescription className="text-xs text-ink-500 mt-1">
              Configure monthly Lender and Pro subscription pricing for every active currency market.
            </CardDescription>
          </div>
          <Input
            placeholder="Search currency or market..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full sm:w-60 h-9 text-xs"
          />
        </div>
      </CardHeader>
      <CardContent className="p-0 divide-y divide-paper-200">
        {filteredCountries.map((c) => {
          const currentLender =
            pricesMap[c.code]?.lender ??
            defaultFallbackPrices[c.code]?.lender ??
            19900;
          const currentPro =
            pricesMap[c.code]?.pro ??
            defaultFallbackPrices[c.code]?.pro ??
            49900;

          return (
            <MarketPricingRow
              key={c.code}
              country={c}
              initialLender={currentLender}
              initialPro={currentPro}
              onSaved={(plan, newPrice) => {
                setPricesMap((prev) => ({
                  ...prev,
                  [c.code]: {
                    ...prev[c.code],
                    [plan]: newPrice,
                  },
                }));
              }}
            />
          );
        })}

        {filteredCountries.length === 0 && (
          <div className="p-6 text-center text-sm text-ink-500">
            No matching markets or currencies found.
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function MarketPricingRow({
  country,
  initialLender,
  initialPro,
  onSaved,
}: {
  country: Country;
  initialLender: number;
  initialPro: number;
  onSaved: (plan: "lender" | "pro", price: number) => void;
}) {
  const router = useRouter();
  const [lenderDraft, setLenderDraft] = useState(initialLender.toString());
  const [proDraft, setProDraft] = useState(initialPro.toString());

  const [savingLender, setSavingLender] = useState(false);
  const [savingPro, setSavingPro] = useState(false);
  const [msg, setMsg] = useState<{ type: "success" | "error"; text: string } | null>(null);

  const isLenderDirty = parseFloat(lenderDraft) !== initialLender && !isNaN(parseFloat(lenderDraft));
  const isProDirty = parseFloat(proDraft) !== initialPro && !isNaN(parseFloat(proDraft));

  async function savePlan(plan: "lender" | "pro", amountStr: string, setSaving: (v: boolean) => void) {
    const amount = parseFloat(amountStr);
    if (isNaN(amount) || amount < 0) {
      setMsg({ type: "error", text: "Please enter a valid price." });
      return;
    }

    setSaving(true);
    setMsg(null);

    try {
      const res = await fetch("/api/admin/subscription-prices", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          country_code: country.code,
          currency_code: country.currency_code,
          plan,
          price_amount: amount,
        }),
      });

      const json = await res.json();
      if (!res.ok) throw new Error(json.error || "Failed to update price");

      onSaved(plan, amount);
      setMsg({ type: "success", text: `${country.currency_code} ${plan} price saved!` });
      router.refresh();
    } catch (err: any) {
      setMsg({ type: "error", text: err.message || "Error saving price" });
    } finally {
      setSaving(false);
    }
  }

  function formatCurrency(val: string) {
    const num = parseFloat(val);
    if (isNaN(num)) return `0 ${country.currency_code}`;
    return new Intl.NumberFormat("en-US").format(num) + ` ${country.currency_code}`;
  }

  return (
    <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-4 hover:bg-paper-50 transition-colors">
      <div className="min-w-44">
        <div className="flex items-center gap-2">
          <span className="font-semibold text-ink-900">{country.name}</span>
          <Badge variant={country.is_active ? "confirm" : "neutral"} className="text-[10px]">
            {country.is_active ? "Live Market" : "Inactive"}
          </Badge>
        </div>
        <p className="text-xs text-ink-500 mt-0.5">
          Currency: <span className="font-semibold text-ink-700">{country.currency_code}</span> ({country.code})
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 flex-1 max-w-2xl">
        {/* Lender Plan Price Box */}
        <div className="flex flex-col gap-1.5 p-3 rounded-lg border border-paper-200 bg-white">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-ink-700">Lender Plan / Mo</span>
            <span className="text-xs font-mono font-semibold text-amber-700">
              {formatCurrency(lenderDraft)}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Input
              type="number"
              min="0"
              value={lenderDraft}
              onChange={(e) => setLenderDraft(e.target.value)}
              className="h-8 text-xs font-tabular"
              placeholder="e.g. 19900"
            />
            <Button
              size="sm"
              disabled={!isLenderDirty || savingLender}
              onClick={() => savePlan("lender", lenderDraft, setSavingLender)}
              className="h-8 px-3 text-xs shrink-0"
            >
              {savingLender ? "…" : "Save"}
            </Button>
          </div>
        </div>

        {/* Pro Plan Price Box */}
        <div className="flex flex-col gap-1.5 p-3 rounded-lg border border-paper-200 bg-white">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-ink-700">Pro Plan / Mo</span>
            <span className="text-xs font-mono font-semibold text-amber-700">
              {formatCurrency(proDraft)}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Input
              type="number"
              min="0"
              value={proDraft}
              onChange={(e) => setProDraft(e.target.value)}
              className="h-8 text-xs font-tabular"
              placeholder="e.g. 49900"
            />
            <Button
              size="sm"
              disabled={!isProDirty || savingPro}
              onClick={() => savePlan("pro", proDraft, setSavingPro)}
              className="h-8 px-3 text-xs shrink-0"
            >
              {savingPro ? "…" : "Save"}
            </Button>
          </div>
        </div>
      </div>

      {msg && (
        <div className="md:w-36 text-right">
          <span
            className={`text-[11px] font-medium ${
              msg.type === "success" ? "text-emerald-600" : "text-rose-600"
            }`}
          >
            {msg.text}
          </span>
        </div>
      )}
    </div>
  );
}
