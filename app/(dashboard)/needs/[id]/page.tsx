import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { NeedModerationActions } from "@/components/need-moderation-actions";
import { formatDateTime, formatCurrency } from "@/lib/utils";
import { ArrowLeft, User, PhoneCall, Handshake } from "lucide-react";

export const dynamic = "force-dynamic";

const STATUS_VARIANT: Record<string, "confirm" | "signal" | "alert" | "neutral"> = {
  active: "confirm",
  matched: "signal",
  expired: "neutral",
  cancelled: "alert",
  accepted: "confirm",
  pending: "signal",
  rejected: "alert",
  withdrawn: "neutral",
};

export default async function NeedDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user: currentUser },
  } = await supabase.auth.getUser();

  const { data: adminProfile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", currentUser?.id ?? "")
    .single();

  const { data: need } = await supabase
    .from("needs_requests")
    .select(`
      *,
      profiles:requester_id ( id, full_name, phone, country, district )
    `)
    .eq("request_id", id)
    .single();

  if (!need) {
    notFound();
  }

  const requester = Array.isArray(need.profiles) ? need.profiles[0] : need.profiles;

  // Fetch offers for this need
  const { data: offers } = await supabase
    .from("need_offers")
    .select(`
      *,
      profiles:offer_maker_id ( id, full_name, phone, country )
    `)
    .eq("need_id", id)
    .order("offered_at", { ascending: false });

  // Fetch contact reveals for this need
  const { data: reveals } = await supabase
    .from("need_contact_reveals")
    .select(`
      *,
      provider:provider_id ( id, full_name, phone ),
      requester:requester_id ( id, full_name, phone )
    `)
    .eq("need_id", id)
    .order("unlocked_at", { ascending: false });

  return (
    <div className="flex-1 space-y-6 p-6">
      <div className="flex items-center gap-3">
        <Link
          href="/needs"
          className="inline-flex items-center gap-1 text-xs text-ink-500 hover:text-ink-800"
        >
          <ArrowLeft className="h-3 w-3" /> Back to Needs Marketplace
        </Link>
      </div>

      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <Header
          title={need.title}
          description={`Need ID: ${need.request_id} · Listed: ${formatDateTime(need.listed_at)}`}
          adminName={adminProfile?.full_name}
        />
        <NeedModerationActions needId={need.request_id} currentStatus={need.status} />
      </div>

      {/* Overview Cards */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Status</span>
            <div className="mt-2">
              <Badge variant={STATUS_VARIANT[need.status] || "neutral"} className="capitalize">
                {need.status}
              </Badge>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Budget</span>
            <p className="mt-2 text-xl font-bold text-ink-950">
              {formatCurrency(need.budget, need.currency || "UGX")}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Category & Location</span>
            <p className="mt-2 text-sm font-semibold capitalize text-ink-900">
              {need.category || need.category_slug?.replace(/_/g, " ")}
            </p>
            <p className="text-xs text-ink-500">
              {need.location ? `${need.location}, ` : ""}
              {need.country}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <span className="text-xs font-medium text-ink-500">Offers & Reveals</span>
            <p className="mt-2 text-xl font-bold text-ink-950">
              {offers?.length ?? 0}
              <span className="text-xs font-normal text-ink-500"> offers · {reveals?.length ?? 0} revealed</span>
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Requester & Specification Details */}
      <div className="grid gap-6 md:grid-cols-3">
        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle className="text-sm font-semibold text-ink-900">
              Need Specification & Details
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 text-sm text-ink-800">
            <div>
              <span className="text-xs font-medium text-ink-500">Specification</span>
              <p className="mt-1 whitespace-pre-wrap rounded-md bg-paper-100 p-3 text-xs font-mono">
                {need.specification || "No detailed specification provided."}
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4 text-xs">
              <div>
                <span className="text-ink-500">Urgency:</span>
                <span className="ml-2 font-medium capitalize text-ink-900">{need.urgency || "Flexible"}</span>
              </div>
              <div>
                <span className="text-ink-500">Capability Slug:</span>
                <span className="ml-2 font-mono text-ink-900">{need.capability_slug || "None"}</span>
              </div>
              <div>
                <span className="text-ink-500">Views:</span>
                <span className="ml-2 font-medium text-ink-900">{need.views_count ?? 0}</span>
              </div>
              <div>
                <span className="text-ink-500">Expires At:</span>
                <span className="ml-2 text-ink-900">
                  {need.expires_at ? formatDateTime(need.expires_at) : "No expiry"}
                </span>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
              <User className="h-4 w-4" /> Requester Info
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-xs">
            {requester ? (
              <>
                <div>
                  <span className="text-ink-500">Name:</span>
                  <Link
                    href={`/users/${requester.id}`}
                    className="ml-2 font-medium text-ink-900 hover:underline"
                  >
                    {requester.full_name || "User"}
                  </Link>
                </div>
                <div>
                  <span className="text-ink-500">Phone:</span>
                  <span className="ml-2 text-ink-900">{requester.phone || "—"}</span>
                </div>
                <div>
                  <span className="text-ink-500">Location:</span>
                  <span className="ml-2 text-ink-900">
                    {requester.district ? `${requester.district}, ` : ""}
                    {requester.country}
                  </span>
                </div>
              </>
            ) : (
              <p className="italic text-ink-400">Anonymous or Unregistered</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Competing Offers Table */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
            <Handshake className="h-4 w-4" /> Competing Provider Offers ({offers?.length ?? 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Provider</TableHead>
                <TableHead>Identity</TableHead>
                <TableHead>Price</TableHead>
                <TableHead>Timeline</TableHead>
                <TableHead>Message</TableHead>
                <TableHead>Terms Locked</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Offered</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {!offers?.length ? (
                <TableRow>
                  <TableCell colSpan={8} className="py-6 text-center text-xs text-ink-500">
                    No offers submitted for this need yet.
                  </TableCell>
                </TableRow>
              ) : (
                offers.map((offer: any) => {
                  const provider = Array.isArray(offer.profiles) ? offer.profiles[0] : offer.profiles;
                  return (
                    <TableRow key={offer.id}>
                      <TableCell>
                        {provider ? (
                          <Link
                            href={`/providers/${provider.id}`}
                            className="font-medium text-ink-900 hover:underline"
                          >
                            {offer.provider_display_name || provider.full_name || "Provider"}
                          </Link>
                        ) : (
                          <span className="text-xs text-ink-500">{offer.provider_display_name || "Provider"}</span>
                        )}
                        <p className="text-[11px] text-ink-500">{provider?.phone || ""}</p>
                      </TableCell>
                      <TableCell className="text-xs capitalize text-ink-700">
                        {offer.provider_identity_type || "individual"}
                      </TableCell>
                      <TableCell className="text-xs font-semibold text-ink-900">
                        {formatCurrency(offer.price, offer.currency || "UGX")}
                      </TableCell>
                      <TableCell className="text-xs text-ink-700">
                        {offer.timeline_text || "—"}
                      </TableCell>
                      <TableCell className="max-w-[200px] text-xs text-ink-700 truncate" title={offer.message}>
                        {offer.message || "—"}
                      </TableCell>
                      <TableCell className="text-xs text-ink-500">
                        {offer.terms_locked_at ? formatDateTime(offer.terms_locked_at) : "Unlocked"}
                      </TableCell>
                      <TableCell>
                        <Badge variant={STATUS_VARIANT[offer.status] || "neutral"} className="capitalize">
                          {offer.status}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-xs text-ink-500">
                        {formatDateTime(offer.offered_at)}
                      </TableCell>
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Contact Reveals Table */}
      {reveals && reveals.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
              <PhoneCall className="h-4 w-4" /> Contact Details Unlocks ({reveals.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Unlocked By</TableHead>
                  <TableHead>Provider Revealed</TableHead>
                  <TableHead>Requester</TableHead>
                  <TableHead>Unlocked At</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {reveals.map((rev: any) => {
                  const prov = Array.isArray(rev.provider) ? rev.provider[0] : rev.provider;
                  const req = Array.isArray(rev.requester) ? rev.requester[0] : rev.requester;
                  return (
                    <TableRow key={rev.id}>
                      <TableCell className="text-xs font-mono text-ink-700">
                        {rev.unlocked_by === rev.requester_id ? "Requester" : "Provider"}
                      </TableCell>
                      <TableCell>
                        <Link href={`/providers/${prov?.id}`} className="font-medium text-ink-900 hover:underline">
                          {prov?.full_name || "Provider"}
                        </Link>
                        <p className="text-[11px] text-ink-500">{prov?.phone || "—"}</p>
                      </TableCell>
                      <TableCell>
                        <Link href={`/users/${req?.id}`} className="font-medium text-ink-900 hover:underline">
                          {req?.full_name || "Requester"}
                        </Link>
                        <p className="text-[11px] text-ink-500">{req?.phone || "—"}</p>
                      </TableCell>
                      <TableCell className="text-xs text-ink-500">
                        {formatDateTime(rev.unlocked_at)}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

