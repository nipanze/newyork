import Link from "next/link";
import { notFound } from "next/navigation";
import { Header } from "@/components/header";
import { MarketerNav } from "@/components/marketer-nav";
import { MarketerActions } from "@/components/marketer-actions";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createAdminClient } from "@/lib/supabase/admin";
import { asVariant, getProfileSummaries, isMissingRelation, migrationMessage, safeNumber } from "@/lib/admin/marketers";
import { formatAmount, formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function MarketerDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = createAdminClient();
  const { data: marketer, error } = await supabase.from("referral_marketers").select("*").eq("id", id).maybeSingle();
  if (isMissingRelation(error)) {
    return (
      <>
        <Header title="Marketer detail" description="Referral-agent profile and reward controls" />
        <main className="flex-1 space-y-4 overflow-y-auto p-6">
          <MarketerNav active="/marketers/users" />
          <p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p>
        </main>
      </>
    );
  }
  if (!marketer) notFound();

  const [
    profiles,
    { data: subscription },
    { data: kyc },
    { data: referrals },
    { data: rewards },
    { data: campaign },
    { data: auditLogs },
  ] = await Promise.all([
    getProfileSummaries([marketer.profile_id]),
    supabase.from("subscriptions").select("plan, status").eq("user_id", marketer.profile_id).eq("status", "active").maybeSingle(),
    supabase.from("kyc_verifications").select("status").eq("user_id", marketer.profile_id).order("submitted_at", { ascending: false }).limit(1).maybeSingle(),
    supabase.from("referrals").select("id, referred_user_id, referred_email, code, country, status, qualifying_event, qualified_at, campaign_id, created_at").eq("referrer_id", marketer.profile_id).order("created_at", { ascending: false }).limit(50),
    supabase.from("referral_rewards").select("id, referral_id, amount, currency, status, created_at").eq("marketer_id", marketer.id),
    marketer.default_campaign_id
      ? supabase.from("referral_campaigns").select("id, name").eq("id", marketer.default_campaign_id).maybeSingle()
      : { data: null },
    supabase.from("audit_logs").select("id, event_type, action, entity_type, entity_id, created_at").or(`entity_id.eq.${marketer.id},entity_id.eq.${marketer.profile_id}`).order("created_at", { ascending: false }).limit(8),
  ]);

  const profile = profiles.get(marketer.profile_id);
  const rewardsByReferral = new Map((rewards ?? []).map((reward) => [reward.referral_id, reward]));
  const totals = (rewards ?? []).reduce(
    (acc, reward) => {
      acc.total += safeNumber(reward.amount);
      acc.pending += reward.status === "pending" ? safeNumber(reward.amount) : 0;
      acc.approved += reward.status === "approved" ? safeNumber(reward.amount) : 0;
      acc.paid += reward.status === "paid" ? safeNumber(reward.amount) : 0;
      acc.currency = acc.currency ?? reward.currency;
      return acc;
    },
    { total: 0, pending: 0, approved: 0, paid: 0, currency: null as string | null }
  );
  const registered = referrals?.length ?? 0;
  const verified = (referrals ?? []).filter((r) => r.status === "verified" || r.status === "qualified").length;
  const qualified = (referrals ?? []).filter((r) => r.status === "qualified").length;
  const conversion = registered ? Math.round((qualified / registered) * 100) : 0;

  return (
    <>
      <Header title={profile?.full_name ?? marketer.referral_code} description="Marketer profile, referrals, rewards, and controls" />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <MarketerNav active="/marketers/users" />

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader><CardTitle>Profile</CardTitle></CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="Name" value={profile?.full_name ?? "—"} />
              <Field label="Email" value={profile?.email ?? "—"} />
              <Field label="Phone" value={profile?.phone ?? "—"} />
              <Field label="Country" value={profile?.country ?? "—"} />
              <Field label="Account status" value={profile?.account_status ?? "—"} />
              <Field label="Plan" value={subscription?.plan ?? "free"} />
              <Field label="KYC" value={kyc?.status ?? "not_submitted"} />
              <Field label="Referral code" value={marketer.referral_code} />
              <Field label="Marketer status" value={<Badge variant={asVariant(marketer.status)}>{marketer.status.replaceAll("_", " ")}</Badge>} />
              <Field label="Campaign" value={campaign?.name ?? "—"} />
              <Field label="Joined" value={formatDateTime(marketer.joined_at)} />
              <Field label="Last activity" value={formatDateTime(marketer.last_activity_at)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>Controls</CardTitle></CardHeader>
            <CardContent className="space-y-4 pt-0">
              <MarketerActions
                endpoint={`/api/admin/marketers/${marketer.id}`}
                actions={[
                  { label: "Activate", value: "active", variant: "confirm", confirm: "Activate this marketer?" },
                  { label: "Suspend", value: "suspended", variant: "destructive", confirm: "Suspend this marketer?" },
                  { label: "Under review", value: "under_review", variant: "outline", confirm: "Flag this marketer for review?" },
                  { label: "Deactivate", value: "deactivated", variant: "destructive", confirm: "Deactivate this marketer?" },
                ]}
              />
              <div className="rounded-md border border-paper-300 p-3 text-xs text-ink-500">
                Referral link: <span className="font-mono text-ink-800">/signup?ref={marketer.referral_code}</span>
              </div>
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <Mini label="Registrations" value={registered} />
          <Mini label="Verified" value={verified} />
          <Mini label="Qualified" value={qualified} />
          <Mini label="Conversion" value={`${conversion}%`} />
          <Mini label="Total rewards" value={formatAmount(totals.total, totals.currency ?? undefined)} />
          <Mini label="Pending" value={formatAmount(totals.pending, totals.currency ?? undefined)} />
          <Mini label="Approved" value={formatAmount(totals.approved, totals.currency ?? undefined)} />
          <Mini label="Paid" value={formatAmount(totals.paid, totals.currency ?? undefined)} />
        </div>

        <Card>
          <CardHeader><CardTitle>Referral history</CardTitle></CardHeader>
          <CardContent className="pt-0">
            <Table>
              <TableHeader><TableRow><TableHead>Referral</TableHead><TableHead>Registered</TableHead><TableHead>Country</TableHead><TableHead>Status</TableHead><TableHead>Qualifying event</TableHead><TableHead>Reward</TableHead><TableHead>Campaign</TableHead></TableRow></TableHeader>
              <TableBody>
                {(referrals ?? []).map((referral) => {
                  const reward = rewardsByReferral.get(referral.id);
                  return (
                    <TableRow key={referral.id}>
                      <TableCell><Link href={`/marketers/referrals/${referral.id}`} className="font-medium text-ink-800 hover:underline">{referral.referred_email ?? referral.referred_user_id?.slice(0, 8) ?? "Unknown"}</Link></TableCell>
                      <TableCell className="text-ink-500">{formatDateTime(referral.created_at)}</TableCell>
                      <TableCell>{referral.country ?? "—"}</TableCell>
                      <TableCell><Badge variant={asVariant(referral.status)}>{referral.status.replaceAll("_", " ")}</Badge></TableCell>
                      <TableCell>{referral.qualifying_event ?? "—"}</TableCell>
                      <TableCell>{reward ? `${formatAmount(reward.amount, reward.currency)} · ${reward.status}` : "—"}</TableCell>
                      <TableCell>{referral.campaign_id?.slice(0, 8) ?? "—"}</TableCell>
                    </TableRow>
                  );
                })}
                {!referrals?.length ? <TableRow><TableCell colSpan={7} className="py-10 text-center text-sm text-ink-500">No referrals attributed to this marketer.</TableCell></TableRow> : null}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Audit history</CardTitle></CardHeader>
          <CardContent className="space-y-2 pt-0">
            {(auditLogs ?? []).map((log) => (
              <div key={log.id} className="flex items-center justify-between rounded-md border border-paper-200 px-3 py-2 text-sm">
                <span>{log.event_type} · {log.action ?? "—"}</span>
                <span className="text-xs text-ink-500">{formatDateTime(log.created_at)}</span>
              </div>
            ))}
            {!auditLogs?.length ? <p className="text-sm text-ink-500">No audit activity yet.</p> : null}
          </CardContent>
        </Card>
      </main>
    </>
  );
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return <div><p className="text-xs uppercase tracking-wide text-ink-500">{label}</p><div className="mt-1 font-medium text-ink-900">{value}</div></div>;
}

function Mini({ label, value }: { label: string; value: React.ReactNode }) {
  return <div className="rounded-md border border-paper-300 bg-white p-4"><p className="text-xs uppercase tracking-wide text-ink-500">{label}</p><p className="mt-1 font-tabular text-lg font-semibold text-ink-900">{value}</p></div>;
}
