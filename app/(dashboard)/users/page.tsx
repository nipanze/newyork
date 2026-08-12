import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Badge } from "@/components/ui/badge";
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
import { formatDate, initials } from "@/lib/utils";
import Link from "next/link";
import type { AccountStatus } from "@/lib/types";
import {
  getPage,
  getPageSize,
  getParam,
  type DashboardSearchParams,
} from "@/lib/dashboard-filters";
import { searchAdminAccounts } from "@/lib/admin/account-search";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<AccountStatus, "confirm" | "signal" | "alert" | "neutral"> = {
  active: "confirm",
  pending_verification: "signal",
  suspended: "alert",
  deactivated: "neutral",
};

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<DashboardSearchParams>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const page = getPage(params);
  const pageSize = getPageSize(params);

  const [{ data: countries }, accountResults] = await Promise.all([
    supabase.from("countries").select("code, name").order("code"),
    searchAdminAccounts({
      q: getParam(params, "q"),
      name: getParam(params, "name"),
      phone: getParam(params, "phone"),
      email: getParam(params, "email"),
      country: getParam(params, "country"),
      accountStatus: getParam(params, "accountStatus"),
      plan: getParam(params, "plan"),
      kycStatus: getParam(params, "kycStatus"),
      admin: getParam(params, "admin"),
      joinedFrom: getParam(params, "joinedFrom"),
      joinedTo: getParam(params, "joinedTo"),
      page,
      pageSize,
    }),
  ]);

  const countryOptions = [
    { label: "All countries", value: "" },
    ...((countries ?? []).map((country) => ({
      label: `${country.name} (${country.code})`,
      value: country.code,
    })) ?? []),
  ];

  return (
    <>
      <Header title="Accounts" description="Every registered user across every market" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        <AdminFilterForm
          resetHref="/users"
          searchParams={params}
          fields={[
            { name: "q", label: "Quick search", placeholder: "Name, phone, or email" },
            { name: "name", label: "Name", placeholder: "Full name" },
            { name: "phone", label: "Phone", placeholder: "+256..." },
            { name: "email", label: "Email", placeholder: "name@example.com" },
            { name: "country", label: "Country", type: "select", options: countryOptions },
            {
              name: "accountStatus",
              label: "Account status",
              type: "select",
              options: [
                { label: "All statuses", value: "" },
                { label: "Active", value: "active" },
                { label: "Pending verification", value: "pending_verification" },
                { label: "Suspended", value: "suspended" },
                { label: "Deactivated", value: "deactivated" },
              ],
            },
            {
              name: "plan",
              label: "Plan",
              type: "select",
              options: [
                { label: "All plans", value: "" },
                { label: "Free", value: "free" },
                { label: "Lender", value: "lender" },
                { label: "Pro", value: "pro" },
              ],
            },
            {
              name: "kycStatus",
              label: "KYC status",
              type: "select",
              options: [
                { label: "All KYC", value: "" },
                { label: "Not submitted", value: "not_submitted" },
                { label: "Pending", value: "pending" },
                { label: "Approved", value: "approved" },
                { label: "Rejected", value: "rejected" },
                { label: "Expired", value: "expired" },
              ],
            },
            {
              name: "admin",
              label: "Admin",
              type: "select",
              options: [
                { label: "All accounts", value: "" },
                { label: "Admins only", value: "yes" },
                { label: "Non-admins", value: "no" },
              ],
            },
            { name: "joinedFrom", label: "Joined from", type: "date" },
            { name: "joinedTo", label: "Joined to", type: "date" },
          ]}
        />

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Account</TableHead>
              <TableHead>Email</TableHead>
              <TableHead>Country</TableHead>
              <TableHead>Plan</TableHead>
              <TableHead>KYC</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Joined</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {accountResults.rows.map((p) => (
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
                <TableCell className="text-ink-600">{p.email ?? "—"}</TableCell>
                <TableCell>{p.country}</TableCell>
                <TableCell className="capitalize">{p.plan}</TableCell>
                <TableCell>
                  <Badge variant={p.kyc_status === "approved" ? "confirm" : p.kyc_status === "pending" ? "signal" : "neutral"}>
                    {p.kyc_status.replace("_", " ")}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={STATUS_VARIANT[p.account_status as AccountStatus]}>{p.account_status}</Badge>
                </TableCell>
                <TableCell className="text-ink-500">{formatDate(p.created_at)}</TableCell>
                <TableCell className="text-right">
                  <Link href={`/users/${p.id}`} className="text-xs font-medium text-ink-700 hover:underline">
                    Manage
                  </Link>
                </TableCell>
              </TableRow>
            ))}
            {!accountResults.rows.length && (
              <TableRow>
                <TableCell colSpan={8} className="py-10 text-center text-sm text-ink-500">
                  No accounts match this filter.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
        <Pagination
          page={page}
          pageSize={pageSize}
          total={accountResults.total}
          searchParams={params}
          basePath="/users"
        />
      </main>
    </>
  );
}
