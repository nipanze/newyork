import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { AdminFilterForm } from "@/components/admin-filter-form";
import { Pagination } from "@/components/pagination";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDateTime } from "@/lib/utils";
import Link from "next/link";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";

export const dynamic = "force-dynamic";

export default async function AuditLogsPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);

  const eventTypeQ = getParam(params, "eventType");
  const entityTypeQ = getParam(params, "entityType");
  const actorQ = getParam(params, "actor");
  const targetQ = getParam(params, "target"); // pre-filter target user from user detail page
  const fromQ = getParam(params, "from");
  const toQ = getParam(params, "to");
  const adminOnlyQ = getParam(params, "adminOnly");

  let query = supabase
    .from("audit_logs")
    .select("id, user_id, event_type, entity_type, entity_id, action, description, created_at", {
      count: "exact",
    })
    .order("created_at", { ascending: false });

  if (eventTypeQ) query = query.ilike("event_type", `%${eventTypeQ}%`);
  if (entityTypeQ) query = query.ilike("entity_type", `%${entityTypeQ}%`);
  if (actorQ) query = query.eq("user_id", actorQ);
  if (targetQ) query = query.or(`user_id.eq.${targetQ},entity_id.eq.${targetQ}`);
  if (fromQ) query = query.gte("created_at", `${fromQ}T00:00:00.000Z`);
  if (toQ) query = query.lte("created_at", `${toQ}T23:59:59.999Z`);
  if (adminOnlyQ === "yes") {
    query = query.or("event_type.ilike.%admin%,action.ilike.%dashboard%");
  }

  const from = (page - 1) * pageSize;
  const { data: logs, count } = await query.range(from, from + pageSize - 1);

  // Resolve actor user names
  const actorIds = [...new Set((logs ?? []).map((l) => l.user_id).filter(Boolean))] as string[];
  const { data: actorProfiles } = actorIds.length
    ? await supabase.from("profiles").select("id, full_name").in("id", actorIds)
    : { data: [] };
  const actorById = new Map((actorProfiles ?? []).map((p) => [p.id, p]));

  return (
    <>
      <Header title="Audit log" description="Append-only compliance trail — read-only" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <AdminFilterForm
          resetHref="/audit-logs"
          searchParams={params}
          fields={[
            {
              name: "eventType",
              label: "Event type",
              type: "select",
              options: [
                { label: "All events", value: "" },
                { label: "Admin actions", value: "admin" },
                { label: "KYC approved", value: "kyc_approved" },
                { label: "KYC rejected", value: "kyc_rejected" },
                { label: "KYC expired", value: "kyc_expired" },
                { label: "Admin moderation", value: "admin_moderation" },
              ],
            },
            {
              name: "entityType",
              label: "Entity type",
              type: "select",
              options: [
                { label: "All entities", value: "" },
                { label: "Profiles", value: "profiles" },
                { label: "KYC verifications", value: "kyc_verifications" },
                { label: "Loan requests", value: "loan_requests" },
                { label: "Forex requests", value: "forex_requests" },
                { label: "Settings", value: "system_settings" },
              ],
            },
            { name: "actor", label: "Actor User ID", placeholder: "User UUID..." },
            {
              name: "adminOnly",
              label: "Scope",
              type: "select",
              options: [
                { label: "All audit events", value: "" },
                { label: "Admin events only", value: "yes" },
              ],
            },
            { name: "from", label: "Date from", type: "date" },
            { name: "to", label: "Date to", type: "date" },
          ]}
        />

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Event</TableHead>
              <TableHead>Entity</TableHead>
              <TableHead>Actor</TableHead>
              <TableHead>Action / Details</TableHead>
              <TableHead>Time</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {logs?.map((log) => {
              const actor = log.user_id ? actorById.get(log.user_id) : null;
              return (
                <TableRow key={log.id}>
                  <TableCell className="font-medium text-ink-900">{log.event_type}</TableCell>
                  <TableCell className="text-ink-500">
                    {log.entity_type
                      ? `${log.entity_type}${log.entity_id ? ` · ${log.entity_id.slice(0, 8)}…` : ""}`
                      : "—"}
                  </TableCell>
                  <TableCell className="text-ink-500">
                    {log.user_id ? (
                      <Link href={`/users/${log.user_id}`} className="text-xs font-medium text-ink-700 hover:underline">
                        {actor?.full_name ?? `${log.user_id.slice(0, 8)}…`}
                      </Link>
                    ) : (
                      "system"
                    )}
                  </TableCell>
                  <TableCell className="text-ink-500">
                    <p>{log.action ?? "—"}</p>
                    {log.description && <p className="text-xs text-ink-500">{log.description}</p>}
                  </TableCell>
                  <TableCell className="text-ink-500">{formatDateTime(log.created_at)}</TableCell>
                </TableRow>
              );
            })}
            {!logs?.length && (
              <TableRow>
                <TableCell colSpan={5} className="py-10 text-center text-sm text-ink-500">
                  No audit events match this filter.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>

        <Pagination
          page={page}
          pageSize={pageSize}
          total={count ?? 0}
          searchParams={params}
          basePath="/audit-logs"
        />
      </main>
    </>
  );
}
