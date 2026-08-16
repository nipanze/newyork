import Link from "next/link";
import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { MarketerNav } from "@/components/marketer-nav";
import { Pagination } from "@/components/pagination";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createAdminClient } from "@/lib/supabase/admin";
import { getPage, getPageSize, getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import { REFERRAL_STATUS_OPTIONS, asVariant, getCampaignOptions, getCountryOptions, getProfileSummaries, isMissingRelation, migrationMessage, statusOptions } from "@/lib/admin/marketers";
import { formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function ReferralsPage({ searchParams }: { searchParams: Promise<DashboardSearchParams> }) {
  const params = await searchParams;
  const supabase = createAdminClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);
  const country = getParam(params, "country");
  const campaign = getParam(params, "campaign");
  const status = getParam(params, "status");
  const fromQ = getParam(params, "from");
  const toQ = getParam(params, "to");
  const [countryOptions, campaigns] = await Promise.all([getCountryOptions(), getCampaignOptions()]);

  let query = supabase
    .from("referrals")
    .select("id, referrer_id, referred_user_id, referred_email, code, campaign_id, source, country, status, qualifying_event, qualified_at, fraud_status, created_at", { count: "exact" })
    .order("created_at", { ascending: false });
  if (country) query = query.eq("country", country);
  if (campaign) query = query.eq("campaign_id", campaign);
  if (status) query = query.eq("status", status);
  if (fromQ) query = query.gte("created_at", `${fromQ}T00:00:00.000Z`);
  if (toQ) query = query.lte("created_at", `${toQ}T23:59:59.999Z`);
  const from = (page - 1) * pageSize;
  const { data, count, error } = await query.range(from, from + pageSize - 1);

  const profiles = await getProfileSummaries([...(data ?? []).map((r) => r.referrer_id), ...(data ?? []).map((r) => r.referred_user_id).filter(Boolean) as string[]]);

  return (
    <>
      <Header title="Referrals" description="Attribution, registration, qualification, and review history" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/referrals" />
        <AdminFilterForm resetHref="/marketers/referrals" searchParams={params} fields={[
          { name: "country", label: "Country", type: "select", options: countryOptions },
          { name: "campaign", label: "Campaign", type: "select", options: campaigns.options },
          { name: "status", label: "Status", type: "select", options: statusOptions(REFERRAL_STATUS_OPTIONS, "All statuses") },
          { name: "from", label: "From", type: "date" },
          { name: "to", label: "To", type: "date" },
        ]} />
        {isMissingRelation(error) || campaigns.missing ? (
          <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p>
        ) : (
          <>
            <Table>
              <TableHeader><TableRow><TableHead>Referrer</TableHead><TableHead>Referred user</TableHead><TableHead>Code</TableHead><TableHead>Campaign</TableHead><TableHead>Source</TableHead><TableHead>Country</TableHead><TableHead>Status</TableHead><TableHead>Risk</TableHead><TableHead>Registered</TableHead><TableHead /></TableRow></TableHeader>
              <TableBody>
                {(data ?? []).map((referral) => (
                  <TableRow key={referral.id}>
                    <TableCell>{profiles.get(referral.referrer_id)?.full_name ?? referral.referrer_id.slice(0, 8)}</TableCell>
                    <TableCell>{referral.referred_user_id ? profiles.get(referral.referred_user_id)?.full_name ?? referral.referred_user_id.slice(0, 8) : referral.referred_email}</TableCell>
                    <TableCell className="font-mono text-xs">{referral.code}</TableCell>
                    <TableCell>{referral.campaign_id?.slice(0, 8) ?? "—"}</TableCell>
                    <TableCell>{referral.source ?? "—"}</TableCell>
                    <TableCell>{referral.country ?? "—"}</TableCell>
                    <TableCell><Badge variant={asVariant(referral.status)}>{referral.status.replaceAll("_", " ")}</Badge></TableCell>
                    <TableCell><Badge variant={asVariant(referral.fraud_status)}>{referral.fraud_status}</Badge></TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(referral.created_at)}</TableCell>
                    <TableCell className="text-right"><Link href={`/marketers/referrals/${referral.id}`} className="text-xs font-medium text-ink-700 hover:underline">Open</Link></TableCell>
                  </TableRow>
                ))}
                {!data?.length ? <TableRow><TableCell colSpan={10} className="py-10 text-center text-sm text-ink-500">No referrals match this filter.</TableCell></TableRow> : null}
              </TableBody>
            </Table>
            <Pagination page={page} pageSize={pageSize} total={count ?? 0} searchParams={params} basePath="/marketers/referrals" />
          </>
        )}
      </main>
    </>
  );
}
