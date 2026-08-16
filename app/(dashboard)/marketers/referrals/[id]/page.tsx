import { notFound } from "next/navigation";
import { Header } from "@/components/header";
import { MarketerNav } from "@/components/marketer-nav";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { createAdminClient } from "@/lib/supabase/admin";
import { asVariant, getProfileSummaries, isMissingRelation, migrationMessage } from "@/lib/admin/marketers";
import { formatAmount, formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function ReferralDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = createAdminClient();
  const { data: referral, error } = await supabase.from("referrals").select("*").eq("id", id).maybeSingle();
  if (isMissingRelation(error)) {
    return (
      <>
        <Header title="Referral detail" description="Attribution, qualification, reward, payout, and audit trace" />
        <main className="flex-1 space-y-4 overflow-y-auto p-6"><MarketerNav active="/marketers/referrals" /><p className="rounded-md border border-paper-300 bg-white p-4 text-sm text-ink-600">{migrationMessage()}</p></main>
      </>
    );
  }
  if (!referral) notFound();

  const [{ data: marketer }, profiles, { data: campaign }, { data: reward }, { data: events }, { data: auditLogs }] = await Promise.all([
    supabase.from("referral_marketers").select("id, referral_code, status").eq("profile_id", referral.referrer_id).maybeSingle(),
    getProfileSummaries([referral.referrer_id, referral.referred_user_id].filter(Boolean)),
    referral.campaign_id ? supabase.from("referral_campaigns").select("*").eq("id", referral.campaign_id).maybeSingle() : { data: null },
    supabase.from("referral_rewards").select("*").eq("referral_id", referral.id).maybeSingle(),
    supabase.from("referral_events").select("*").eq("referral_id", referral.id).order("created_at", { ascending: false }).limit(20),
    supabase.from("audit_logs").select("id, event_type, action, created_at, new_values").eq("entity_id", referral.id).order("created_at", { ascending: false }).limit(20),
  ]);
  const { data: payout } = marketer
    ? await supabase.from("referral_payouts").select("*").eq("marketer_id", marketer.id).order("created_at", { ascending: false }).limit(1).maybeSingle()
    : { data: null };

  const referrer = profiles.get(referral.referrer_id);
  const referred = referral.referred_user_id ? profiles.get(referral.referred_user_id) : null;

  return (
    <>
      <Header title="Referral detail" description={referral.id} />
      <main className="flex-1 space-y-6 overflow-y-auto p-6">
        <MarketerNav active="/marketers/referrals" />
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader><CardTitle>Attribution</CardTitle></CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="Referrer" value={referrer?.full_name ?? referral.referrer_id} />
              <Field label="Referred user" value={referred?.full_name ?? referral.referred_email ?? referral.referred_user_id ?? "—"} />
              <Field label="Referral code" value={referral.code} />
              <Field label="Campaign" value={campaign?.name ?? "—"} />
              <Field label="Source" value={referral.source ?? "—"} />
              <Field label="Country" value={referral.country ?? "—"} />
              <Field label="Registered" value={formatDateTime(referral.created_at)} />
              <Field label="Verified" value={formatDateTime(referral.verified_at)} />
              <Field label="Qualifying event" value={referral.qualifying_event ?? "—"} />
              <Field label="Qualified" value={formatDateTime(referral.qualified_at)} />
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle>Reward and risk</CardTitle></CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 pt-0 text-sm">
              <Field label="Referral status" value={<Badge variant={asVariant(referral.status)}>{referral.status.replaceAll("_", " ")}</Badge>} />
              <Field label="Fraud/risk" value={<Badge variant={asVariant(referral.fraud_status)}>{referral.fraud_status}</Badge>} />
              <Field label="Risk reason" value={referral.fraud_reason ?? "—"} />
              <Field label="Reward" value={reward ? formatAmount(reward.amount, reward.currency) : "No reward generated"} />
              <Field label="Reward status" value={reward ? <Badge variant={asVariant(reward.status)}>{reward.status.replaceAll("_", " ")}</Badge> : "—"} />
              <Field label="Payout status" value={payout ? <Badge variant={asVariant(payout.status)}>{payout.status.replaceAll("_", " ")}</Badge> : "—"} />
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader><CardTitle>Why reward was or was not generated</CardTitle></CardHeader>
          <CardContent className="space-y-2 pt-0 text-sm text-ink-600">
            <p>Status is <strong>{referral.status}</strong>; qualifying event is <strong>{referral.qualifying_event ?? "not recorded"}</strong>.</p>
            <p>{reward ? `A ${reward.status} reward exists for ${formatAmount(reward.amount, reward.currency)}.` : "No reward row exists yet. Check campaign rules, qualification event, duplicate attribution, and fraud status before approving any reward."}</p>
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <Timeline title="Referral events" rows={(events ?? []).map((e) => ({ id: e.id, label: e.event_type, date: e.created_at }))} />
          <Timeline title="Audit history" rows={(auditLogs ?? []).map((e) => ({ id: e.id, label: `${e.event_type} · ${e.action ?? "—"}`, date: e.created_at }))} />
        </div>
      </main>
    </>
  );
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return <div><p className="text-xs uppercase tracking-wide text-ink-500">{label}</p><div className="mt-1 font-medium text-ink-900">{value}</div></div>;
}

function Timeline({ title, rows }: { title: string; rows: Array<{ id: string; label: string; date: string }> }) {
  return <Card><CardHeader><CardTitle>{title}</CardTitle></CardHeader><CardContent className="space-y-2 pt-0">{rows.map((row) => <div key={row.id} className="flex justify-between rounded-md border border-paper-200 px-3 py-2 text-sm"><span>{row.label}</span><span className="text-xs text-ink-500">{formatDateTime(row.date)}</span></div>)}{!rows.length ? <p className="text-sm text-ink-500">No history recorded.</p> : null}</CardContent></Card>;
}
