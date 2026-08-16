import { createAdminClient } from "@/lib/supabase/admin";
import type { DashboardSearchParams } from "@/lib/dashboard-filters";
import { getParam } from "@/lib/dashboard-filters";

export const MARKETER_STATUS_OPTIONS = ["new", "active", "suspended", "deactivated", "under_review"] as const;
export const REFERRAL_STATUS_OPTIONS = ["clicked", "registered", "verified", "qualified", "rejected", "fraud_hold"] as const;
export const REWARD_STATUS_OPTIONS = ["pending", "approved", "rejected", "paid", "cancelled", "fraud_hold"] as const;
export const PAYOUT_STATUS_OPTIONS = ["requested", "under_review", "approved", "processing", "paid", "failed", "cancelled"] as const;
export const CAMPAIGN_STATUS_OPTIONS = ["draft", "active", "paused", "ended", "deactivated"] as const;

export type SelectOption = { label: string; value: string };

export async function getCountryOptions() {
  const supabase = createAdminClient();
  const { data } = await supabase.from("countries").select("code, name").order("code");
  return [
    { label: "All countries", value: "" },
    ...((data ?? []).map((c) => ({ label: `${c.name} (${c.code})`, value: c.code })) ?? []),
  ];
}

export async function getCampaignOptions() {
  const supabase = createAdminClient();
  const { data, error } = await supabase.from("referral_campaigns").select("id, name").order("name");
  if (error) return { missing: isMissingRelation(error), options: [{ label: "All campaigns", value: "" }] };
  return {
    missing: false,
    options: [{ label: "All campaigns", value: "" }, ...((data ?? []).map((c) => ({ label: c.name, value: c.id })) ?? [])],
  };
}

export function statusOptions(values: readonly string[], allLabel: string): SelectOption[] {
  return [{ label: allLabel, value: "" }, ...values.map((value) => ({ label: titleize(value), value }))];
}

export function titleize(value: string) {
  return value.replaceAll("_", " ").replace(/\b\w/g, (match) => match.toUpperCase());
}

export function getDateRange(params: DashboardSearchParams) {
  return { from: getParam(params, "from"), to: getParam(params, "to") };
}

export function applyDateRange<T extends any>(query: T, column: string, from?: string, to?: string) {
  let scoped = query as any;
  if (from) scoped = scoped.gte(column, `${from}T00:00:00.000Z`);
  if (to) scoped = scoped.lte(column, `${to}T23:59:59.999Z`);
  return scoped as T;
}

export function isMissingRelation(error: { code?: string; message?: string } | null | undefined) {
  if (!error) return false;
  return error.code === "42P01" || error.code === "PGRST205" || /relation .* does not exist/i.test(error.message ?? "");
}

export function migrationMessage() {
  return "Apply sql/patch_marketer_department.sql to enable the Marketer / Referral Department.";
}

export async function getProfileSummaries(ids: string[]) {
  const uniqueIds = [...new Set(ids.filter(Boolean))];
  if (!uniqueIds.length) return new Map<string, any>();
  const supabase = createAdminClient();
  const { data } = await supabase
    .from("profiles")
    .select("id, full_name, phone, country, account_status, is_admin")
    .in("id", uniqueIds);
  const emailById = await getAuthEmails(uniqueIds);
  return new Map(
    (data ?? []).map((profile) => [
      profile.id,
      {
        ...profile,
        email: emailById.get(profile.id) ?? null,
      },
    ])
  );
}

export async function getAuthEmails(ids: string[]) {
  const supabase = createAdminClient();
  const emailById = new Map<string, string | null>();
  await Promise.all(
    [...new Set(ids.filter(Boolean))].map(async (id) => {
      const { data } = await supabase.auth.admin.getUserById(id);
      emailById.set(id, data.user?.email ?? null);
    })
  );
  return emailById;
}

export async function getMatchingProfileIds(term: string) {
  const value = term.trim();
  if (!value) return null;

  const supabase = createAdminClient();
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id")
    .or(`full_name.ilike.%${escapeIlike(value)}%,phone.ilike.%${escapeIlike(value)}%`);

  const matched = new Set((profiles ?? []).map((p) => p.id));
  if (value.includes("@")) {
    let page = 1;
    while (page <= 20) {
      const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) break;
      for (const user of data.users ?? []) {
        if (user.email?.toLowerCase().includes(value.toLowerCase())) matched.add(user.id);
      }
      if ((data.users ?? []).length < 1000) break;
      page += 1;
    }
  }

  return matched;
}

export function escapeIlike(value: string) {
  return value.replaceAll("%", "\\%").replaceAll("_", "\\_").trim();
}

export function asVariant(status: string): "confirm" | "signal" | "alert" | "neutral" {
  if (["active", "approved", "paid", "qualified", "verified", "clear"].includes(status)) return "confirm";
  if (["pending", "requested", "under_review", "processing", "review", "new", "draft"].includes(status)) return "signal";
  if (["suspended", "deactivated", "rejected", "failed", "fraud_hold", "flagged", "cancelled"].includes(status)) return "alert";
  return "neutral";
}

export function safeNumber(value: number | null | undefined) {
  return Number(value ?? 0);
}
