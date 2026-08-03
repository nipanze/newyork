import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

// Supabase uses Node.js-only APIs (e.g. process.version) that are not
// available in the default Edge Runtime. Switching to the Node.js runtime
// removes the build warning and ensures the middleware works on Vercel.
export const runtime = "nodejs";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
