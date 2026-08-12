import { createAdminClient } from "@/lib/supabase/admin";
import type { AccountStatus, KycStatus, SubscriptionPlan } from "@/lib/types";

export type AccountSearchFilters = {
  q?: string;
  name?: string;
  phone?: string;
  email?: string;
  country?: string;
  accountStatus?: string;
  plan?: string;
  kycStatus?: string;
  admin?: string;
  joinedFrom?: string;
  joinedTo?: string;
  page: number;
  pageSize: number;
};

export type AdminAccountRow = {
  id: string;
  full_name: string | null;
  email: string | null;
  phone: string | null;
  country: string | null;
  account_status: AccountStatus;
  is_admin: boolean;
  created_at: string;
  plan: SubscriptionPlan;
  subscription_status: string | null;
  kyc_status: KycStatus | "not_submitted";
};

type AuthUserSummary = {
  id: string;
  email: string | null;
  last_sign_in_at: string | null;
};

const VALID_ACCOUNT_STATUSES = new Set(["active", "suspended", "pending_verification", "deactivated"]);
const VALID_PLANS = new Set(["free", "lender", "pro"]);
const VALID_KYC_STATUSES = new Set(["not_submitted", "pending", "approved", "rejected", "expired"]);

export async function searchAdminAccounts(filters: AccountSearchFilters) {
  const supabaseAdmin = createAdminClient();
  const authUsers = await listAllAuthUsers();
  const emailByUserId = new Map(authUsers.map((user) => [user.id, user.email]));

  const matchingEmailIds = getMatchingEmailIds(authUsers, [filters.q, filters.email]);
  if ((filters.email || looksLikeEmail(filters.q)) && matchingEmailIds.size === 0) {
    return { rows: [], total: 0 };
  }

  let allowedIds: Set<string> | null = matchingEmailIds.size ? matchingEmailIds : null;

  if (filters.plan && VALID_PLANS.has(filters.plan)) {
    const { data } = await supabaseAdmin
      .from("subscriptions")
      .select("user_id")
      .eq("status", "active")
      .eq("plan", filters.plan);
    allowedIds = intersectIds(allowedIds, new Set((data ?? []).map((row) => row.user_id)));
  }

  if (filters.kycStatus && VALID_KYC_STATUSES.has(filters.kycStatus)) {
    const { data } = await supabaseAdmin
      .from("kyc_verifications")
      .select("user_id")
      .eq("status", filters.kycStatus);
    const kycIds = new Set((data ?? []).map((row) => row.user_id));
    allowedIds =
      filters.kycStatus === "not_submitted"
        ? await getUsersWithoutKyc(supabaseAdmin, allowedIds)
        : intersectIds(allowedIds, kycIds);
  }

  if (allowedIds && allowedIds.size === 0) {
    return { rows: [], total: 0 };
  }

  let query = supabaseAdmin
    .from("profiles")
    .select("id, full_name, phone, country, account_status, is_admin, created_at", {
      count: "exact",
    })
    .order("created_at", { ascending: false });

  const textTerms = [looksLikeEmail(filters.q) ? undefined : filters.q, filters.name]
    .map((value) => value?.trim())
    .filter(Boolean) as string[];
  for (const term of textTerms) {
    const escaped = escapeIlike(term);
    query = query.or(`full_name.ilike.%${escaped}%,phone.ilike.%${escaped}%`);
  }

  if (filters.phone) query = query.ilike("phone", `%${escapeIlike(filters.phone)}%`);
  if (filters.country) query = query.eq("country", filters.country);
  if (filters.accountStatus && VALID_ACCOUNT_STATUSES.has(filters.accountStatus)) {
    query = query.eq("account_status", filters.accountStatus);
  }
  if (filters.admin === "yes") query = query.eq("is_admin", true);
  if (filters.admin === "no") query = query.eq("is_admin", false);
  if (filters.joinedFrom) query = query.gte("created_at", startOfDay(filters.joinedFrom));
  if (filters.joinedTo) query = query.lte("created_at", endOfDay(filters.joinedTo));
  if (allowedIds) query = query.in("id", [...allowedIds]);

  const from = (filters.page - 1) * filters.pageSize;
  const to = from + filters.pageSize - 1;
  const { data: profiles, count, error } = await query.range(from, to);
  if (error) throw error;

  const userIds = (profiles ?? []).map((profile) => profile.id);
  const [{ data: subscriptions }, { data: kycs }] = await Promise.all([
    userIds.length
      ? supabaseAdmin
          .from("subscriptions")
          .select("user_id, plan, status")
          .in("user_id", userIds)
          .eq("status", "active")
      : { data: [] },
    userIds.length
      ? supabaseAdmin
          .from("kyc_verifications")
          .select("user_id, status, submitted_at")
          .in("user_id", userIds)
          .order("submitted_at", { ascending: false })
      : { data: [] },
  ]);

  const subByUserId = new Map((subscriptions ?? []).map((sub) => [sub.user_id, sub]));
  const kycByUserId = new Map<string, { status: KycStatus }>();
  for (const kyc of kycs ?? []) {
    if (!kycByUserId.has(kyc.user_id)) kycByUserId.set(kyc.user_id, kyc);
  }

  const rows: AdminAccountRow[] = (profiles ?? []).map((profile) => {
    const sub = subByUserId.get(profile.id);
    const kyc = kycByUserId.get(profile.id);

    return {
      id: profile.id,
      full_name: profile.full_name,
      email: emailByUserId.get(profile.id) ?? null,
      phone: profile.phone,
      country: profile.country,
      account_status: profile.account_status,
      is_admin: profile.is_admin,
      created_at: profile.created_at,
      plan: (sub?.plan ?? "free") as SubscriptionPlan,
      subscription_status: sub?.status ?? null,
      kyc_status: kyc?.status ?? "not_submitted",
    };
  });

  return { rows, total: count ?? rows.length };
}

async function listAllAuthUsers() {
  const supabaseAdmin = createAdminClient();
  const users: AuthUserSummary[] = [];
  let page = 1;

  while (page <= 20) {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;

    const batch =
      data.users?.map((user) => ({
        id: user.id,
        email: user.email ?? null,
        last_sign_in_at: user.last_sign_in_at ?? null,
      })) ?? [];

    users.push(...batch);
    if (batch.length < 1000) break;
    page += 1;
  }

  return users;
}

function getMatchingEmailIds(users: AuthUserSummary[], terms: Array<string | undefined>) {
  const normalizedTerms = terms.map((term) => term?.trim().toLowerCase()).filter(Boolean) as string[];
  const emailTerms = normalizedTerms.filter((term) => term.includes("@"));
  if (!emailTerms.length) return new Set<string>();

  return new Set(
    users
      .filter((user) => {
        const email = user.email?.toLowerCase() ?? "";
        return emailTerms.some((term) => email.includes(term));
      })
      .map((user) => user.id)
  );
}

async function getUsersWithoutKyc(
  supabaseAdmin: ReturnType<typeof createAdminClient>,
  allowedIds: Set<string> | null
) {
  const [{ data: profiles }, { data: kycs }] = await Promise.all([
    supabaseAdmin.from("profiles").select("id"),
    supabaseAdmin.from("kyc_verifications").select("user_id"),
  ]);
  const kycIds = new Set((kycs ?? []).map((kyc) => kyc.user_id));
  const profileIds = (profiles ?? []).map((profile) => profile.id);
  return new Set(profileIds.filter((id) => !kycIds.has(id) && (!allowedIds || allowedIds.has(id))));
}

function intersectIds(left: Set<string> | null, right: Set<string>) {
  if (!left) return right;
  return new Set([...left].filter((id) => right.has(id)));
}

function looksLikeEmail(value?: string) {
  return Boolean(value?.includes("@"));
}

function escapeIlike(value: string) {
  return value.replaceAll("%", "\\%").replaceAll("_", "\\_").trim();
}

function startOfDay(date: string) {
  return `${date}T00:00:00.000Z`;
}

function endOfDay(date: string) {
  return `${date}T23:59:59.999Z`;
}
