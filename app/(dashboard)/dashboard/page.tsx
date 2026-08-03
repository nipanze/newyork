import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatAmount, formatDateTime } from "@/lib/utils";
import { Users, HandCoins, ShieldCheck, Receipt, Globe2 } from "lucide-react";
import Link from "next/link";

export const dynamic = "force-dynamic";

export default async function DashboardOverviewPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [
    { count: userCount },
    { count: activeLoanCount },
    { count: pendingKycCount },
    { count: activeCountryCount },
    { data: recentLoans },
    { data: profile },
  ] = await Promise.all([
    supabase.from("profiles").select("id", { count: "exact", head: true }),
    supabase.from("loan_requests").select("id", { count: "exact", head: true }).eq("status", "active"),
    supabase.from("kyc_verifications").select("id", { count: "exact", head: true }).eq("status", "pending"),
    supabase.from("countries").select("code", { count: "exact", head: true }).eq("is_active", true),
    supabase
      .from("loan_requests")
      .select("id, title, country, requested_amount, status, listed_at")
      .order("listed_at", { ascending: false })
      .limit(6),
    supabase.from("profiles").select("full_name").eq("id", user!.id).single(),
  ]);

  return (
    <>
      <Header
        title="Overview"
        description="Marketplace health across every active market"
        adminName={profile?.full_name}
      />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard label="Total accounts" value={userCount ?? 0} icon={Users} />
          <StatCard label="Active loan listings" value={activeLoanCount ?? 0} icon={HandCoins} />
          <StatCard
            label="KYC pending review"
            value={pendingKycCount ?? 0}
            icon={ShieldCheck}
            tone={pendingKycCount ? "signal" : "neutral"}
            hint={pendingKycCount ? "Needs attention" : "All caught up"}
          />
          <StatCard label="Active markets" value={activeCountryCount ?? 0} icon={Globe2} />
        </div>

        <Card>
          <CardHeader className="flex-row items-center justify-between space-y-0">
            <CardTitle>Recent listings</CardTitle>
            <Link href="/loans" className="text-xs font-medium text-ink-700 hover:underline">
              View all
            </Link>
          </CardHeader>
          <CardContent className="space-y-2 pt-1">
            {recentLoans?.length ? (
              recentLoans.map((loan) => (
                <div
                  key={loan.id}
                  className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2.5"
                >
                  <div>
                    <p className="text-sm font-medium text-ink-900">{loan.title}</p>
                    <p className="text-xs text-ink-500">
                      {loan.country} · {formatDateTime(loan.listed_at)}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="font-tabular text-sm text-ink-700">
                      {formatAmount(loan.requested_amount, undefined)}
                    </span>
                    <Badge variant={loan.status === "active" ? "confirm" : "neutral"}>{loan.status}</Badge>
                  </div>
                </div>
              ))
            ) : (
              <p className="py-6 text-center text-sm text-ink-500">No listings yet.</p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Receipt className="h-4 w-4" /> Reminder
            </CardTitle>
          </CardHeader>
          <CardContent className="pt-0 text-sm text-ink-700">
            This console is read/act on the same Supabase project as the Flutter app. Nipanze
            never holds, pools, or moves funds between borrowers and lenders — actions here are
            limited to moderation (accounts, KYC, listings, markets, settings), never to
            payments between users.
          </CardContent>
        </Card>
      </main>
    </>
  );
}
