import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const country = searchParams.get("country")?.toUpperCase();
  const currency = searchParams.get("currency")?.toUpperCase();

  const supabase = await createClient();
  let query = supabase
    .from("subscription_prices")
    .select("country_code, currency_code, plan, price_amount, price_minor_units, updated_at")
    .order("country_code")
    .order("plan");

  if (country) {
    query = query.eq("country_code", country);
  } else if (currency) {
    query = query.eq("currency_code", currency);
  }

  const { data, error } = await query;
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ prices: data ?? [] });
}
