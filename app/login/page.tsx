"use client";

import { useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const notAdmin = searchParams.get("error") === "not_admin";

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const supabase = createClient();
    const { data, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (signInError) {
      setError(signInError.message);
      setLoading(false);
      return;
    }

    // Confirm admin access before routing into the dashboard — the RLS
    // policy on `profiles` lets a user read their own row regardless of
    // is_admin, so this check runs client-side too for a fast redirect;
    // middleware.ts enforces the real gate on every subsequent request.
    const { data: profile } = await supabase
      .from("profiles")
      .select("is_admin")
      .eq("id", data.user.id)
      .single();

    if (!profile?.is_admin) {
      await supabase.auth.signOut();
      setError("This account does not have admin access to Nipanze Dashboard.");
      setLoading(false);
      return;
    }

    router.push(searchParams.get("next") || "/dashboard");
    router.refresh();
  }

  return (
    <Card className="w-full max-w-sm">
      <CardHeader>
        <div className="mb-2 flex h-8 w-8 items-center justify-center rounded-md bg-amber-signal text-sm font-bold text-ink-950">
          N
        </div>
        <CardTitle className="text-lg">Sign in to Nipanze Dashboard</CardTitle>
        <CardDescription>Admin access only — same account as the Nipanze mobile app.</CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@nipanze.ug"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
            />
          </div>

          {(error || notAdmin) && (
            <p className="rounded-md bg-clay-alert-soft px-3 py-2 text-xs text-clay-alert">
              {error || "This account does not have admin access."}
            </p>
          )}

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Signing in…" : "Sign in"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-ink-950 px-4">
      <Suspense fallback={null}>
        <LoginForm />
      </Suspense>
    </main>
  );
}
