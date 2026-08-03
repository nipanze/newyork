import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDate, initials } from "@/lib/utils";
import Link from "next/link";

export const dynamic = "force-dynamic";

const STATUS_VARIANT = {
  active: "confirm",
  pending_verification: "signal",
  suspended: "alert",
  deactivated: "neutral",
} as const;

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; country?: string }>;
}) {
  const { q, country } = await searchParams;
  const supabase = await createClient();

  let query = supabase
    .from("profiles")
    .select("id, full_name, phone, country, account_status, is_admin, created_at")
    .order("created_at", { ascending: false })
    .limit(100);

  if (country) query = query.eq("country", country);
  if (q) query = query.ilike("full_name", `%${q}%`);

  const [{ data: profiles }, { data: subs }] = await Promise.all([
    query,
    supabase.from("subscriptions").select("user_id, plan, status").eq("status", "active"),
  ]);

  const planByUser = new Map((subs ?? []).map((s) => [s.user_id, s.plan]));

  return (
    <>
      <Header title="Accounts" description="Every registered user across every market" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <form className="flex gap-2">
          <input
            name="q"
            defaultValue={q}
            placeholder="Search by name…"
            className="h-9 w-64 rounded-md border border-paper-300 bg-white px-3 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ink-700"
          />
          <button className="h-9 rounded-md bg-ink-900 px-4 text-sm font-medium text-paper-50">
            Search
          </button>
        </form>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Account</TableHead>
              <TableHead>Country</TableHead>
              <TableHead>Plan</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Joined</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {profiles?.map((p) => (
              <TableRow key={p.id}>
                <TableCell>
                  <div className="flex items-center gap-3">
                    <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-paper-200 text-xs font-semibold text-ink-700">
                      {initials(p.full_name)}
                    </div>
                    <div>
                      <p className="font-medium text-ink-900">{p.full_name ?? "—"}</p>
                      <p className="text-xs text-ink-500">{p.phone ?? "no phone"}</p>
                    </div>
                    {p.is_admin ? <Badge variant="outline">admin</Badge> : null}
                  </div>
                </TableCell>
                <TableCell>{p.country}</TableCell>
                <TableCell className="capitalize">{planByUser.get(p.id) ?? "free"}</TableCell>
                <TableCell>
                  <Badge variant={STATUS_VARIANT[p.account_status]}>{p.account_status}</Badge>
                </TableCell>
                <TableCell className="text-ink-500">{formatDate(p.created_at)}</TableCell>
                <TableCell className="text-right">
                  <Link href={`/users/${p.id}`} className="text-xs font-medium text-ink-700 hover:underline">
                    Manage
                  </Link>
                </TableCell>
              </TableRow>
            ))}
            {!profiles?.length && (
              <TableRow>
                <TableCell colSpan={6} className="py-10 text-center text-sm text-ink-500">
                  No accounts match this filter.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </main>
    </>
  );
}
