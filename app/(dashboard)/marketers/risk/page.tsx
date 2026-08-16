import Link from "next/link";
import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { MarketerNav } from "@/components/marketer-nav";
import { MarketerActions } from "@/components/marketer-actions";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createAdminClient } from "@/lib/supabase/admin";
import { getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import { asVariant, getCountryOptions, getProfileSummaries, isMissingRelation, migrationMessage } from "@/lib/admin/marketers";
import { formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function RiskPage({ searchParams }: { searchParams: Promise<DashboardSearchParams> }) {
  const params = await searchParams;
  const supabase = createAdminClient();
  const country = getParam(params, "country");
  const signal = getParam(params, "signal");
  const countryOptions = await getCountryOptions();

  const { data: marketers, error } = await supabase
    .from("referral_marketers")
    .select("id, profile_id, referral_code, status, risk_status, risk_reason, last_activity_at")
    .in("risk_status", signal ? [signal] : ["review", "flagged"])
    .order("last_activity_at", { ascending: false, nullsFirst: false })
    .limit(100);

  const profiles = await getProfileSummaries((marketers ?? []).map((m) => m.profile_id));
  let rows = marketers ?? [];
  if (country) rows = rows.filter((row) => profiles.get(row.profile_id)?.country === country);

  return (
    <>
      <Header title="Fraud/Risk" description="Suspicious referral patterns for review, not automatic bans" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/risk" />
        <AdminFilterForm resetHref="/marketers/risk" searchParams={params} fields={[
          { name: "country", label: "Country", type: "select", options: countryOptions },
          { name: "signal", label: "Signal", type: "select", options: [
            { label: "Review or flagged", value: "" },
            { label: "Review", value: "review" },
            { label: "Flagged", value: "flagged" },
          ] },
        ]} />
        {isMissingRelation(error) ? <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p> : (
          <Table>
            <TableHeader><TableRow><TableHead>Marketer</TableHead><TableHead>Code</TableHead><TableHead>Country</TableHead><TableHead>Account status</TableHead><TableHead>Risk</TableHead><TableHead>Reason</TableHead><TableHead>Last activity</TableHead><TableHead>Actions</TableHead></TableRow></TableHeader>
            <TableBody>
              {rows.map((marketer) => {
                const profile = profiles.get(marketer.profile_id);
                return <TableRow key={marketer.id}>
                  <TableCell><Link href={`/marketers/users/${marketer.id}`} className="font-medium text-ink-800 hover:underline">{profile?.full_name ?? "Unnamed marketer"}</Link><p className="text-xs text-ink-500">{profile?.email ?? profile?.phone ?? "no contact"}</p></TableCell>
                  <TableCell className="font-mono text-xs">{marketer.referral_code}</TableCell>
                  <TableCell>{profile?.country ?? "—"}</TableCell>
                  <TableCell><Badge variant={asVariant(marketer.status)}>{marketer.status.replaceAll("_", " ")}</Badge></TableCell>
                  <TableCell><Badge variant={asVariant(marketer.risk_status)}>{marketer.risk_status}</Badge></TableCell>
                  <TableCell>{marketer.risk_reason ?? "Manual review required"}</TableCell>
                  <TableCell className="text-ink-500">{formatDateTime(marketer.last_activity_at)}</TableCell>
                  <TableCell><MarketerActions endpoint={`/api/admin/marketers/${marketer.id}`} actions={[
                    { label: "Review", value: "under_review", variant: "outline", confirm: "Keep this marketer under review?" },
                    { label: "Suspend", value: "suspended", variant: "destructive", confirm: "Suspend this marketer?" },
                    { label: "Clear", value: "active", variant: "confirm", confirm: "Clear review by reactivating this marketer?" },
                  ]} /></TableCell>
                </TableRow>;
              })}
              {!rows.length ? <TableRow><TableCell colSpan={8} className="py-10 text-center text-sm text-ink-500">No marketer risk items match this filter.</TableCell></TableRow> : null}
            </TableBody>
          </Table>
        )}
      </main>
    </>
  );
}
