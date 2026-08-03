# Nipanze Dashboard

Admin control console for the Nipanze non-custodial lending & forex marketplace — manages
accounts, KYC review, loan/forex listings, transactions, the audit trail, per-market settings,
and market activation. Shares the same Supabase project (and therefore the same accounts) as
the Flutter mobile app.

| Component | Technology |
|---|---|
| Frontend | Next.js 14 (App Router), React, TypeScript |
| Styling | Tailwind CSS v4 + hand-rolled shadcn-style primitives (`components/ui`) |
| Backend | Next.js API Routes (TypeScript) |
| Database | Supabase (PostgreSQL) — same cloud project as the mobile app |
| Auth | Supabase Auth, gated to `profiles.is_admin = TRUE` |
| Deployment | Vercel + GitHub |

## Getting started

```bash
npm install
cp .env.example .env.local   # fill in your Supabase project URL + keys
npm run dev
```

Open http://localhost:3000 — you'll be redirected to `/login`.

### Requirements

- Node.js 18.18+
- A Supabase project already running `sql/schema.sql` and `sql/seed.sql` from the Flutter
  project (this dashboard doesn't own the schema — it's a client of it)
- At least one seeded account with `profiles.is_admin = TRUE` (the seed data ships with
  `admin1@nipanze.ug` / `admin2@nipanze.ug`, password `Test1234!`)

## Environment variables

See `.env.example`.

- `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` — used by the browser and by
  Server Components/Route Handlers for anything that should respect RLS (which is almost
  everything reads in this app).
- `SUPABASE_SERVICE_ROLE_KEY` — server-only, used exclusively inside `app/api/admin/**/route.ts`
  handlers for the handful of writes an admin needs that RLS otherwise blocks (updating
  someone else's `profiles` row, approving KYC, toggling a country). Every one of those route
  handlers calls `requireAdmin()` first — the service-role key never runs unchecked.

## How access control works

1. `middleware.ts` refreshes the Supabase session on every request and redirects
   unauthenticated visitors to `/login`, and non-admins back to `/login?error=not_admin`.
2. `app/(dashboard)/layout.tsx` re-checks `profiles.is_admin` server-side before rendering any
   dashboard route, as defense in depth.
3. Every mutating API route calls `requireAdmin()` (`lib/supabase/require-admin.ts`) before
   touching the service-role client.

`is_admin` is the only role concept in the schema — there's no separate "dashboard user" table.
Any Nipanze account can be promoted via the Accounts → Manage → "Grant admin access" action (or
directly in Supabase).

## Project structure

```
app/
  login/                     Sign-in page (Supabase Auth)
  auth/callback/             OAuth/magic-link callback route
  (dashboard)/               Everything behind the admin gate
    dashboard/                Overview — KPIs, recent listings
    users/                    Accounts list + detail (status, admin role)
    loans/                    Loan listings list + detail (request + offers)
    forex/                    Forex listings (placeholder until Stage 4.7 migration ships)
    kyc/                      KYC review queue — approve / reject
    transactions/             Nipanze's own revenue records (Stage 6)
    audit-logs/               Read-only compliance trail
    countries/                Per-market lending/forex activation toggles
    settings/                 system_settings — global + per-country overrides
  api/admin/                 Route handlers backing the mutating actions above
components/
  ui/                        Button, Card, Input, Label, Badge, Table primitives
  sidebar.tsx, header.tsx, stat-card.tsx, logout-button.tsx
  account-actions.tsx, kyc-review-actions.tsx, country-toggles.tsx, setting-row.tsx
lib/
  supabase/                  client.ts (browser), server.ts (RSC), admin.ts (service-role),
                              middleware.ts, require-admin.ts
  types.ts                   Hand-written Database types (swap for generated types any time)
  utils.ts                   cn(), formatAmount(), formatDate(), formatDateTime(), initials()
```

## Design notes

Sidebar in dark "ink" tones, workspace in warm "paper" tones, with an amber accent reserved for
attention states (pending KYC, needs review) and teal for confirmed/active states. Numeric and
currency values use `font-tabular` (DM Mono), matching the tabular-figure convention already
used in the Flutter app, so the two surfaces read as one product.

## Extending

- **Generate real Supabase types**: `npx supabase gen types typescript --project-id <ref> >
  lib/types.ts` once you're ready to move off the hand-written subset in this scaffold.
- **Forex module**: `app/(dashboard)/forex/page.tsx` already queries `forex_requests`
  defensively — once your project runs the Stage 4.7 migration, it'll start listing rows with
  no further changes needed beyond styling it like the Loans page.
- **shadcn/ui CLI**: the primitives in `components/ui` are hand-written to match shadcn's API
  shape closely enough that you can drop in `npx shadcn@latest add <component>` for anything
  beyond Button/Card/Input/Label/Badge/Table without conflicts.
