import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/supabase/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(request: Request) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const { searchParams } = new URL(request.url);
  const countryCode = searchParams.get("country");

  const supabaseAdmin = createAdminClient();
  let query = supabaseAdmin
    .from("subscription_prices")
    .select("id, country_code, currency_code, plan, price_amount, price_minor_units, updated_at")
    .order("country_code")
    .order("plan");

  if (countryCode) {
    query = query.eq("country_code", countryCode.toUpperCase());
  }

  const { data, error } = await query;
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ data });
}

export async function PATCH(request: Request) {
  const admin = await requireAdmin();
  if ("error" in admin) return admin.error;

  const body = await request.json().catch(() => ({}));
  const { country_code, currency_code, plan, price_amount } = body as {
    country_code?: string;
    currency_code?: string;
    plan?: "lender" | "pro";
    price_amount?: number;
  };

  if (!country_code || !plan || price_amount === undefined || price_amount < 0) {
    return NextResponse.json(
      { error: "country_code, plan ('lender' | 'pro'), and non-negative price_amount are required." },
      { status: 400 }
    );
  }

  const uppercaseCountry = country_code.toUpperCase();
  const supabaseAdmin = createAdminClient();

  // Fetch currency_code if not supplied
  let finalCurrencyCode = currency_code;
  if (!finalCurrencyCode) {
    const { data: countryData } = await supabaseAdmin
      .from("countries")
      .select("currency_code")
      .eq("code", uppercaseCountry)
      .single();
    finalCurrencyCode = countryData?.currency_code ?? "UGX";
  }

  const numericAmount = Number(price_amount);
  const priceMinorUnits = Math.round(numericAmount); // integer minor units for EAC currencies

  const payload = {
    country_code: uppercaseCountry,
    currency_code: finalCurrencyCode,
    plan,
    price_amount: numericAmount,
    price_minor_units: priceMinorUnits,
    updated_at: new Date().toISOString(),
  };

  const { data, error } = await supabaseAdmin
    .from("subscription_prices")
    .upsert(payload, { onConflict: "country_code,plan" })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabaseAdmin.from("audit_logs").insert({
    user_id: admin.user.id,
    event_type: "admin_action",
    entity_type: "subscription_prices",
    entity_id: data.id,
    action: `dashboard_update_subscription_price:${uppercaseCountry}:${plan}`,
    new_values: payload,
  });

  return NextResponse.json({ ok: true, data });
}
