# Nipanze Admin Portal

Control dashboard for the Nipanze non-custodial lending and forex marketplace.

This repository is the **admin/control portal** for the client-facing Flutter app described in
[README_Android.md](README_Android.md) and tracked in
[BUILD_PLAN_android.md](BUILD_PLAN_android.md). The Android app is where users post loan or forex
requests, browse the marketplace, make offers, complete KYC, and accept deals. This Next.js app is
where Nipanze operators supervise that same platform: accounts, KYC, markets, pricing, listings,
settings, transactions, and audit trails.

Nipanze does not hold funds, pool capital, issue loans, convert currency, or move money between
users. The admin portal must preserve that boundary: it moderates the marketplace and controls
platform configuration, but it is not a banking, lending, escrow, or bureau-de-change back office.

## Platform Relationship

| Surface | Purpose | Primary users |
|---|---|---|
| Flutter Android app | Public marketplace for loan and forex requests/offers | Clients, borrowers, lenders, forex participants |
| This Next.js portal | Internal control plane for marketplace operations | Admins, support, compliance, operations |
| Supabase project | Shared auth, database, storage, RLS, and operational data | Both apps |

The two apps share one account model, one Supabase project, and one database schema. Marketplace
capability is controlled by `subscription_plan`; operational authority is controlled only by
`profiles.is_admin = TRUE`.

## What This Portal Controls

- **Overview**: platform KPIs, recent listings, active market count, pending KYC count.
- **Accounts**: user lookup, account status, country, subscription plan, and admin access.
- **KYC review**: pending identity submissions, document viewing, approval, and rejection.
- **Loans**: loan listing oversight, request detail, offer visibility, and listing status review.
- **Forex**: forex request oversight once the Stage 4.7 schema is applied.
- **Markets & pricing**: country activation, forex enablement, and subscription pricing by market.
- **Settings**: global and per-country `system_settings` overrides.
- **Transactions**: Nipanze revenue records for subscriptions and future platform fees only.
- **Audit logs**: read-only compliance and admin activity trail.

## Product Context

The Android planning files define Nipanze as one marketplace with two modules:

- **Loans**: structured loan requests and lender offers.
- **Forex**: peer-to-peer currency exchange requests and offers.

The launch market is Uganda, with expansion planned for Kenya, Tanzania, Rwanda, Nigeria, South
Africa, and Egypt. Each market can be activated independently for lending and forex. This portal is
the operational place where those switches and local subscription prices are managed.

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 14 App Router, React, TypeScript |
| Styling | Tailwind CSS v4, local shadcn-style primitives in `components/ui` |
| Icons | `lucide-react` |
| Backend | Next.js Route Handlers |
| Database/Auth | Supabase PostgreSQL + Supabase Auth |
| Deployment target | Vercel or any Node-compatible Next.js host |

## Getting Started

Requirements:

- Node.js 18.18+
- npm
- A Supabase project with the Nipanze schema and seed/patch SQL applied
- At least one account where `profiles.is_admin = TRUE`

Install and run:

```bash
npm install
npm run dev
```

Open `http://localhost:3000`. Unauthenticated users are redirected to `/login`; authenticated
non-admin users are rejected by the admin gate.

## Environment Variables

Create `.env.local` with:

```bash
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
```

`NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are used by browser/server Supabase
clients for normal RLS-aware reads. `SUPABASE_SERVICE_ROLE_KEY` is server-only and is used only in
admin API routes after `requireAdmin()` confirms the current user is an admin.

## Access Control

Admin access is enforced in three layers:

1. `middleware.ts` refreshes the Supabase session and redirects unauthenticated users.
2. `app/(dashboard)/layout.tsx` checks `profiles.is_admin` before rendering dashboard routes.
3. Mutating routes under `app/api/admin/**` call `requireAdmin()` before using the service-role
   Supabase client.

There is no separate dashboard-user table. Admins are normal Nipanze accounts with
`profiles.is_admin = TRUE`.

## Repo Structure

```text
app/
  login/                     Admin login
  auth/callback/             Supabase auth callback
  (dashboard)/               Protected admin workspace
    dashboard/                KPIs and recent marketplace activity
    users/                    Account list and account detail
    kyc/                      Identity review queue and detail
    loans/                    Loan listings and detail
    forex/                    Forex listing oversight
    countries/                Market activation and subscription pricing
    settings/                 Global and per-market settings
    transactions/             Platform revenue records
    audit-logs/               Compliance/event trail
  api/admin/                 Admin-only mutating route handlers
components/                  Dashboard UI and action components
lib/supabase/                Browser, server, middleware, admin, and guard clients
lib/types.ts                 Hand-maintained Supabase type subset
sql/                         Schema, seed, and feature patches
sqlx/                        Extra SQL patch copies/working SQL
README_Android.md            Client-facing Flutter product README
BUILD_PLAN_android.md        Client app technical plan and stage log
```

## Database Notes

The portal expects the same Supabase schema used by the Android app. Important tables include:

- `profiles`, `subscriptions`, `subscription_prices`
- `countries`, `currencies`, `system_settings`
- `loan_requests`, `loan_offers`
- `forex_requests`, `forex_offers`
- `kyc_verifications`
- `transactions`, `audit_logs`

Some screens query newer tables defensively. For example, the Forex page displays a migration
message if `forex_requests` is not present yet. Apply the relevant SQL patches in `sql/` as stages
are enabled.

## Admin Boundary

Admin actions should remain limited to platform governance:

- approving/rejecting KYC
- suspending/reactivating accounts
- granting/revoking admin access
- toggling market availability
- managing subscription pricing and settings
- reviewing listings, audit logs, and platform revenue records

Admin actions must not create hidden custodial behavior. User-to-user lending, repayment,
settlement, and currency exchange happen outside Nipanze after controlled contact reveal.

## Scripts

```bash
npm run dev      # local development
npm run build    # production build
npm run start    # serve production build
npm run lint     # lint command configured by package.json
```

## Current Alignment With Android Plan

This portal maps to Stage 5, **Admin & Compliance**, from
[BUILD_PLAN_android.md](BUILD_PLAN_android.md). It also supports the active Stage 4.5 and Stage 4.7
work by exposing market toggles, subscription pricing, settings, loan oversight, and forex oversight.

When the Android app adds or changes marketplace behavior, update this README and the dashboard
screens so the admin portal remains the operational source of control for the same shared platform.
