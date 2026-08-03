import { createClient } from "@/lib/supabase/server";
import { Header } from "@/components/header";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { ArrowLeftRight } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function ForexPage() {
  const supabase = await createClient();

  // forex_requests / forex_offers ship in Stage 4.7 (see BUILD_PLAN.md).
  // This queries defensively so the page still renders cleanly against a
  // database that hasn't run that migration yet.
  const { data: forexRequests, error } = await supabase
    .from("forex_requests" as never)
    .select("*")
    .limit(50);

  return (
    <>
      <Header title="Forex" description="Peer-to-peer currency exchange requests" />
      <main className="flex-1 space-y-4 overflow-y-auto p-6">
        {error || !forexRequests ? (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <ArrowLeftRight className="h-4 w-4" /> Forex module not active yet
              </CardTitle>
              <CardDescription>
                This market's Supabase project hasn't run the Stage 4.7 migration
                (`forex_requests` / `forex_offers`, `countries.forex_enabled`,
                `currencies.forex_trading_enabled`). Once it has, this page will list
                forex requests the same way the Loans page lists loan requests.
              </CardDescription>
            </CardHeader>
            <CardContent className="pt-0 text-sm text-ink-500">
              Nothing to configure here — apply the migration in the mobile project's
              `sql/migrations/` directory, then reload.
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardHeader>
              <CardTitle>Forex requests</CardTitle>
            </CardHeader>
            <CardContent className="pt-0 text-sm text-ink-500">
              {forexRequests.length} request(s) found.
            </CardContent>
          </Card>
        )}
      </main>
    </>
  );
}
