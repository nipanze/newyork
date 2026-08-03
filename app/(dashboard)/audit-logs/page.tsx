import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function AuditLogsPage() {
  const supabase = await createClient();

  const { data: logs } = await supabase
    .from("audit_logs")
    .select("id, user_id, event_type, entity_type, entity_id, action, created_at")
    .order("created_at", { ascending: false })
    .limit(200);

  return (
    <>
      <Header title="Audit log" description="Append-only compliance trail — read-only" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Event</TableHead>
              <TableHead>Entity</TableHead>
              <TableHead>Actor</TableHead>
              <TableHead>Action</TableHead>
              <TableHead>Time</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {logs?.map((log) => (
              <TableRow key={log.id}>
                <TableCell className="font-medium text-ink-900">{log.event_type}</TableCell>
                <TableCell className="text-ink-500">
                  {log.entity_type ? `${log.entity_type}${log.entity_id ? ` · ${log.entity_id.slice(0, 8)}…` : ""}` : "—"}
                </TableCell>
                <TableCell className="text-ink-500">
                  {log.user_id ? `${log.user_id.slice(0, 8)}…` : "system"}
                </TableCell>
                <TableCell className="text-ink-500">{log.action ?? "—"}</TableCell>
                <TableCell className="text-ink-500">{formatDateTime(log.created_at)}</TableCell>
              </TableRow>
            ))}
            {!logs?.length && (
              <TableRow>
                <TableCell colSpan={5} className="py-10 text-center text-sm text-ink-500">
                  No audit events recorded yet.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </main>
    </>
  );
}
