# BUILD_PLAN.md — Nipanze Admin Portal

> **Repo**: Next.js + Supabase admin/control portal  
> **Related client docs**: [README_Android.md](README_Android.md), [BUILD_PLAN_android.md](BUILD_PLAN_android.md)  
> **Current focus**: Build complete admin controls, starting with Overview and Accounts  
> **Updated**: August 12, 2026

## 1. Purpose

This file is the technical build plan for the Nipanze admin portal.

The Android files describe the user/client marketplace app. This repo is the control portal for that
same platform. Its job is to let admins view, filter, search, moderate, configure, and audit every
important part of Nipanze without breaking the core product boundary: Nipanze is a non-custodial
marketplace and does not hold, move, lend, repay, or exchange user funds.

This plan tracks:

- the current admin dashboard implementation
- missing search/filter/control features
- the stage-by-stage dashboard roadmap
- the data access and security rules needed for admin operations
- the first build priority: Overview, then Accounts

## 2. Product Position

Nipanze has two connected surfaces:

| Surface | Repo/docs | Purpose |
|---|---|---|
| Client marketplace | `README_Android.md`, `BUILD_PLAN_android.md` | Users post loan/forex requests, make offers, complete KYC, accept deals |
| Admin portal | `README.md`, this file | Admins control accounts, KYC, listings, markets, pricing, settings, transactions, and audit logs |

Both surfaces share:

- one Supabase project
- one account model
- one `profiles` table
- one `subscription_plan` model
- one admin authority flag: `profiles.is_admin = TRUE`

## 3. Current Implementation Snapshot

### 3.1 Stack

- Next.js 14 App Router
- React 18
- TypeScript
- Tailwind CSS v4
- Supabase Auth and PostgreSQL
- Server Components for dashboard reads
- Route Handlers for admin mutations
- `lucide-react` icons
- local UI primitives in `components/ui`

### 3.2 Existing dashboard routes

- `/dashboard` — overview KPIs and recent listings
- `/users` — accounts list
- `/users/[id]` — account detail
- `/kyc` — KYC review queue
- `/kyc/[id]` — KYC detail
- `/loans` — loan listing oversight
- `/loans/[id]` — loan detail
- `/forex` — forex listing oversight
- `/forex/[id]` — forex detail
- `/countries` — market toggles and subscription pricing
- `/settings` — global/per-market settings
- `/transactions` — platform revenue records
- `/audit-logs` — compliance/event trail

### 3.3 Existing admin controls

- login through Supabase Auth
- dashboard access gated by `profiles.is_admin`
- KYC approval/rejection components
- country lending/forex toggles
- subscription pricing manager
- settings row editor
- account action controls
- loan/forex list and detail pages
- audit and transaction pages

### 3.4 Known gaps

- Accounts search only supports a basic name filter.
- Admins need search by name, phone number, email, country, plan, KYC status, account status, and admin status.
- Email lives in Supabase Auth, so account search needs a secure admin-only API/RPC/view path.
- Overview needs richer control widgets and drill-down filters.
- KYC needs stronger filtering and review controls.
- Loans and Forex need admin moderation controls per listing.
- Audit logs need better actor/target/event/date filtering.
- Every admin mutation should create or connect to an audit trail.
- List pages need consistent pagination and clear filter reset behavior.

## 4. Build Principles

1. **Admin is a control plane, not a financial back office.**  
   Admins moderate and configure the marketplace. They do not process peer-to-peer loan funds,
   repayments, settlements, or currency exchanges.

2. **Every filter lives in the URL.**  
   Search, country filters, status filters, pagination, and date ranges should use query params so
   pages are refresh-safe and shareable.

3. **Use server-side reads by default.**  
   Dashboard pages should query Supabase from Server Components where possible.

4. **Use service role only after admin verification.**  
   Mutating route handlers may use `SUPABASE_SERVICE_ROLE_KEY`, but only after `requireAdmin()`.

5. **Email search must be admin-only.**  
   User emails should not be exposed through public profile queries. Use an admin API/RPC/view
   designed for dashboard account search.

6. **Controls must be visible at the point of decision.**  
   Account controls belong on account pages, KYC controls on KYC pages, listing controls on listing
   pages, and market controls on market pages.

7. **Audit important admin actions.**  
   Suspending accounts, approving KYC, rejecting KYC, changing plans, toggling markets, editing
   settings, and moderating listings should leave an audit record.

## 5. Stage Summary

| Stage | Title | Status | Goal |
|---|---|---|---|
| 0 | Baseline Alignment | Complete | README defines this repo as the admin portal |
| 1 | Shared Filter/Search Foundation | Planned | Reusable URL-driven filters and pagination |
| 2 | Overview Control Center | Planned | Rich dashboard with KPIs, filters, queues, and drill-down links |
| 3 | Accounts Control Center | Planned | Search by name/phone/email and manage user state |
| 4 | KYC Control Center | Planned | Full KYC review, filtering, rejection reasons, and audit trail |
| 5 | Loan Moderation | Planned | Listing/offer visibility and moderation controls |
| 6 | Forex Moderation | Planned | Forex request/offer oversight and market/currency checks |
| 7 | Markets, Pricing, Settings | Planned | Complete market activation, price, currency, and setting controls |
| 8 | Transactions & Audit Logs | Planned | Better revenue and compliance search/filter/reporting |
| 9 | Hardening & Launch Readiness | Planned | Tests, security pass, performance, pagination, deployment checks |

## 6. Stage 1 — Shared Filter/Search Foundation

### Goal

Create reusable dashboard filtering patterns so every page can search and filter consistently.

### Build items

- [ ] Create reusable filter components:
  - [ ] text search input
  - [ ] country selector
  - [ ] status selector
  - [ ] plan selector
  - [ ] KYC status selector
  - [ ] admin status selector
  - [ ] date range fields
  - [ ] clear filters button
- [ ] Create URL query helpers for:
  - [ ] reading params safely
  - [ ] applying defaults
  - [ ] building filtered links
  - [ ] preserving params during pagination
- [ ] Add shared pagination component.
- [ ] Standardize empty states for filtered list pages.
- [ ] Standardize loading/error states where client-side actions are used.

### Exit criteria

- Filter state survives refresh.
- Filter URLs can be shared.
- Accounts, KYC, Loans, Forex, Transactions, and Audit Logs can reuse the same pattern.

## 7. Stage 2 — Overview Control Center

### Goal

Make `/dashboard` the main admin command center.

### Filters

- [ ] country
- [ ] date range
- [ ] module: `All`, `Loans`, `Forex`

### KPI cards

- [ ] total accounts
- [ ] active accounts
- [ ] suspended accounts
- [ ] pending KYC submissions
- [ ] approved KYC submissions
- [ ] active loan listings
- [ ] active forex requests
- [ ] active markets
- [ ] forex-enabled markets
- [ ] subscriptions by plan

### Dashboard sections

- [ ] latest registered users
- [ ] latest pending KYC submissions
- [ ] latest loan listings
- [ ] latest forex requests
- [ ] recent audit log entries
- [ ] markets needing attention

### Controls

- [ ] quick link to filtered Accounts
- [ ] quick link to filtered KYC queue
- [ ] quick link to filtered Loans
- [ ] quick link to filtered Forex
- [ ] quick link to Countries/Pricing
- [ ] quick link to Audit Logs

### Exit criteria

- Admin can open the dashboard and immediately see what needs attention.
- Every dashboard section links to the relevant filtered work page.

## 8. Stage 3 — Accounts Control Center

### Goal

Make `/users` and `/users/[id]` the complete account control surface.

### Account list filters

- [ ] name
- [ ] phone number
- [ ] email
- [ ] country
- [ ] account status
- [ ] subscription plan
- [ ] KYC status
- [ ] admin status
- [ ] joined date range

### Account table columns

- [ ] name
- [ ] email
- [ ] phone
- [ ] country
- [ ] plan
- [ ] KYC status
- [ ] account status
- [ ] admin badge
- [ ] joined date
- [ ] last activity where available
- [ ] actions

### Backend/data work

- [ ] Add admin-only account search endpoint or RPC.
- [ ] Include email from Supabase Auth safely.
- [ ] Join active subscription plan.
- [ ] Join latest KYC status.
- [ ] Support pagination and count.
- [ ] Prevent non-admin access to email search.

### Account controls

- [ ] view full profile
- [ ] suspend account
- [ ] reactivate account
- [ ] deactivate account
- [ ] grant admin access
- [ ] revoke admin access
- [ ] change subscription plan
- [ ] view user's KYC record
- [ ] view user's loan requests
- [ ] view user's forex requests
- [ ] view user's offers
- [ ] view user's audit logs

### Account detail page

- [ ] profile summary
- [ ] contact information
- [ ] account status controls
- [ ] admin access controls
- [ ] subscription panel
- [ ] KYC summary
- [ ] loan request history
- [ ] forex request history
- [ ] offer history
- [ ] transaction history
- [ ] audit trail

### Exit criteria

- Admin can find a user by name, phone number, or email.
- Admin can understand and control that user from one detail page.
- High-impact changes create audit records.

## 9. Stage 4 — KYC Control Center

### Goal

Give admins a complete KYC review workflow.

### KYC filters

- [ ] applicant name
- [ ] phone number
- [ ] email
- [ ] country
- [ ] status
- [ ] document type
- [ ] submitted date range

### KYC controls

- [ ] approve submission
- [ ] reject submission with required reason
- [ ] mark expired
- [ ] view front document
- [ ] view back document
- [ ] view selfie
- [ ] open linked account detail
- [ ] show prior rejection reason
- [ ] show review timestamp and reviewer

### Exit criteria

- Admin can review KYC without leaving the KYC flow.
- Every KYC status change writes an audit event.

## 10. Stage 5 — Loan Moderation

### Goal

Give admins visibility and control over loan listings and offers.

### Loan filters

- [ ] title/search text
- [ ] borrower name
- [ ] borrower phone
- [ ] borrower email
- [ ] country
- [ ] status
- [ ] amount range
- [ ] listed date range
- [ ] number of offers
- [ ] borrower KYC status

### Loan controls

- [ ] view listing detail
- [ ] view borrower profile
- [ ] inspect offers
- [ ] view accepted offer state
- [ ] view contact reveal state where applicable
- [ ] cancel/moderate listing
- [ ] mark suspicious or needs review
- [ ] write audit event for moderation

### Exit criteria

- Admin can locate and inspect risky or disputed loan activity.
- Admin can moderate listings without touching user-to-user funds.

## 11. Stage 6 — Forex Moderation

### Goal

Give admins visibility and control over forex requests and offers after Stage 4.7 schema support.

### Forex filters

- [ ] requester name
- [ ] requester phone
- [ ] requester email
- [ ] country
- [ ] currency held
- [ ] currency needed
- [ ] status
- [ ] amount range
- [ ] preferred rate range
- [ ] listed date range

### Forex controls

- [ ] view forex request detail
- [ ] inspect offers
- [ ] view requester profile
- [ ] verify country forex enablement
- [ ] verify currency trading enablement
- [ ] cancel/moderate request
- [ ] write audit event for moderation

### Exit criteria

- Admin can supervise forex activity by country and currency pair.
- Disabled markets/currencies cannot silently appear active.

## 12. Stage 7 — Markets, Pricing, Settings

### Goal

Make operational configuration safe, visible, and auditable.

### Markets

- [ ] toggle lending active per country
- [ ] toggle forex enabled per country
- [ ] show currency and phone prefix
- [ ] show launch/readiness status
- [ ] show listing/user counts per market

### Subscription pricing

- [ ] edit Free/Lender/Pro pricing by country
- [ ] validate currency and amount
- [ ] show last updated timestamp
- [ ] audit pricing changes

### Settings

- [ ] edit global settings
- [ ] edit per-country overrides
- [ ] type-aware controls for boolean/number/string/json
- [ ] JSON validation before submit
- [ ] audit setting changes

### Exit criteria

- Admin can control market launch state and pricing safely.
- Every configuration change is traceable.

## 13. Stage 8 — Transactions & Audit Logs

### Goal

Improve operational reporting and compliance review.

### Transaction filters

- [ ] user name
- [ ] user phone
- [ ] user email
- [ ] country
- [ ] plan
- [ ] status
- [ ] provider reference
- [ ] amount range
- [ ] date range

### Audit filters

- [ ] actor
- [ ] target user
- [ ] event type
- [ ] country
- [ ] date range
- [ ] admin-only events

### Exit criteria

- Admin can trace what happened, who did it, and which user/listing/market was affected.

## 14. Stage 9 — Hardening & Launch Readiness

### Security

- [ ] Confirm every dashboard route is admin-gated.
- [ ] Confirm every mutating route calls `requireAdmin()`.
- [ ] Confirm service-role key is never imported into client components.
- [ ] Confirm email search is admin-only.
- [ ] Confirm KYC documents are not publicly exposed.

### Reliability

- [ ] Add pagination to heavy list pages.
- [ ] Add graceful errors for missing optional Forex tables.
- [ ] Add optimistic UI only where rollback is clear.
- [ ] Add server-side validation to every mutation.

### Testing

- [ ] Build check passes.
- [ ] Lint passes or documented lint gaps are fixed.
- [ ] Manual admin flow smoke test:
  - [ ] login
  - [ ] overview
  - [ ] account search by name
  - [ ] account search by phone
  - [ ] account search by email
  - [ ] KYC approve/reject
  - [ ] market toggle
  - [ ] pricing update
  - [ ] settings update
  - [ ] audit log review

## 15. Immediate Next Build Order

1. Add shared filter utilities and small reusable filter controls.
2. Upgrade `/dashboard` with richer KPIs and drill-down sections.
3. Build the admin-only account search data path that supports email.
4. Upgrade `/users` filters and pagination.
5. Upgrade `/users/[id]` into a complete control page.
6. Extend the same filter/control pattern to KYC.

## 16. Definition of Done for First Milestone

The first milestone is complete when:

- `/dashboard` shows meaningful overview metrics and attention queues.
- `/users` can filter by name, phone number, email, country, status, plan, KYC, and admin state.
- `/users/[id]` lets admins view and control the important parts of an account.
- Admin-only email access is handled safely.
- Account status/admin/plan changes are protected by `requireAdmin()`.
- Important admin actions write audit records or have a clear audit implementation path.
