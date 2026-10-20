import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { CapabilityPolicyEditor } from "@/components/capability-policy-editor";
import { SlidersHorizontal, ArrowLeft, ShieldCheck } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function CapabilitiesSettingsPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: adminProfile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", user?.id ?? "")
    .single();

  // Fetch capabilities with their parent category
  const { data: capabilities } = await supabase
    .from("need_capabilities")
    .select("*, need_categories ( name, icon, sort_order )")
    .order("category_slug", { ascending: true })
    .order("name", { ascending: true });

  // Fetch verification requirements matrix
  const { data: requirements } = await supabase
    .from("verification_requirements")
    .select("*")
    .order("scope_type")
    .order("scope_id");

  return (
    <div className="flex-1 space-y-6 p-6">
      <div className="flex items-center gap-3">
        <Link
          href="/settings"
          className="inline-flex items-center gap-1 text-xs text-ink-500 hover:text-ink-800"
        >
          <ArrowLeft className="h-3 w-3" /> Back to Settings
        </Link>
      </div>

      <Header
        title="Capability Policies & Verification Matrix"
        description="Configure proof policies (Open, Optional, Required) and document rules for individuals and companies."
        adminName={adminProfile?.full_name}
      />

      {/* Explanation Banner */}
      <Card className="bg-paper-100 border-paper-300">
        <CardContent className="pt-5 pb-5 text-xs text-ink-700 space-y-1">
          <p className="font-semibold text-ink-900">Verification Policies (VERIFICATION_SPEC.md):</p>
          <ul className="list-disc pl-5 space-y-0.5">
            <li><strong>Open (No proof required):</strong> Capability is immediately active. No document uploads asked.</li>
            <li><strong>Optional Proof:</strong> Active upon selection. Proof can be uploaded later to earn the verified provider badge.</li>
            <li><strong>Required Proof:</strong> Inactive until admin reviews and approves valid evidence. Server blocks offers while inactive.</li>
          </ul>
        </CardContent>
      </Card>

      {/* Capability Catalog Table */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
            <SlidersHorizontal className="h-4 w-4" /> Capability Policy Catalog
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Category</TableHead>
                <TableHead>Capability</TableHead>
                <TableHead>Slug</TableHead>
                <TableHead>Current Policy</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="w-[280px]">Adjust Policy</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {!capabilities?.length ? (
                <TableRow>
                  <TableCell colSpan={6} className="py-6 text-center text-xs text-ink-500">
                    No capabilities catalog found.
                  </TableCell>
                </TableRow>
              ) : (
                capabilities.map((cap) => (
                  <TableRow key={cap.slug}>
                    <TableCell className="font-medium text-ink-900">
                      {cap.need_categories?.icon} {cap.need_categories?.name || cap.category_slug}
                    </TableCell>
                    <TableCell className="font-medium text-ink-900">
                      {cap.name}
                    </TableCell>
                    <TableCell className="font-mono text-xs text-ink-500">
                      {cap.slug}
                    </TableCell>
                    <TableCell>
                      <Badge
                        variant={
                          cap.verification_policy === "required_proof"
                            ? "alert"
                            : cap.verification_policy === "optional_proof"
                            ? "signal"
                            : "neutral"
                        }
                        className="capitalize"
                      >
                        {cap.verification_policy.replace(/_/g, " ")}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <Badge variant={cap.is_active ? "confirm" : "neutral"}>
                        {cap.is_active ? "Enabled" : "Disabled"}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <CapabilityPolicyEditor
                        slug={cap.slug}
                        currentPolicy={cap.verification_policy}
                        isActive={cap.is_active}
                      />
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Verification Matrix Rules */}
      {requirements && requirements.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-semibold text-ink-900 flex items-center gap-2">
              <ShieldCheck className="h-4 w-4" /> Active Verification Requirements Matrix
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Scope</TableHead>
                  <TableHead>Target Slug</TableHead>
                  <TableHead>Provider Type</TableHead>
                  <TableHead>Required Evidence Keys</TableHead>
                  <TableHead>Expiry (Days)</TableHead>
                  <TableHead>Active</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {requirements.map((req) => (
                  <TableRow key={`${req.scope_type}-${req.scope_id}-${req.provider_type}`}>
                    <TableCell className="text-xs capitalize font-medium text-ink-900">
                      {req.scope_type}
                    </TableCell>
                    <TableCell className="font-mono text-xs text-ink-700">
                      {req.scope_id}
                    </TableCell>
                    <TableCell className="text-xs capitalize text-ink-700">
                      {req.provider_type}
                    </TableCell>
                    <TableCell className="text-xs font-mono text-ink-600">
                      {req.required_evidence?.length ? req.required_evidence.join(", ") : "supporting_document"}
                    </TableCell>
                    <TableCell className="text-xs text-ink-700">
                      {req.expires_after_days ? `${req.expires_after_days} days` : "No expiry"}
                    </TableCell>
                    <TableCell>
                      <Badge variant={req.is_active ? "confirm" : "neutral"}>
                        {req.is_active ? "Active" : "Inactive"}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

