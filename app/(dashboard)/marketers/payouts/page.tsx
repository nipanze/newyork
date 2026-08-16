import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { MarketerNav } from "@/components/marketer-nav";
import { MarketerActions } from "@/components/marketer-actions";
import { Pagination } from "@/components/pagination";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createAdminClient } from "@/lib/supabase/admin";
import { getPage, getPageSize, getParam, type DashboardSearchParams } from "@/lib/dashboard-filters";
import { PAYOUT_STATUS_OPTIONS, asVariant, getProfileSummaries, isMissingRelation, migrationMessage, statusOptions } from "@/lib/admin/marketers";
import { formatAmount, formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function PayoutsPage({ searchParams }: { searchParams: Promise<DashboardSearchParams> }) {
  const params = await searchParams;
  const supabase = createAdminClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);
  const status = getParam(params, "status");

  let query = supabase.from("referral_payouts").select("*", { count: "exact" }).order("requested_at", { ascending: false });
  if (status) query = query.eq("status", status);
  const from = (page - 1) * pageSize;
  const { data, count, error } = await query.range(from, from + pageSize - 1);
  const { data: marketers } = data?.length ? await supabase.from("referral_marketers").select("id, profile_id, referral_code").in("id", data.map((p) => p.marketer_id)) : { data: [] };
  const marketerById = new Map((marketers ?? []).map((m) => [m.id, m]));
  const profiles = await getProfileSummaries((marketers ?? []).map((m) => m.profile_id));

  return (
    <>
      <Header title="Referral payouts" description="Marketer reward payout workflow, ready for future provider integration" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <MarketerNav active="/marketers/payouts" />
        <AdminFilterForm resetHref="/marketers/payouts" searchParams={params} fields={[
          { name: "status", label: "Status", type: "select", options: statusOptions(PAYOUT_STATUS_OPTIONS, "All statuses") },
        ]} />
        {isMissingRelation(error) ? <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p> : (
          <>
            <Table>
              <TableHeader><TableRow><TableHead>Payout ID</TableHead><TableHead>Marketer</TableHead><TableHead>Amount</TableHead><TableHead>Method</TableHead><TableHead>Destination</TableHead><TableHead>Status</TableHead><TableHead>Requested</TableHead><TableHead>Approved</TableHead><TableHead>Completed</TableHead><TableHead>Failure</TableHead><TableHead>Actions</TableHead></TableRow></TableHeader>
              <TableBody>
                {(data ?? []).map((payout) => {
                  const marketer = marketerById.get(payout.marketer_id);
                  return <TableRow key={payout.id}>
                    <TableCell className="font-mono text-xs">{payout.id.slice(0, 8)}</TableCell>
                    <TableCell>{marketer ? profiles.get(marketer.profile_id)?.full_name ?? marketer.referral_code : "—"}</TableCell>
                    <TableCell>{formatAmount(payout.amount, payout.currency)}</TableCell>
                    <TableCell>{payout.payout_method ?? "—"}</TableCell>
                    <TableCell className="max-w-40 truncate">{payout.payout_destination_ref ?? "—"}</TableCell>
                    <TableCell><Badge variant={asVariant(payout.status)}>{payout.status.replaceAll("_", " ")}</Badge></TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(payout.requested_at)}</TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(payout.approved_at)}</TableCell>
                    <TableCell className="text-ink-500">{formatDateTime(payout.completed_at)}</TableCell>
                    <TableCell>{payout.failure_reason ?? "—"}</TableCell>
                    <TableCell><MarketerActions endpoint={`/api/admin/marketers/payouts/${payout.id}`} actions={[
                      { label: "Review", value: "under_review", variant: "outline" },
                      { label: "Approve", value: "approved", variant: "confirm", confirm: "Approve this payout for processing?" },
                      { label: "Processing", value: "processing", variant: "outline" },
                      { label: "Paid", value: "paid", variant: "confirm", confirm: "Only continue if the payout provider/process confirms payment. Mark paid?" },
                      { label: "Failed", value: "failed", variant: "destructive", confirm: "Mark this payout failed?" },
                    ]} /></TableCell>
                  </TableRow>;
                })}
                {!data?.length ? <TableRow><TableCell colSpan={11} className="py-10 text-center text-sm text-ink-500">No payouts match this filter.</TableCell></TableRow> : null}
              </TableBody>
            </Table>
            <Pagination page={page} pageSize={pageSize} total={count ?? 0} searchParams={params} basePath="/marketers/payouts" />
          </>
        )}
      </main>
    </>
  );
}
