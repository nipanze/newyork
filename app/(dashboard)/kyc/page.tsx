import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { KycReviewActions } from "@/components/kyc-review-actions";
import { formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function KycPage() {
  const supabase = await createClient();

  const { data: pending } = await supabase
    .from("kyc_verifications")
    .select("id, user_id, national_id_type, national_id_number, submitted_at, status")
    .eq("status", "pending")
    .order("submitted_at", { ascending: true });

  const userIds = (pending ?? []).map((k) => k.user_id);
  const { data: profiles } = userIds.length
    ? await supabase.from("profiles").select("id, full_name, country").in("id", userIds)
    : { data: [] };

  const profileById = new Map((profiles ?? []).map((p) => [p.id, p]));

  return (
    <>
      <Header title="KYC review" description="Pending identity verification submissions" />
      <main className="flex-1 space-y-3 overflow-y-auto p-6">
        {pending?.length ? (
          pending.map((k) => {
            const profile = profileById.get(k.user_id);
            return (
              <Card key={k.id}>
                <CardContent className="flex flex-wrap items-center justify-between gap-4 p-4">
                  <div>
                    <p className="font-medium text-ink-900">{profile?.full_name ?? k.user_id}</p>
                    <p className="text-xs text-ink-500">
                      {profile?.country} · {k.national_id_type ?? "ID type not set"} ·{" "}
                      {k.national_id_number ?? "no ID number"}
                    </p>
                    <p className="mt-1 text-xs text-ink-500">
                      Submitted {formatDateTime(k.submitted_at)}
                    </p>
                  </div>
                  <div className="flex items-center gap-4">
                    <Badge variant="signal">pending</Badge>
                    <KycReviewActions kycId={k.id} />
                  </div>
                </CardContent>
              </Card>
            );
          })
        ) : (
          <Card>
            <CardContent className="py-10 text-center text-sm text-ink-500">
              No pending KYC submissions — the queue is clear.
            </CardContent>
          </Card>
        )}
      </main>
    </>
  );
}
