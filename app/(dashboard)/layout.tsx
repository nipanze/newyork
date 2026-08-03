import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/sidebar";

export default async function DashboardGroupLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("is_admin, full_name")
    .eq("id", user.id)
    .single();

  if (!profile?.is_admin) redirect("/login?error=not_admin");

  return (
    <div className="flex min-h-screen bg-paper-50">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">{children}</div>
    </div>
  );
}
