# BUILD_PLAN.md — Nipanze Admin Portal

> **Repo**: Next.js + Supabase admin/control portal  
> **Related client docs**: [README_Android.md](README_Android.md), [BUILD_PLAN_android.md](BUILD_PLAN_android.md)  
> **Current focus**: Marketer / Referral Department
> **Updated**: August 16, 2026

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
- `/marketers` — marketer/referral department overview
- `/marketers/users` — marketer roster
- `/marketers/users/[id]` — marketer detail and controls
- `/marketers/referrals` — referral attribution and review
- `/marketers/referrals/[id]` — referral detail
- `/marketers/rewards` — referral reward queue
- `/marketers/payouts` — marketer payout workflow
- `/marketers/campaigns` — campaign rules and status controls
- `/marketers/risk` — fraud/risk review queue

### 3.3 Existing admin controls

- login through Supabase Auth
- dashboard access gated by `profiles.is_admin`
- KYC approval/rejection components
- country lending/forex toggles
- subscription pricing manager
- settings row editor
- account action controls
- loan/forex list and detail pages
- marketer/referral department pages and status controls
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
| 1 | Shared Filter/Search Foundation | In progress | Reusable URL-driven filters and pagination |
| 2 | Overview Control Center | In progress | Rich dashboard with KPIs, filters, queues, and drill-down links |
| 3 | Accounts Control Center | In progress | Search by name/phone/email and manage user state |
| 4 | KYC Control Center | Planned | Full KYC review, filtering, rejection reasons, and audit trail |
| 5 | Loan Moderation | Planned | Listing/offer visibility and moderation controls |
| 6 | Forex Moderation | Planned | Forex request/offer oversight and market/currency checks |
| 7 | Markets, Pricing, Settings | Planned | Complete market activation, price, currency, and setting controls |
| 8 | Transactions & Audit Logs | Planned | Better revenue and compliance search/filter/reporting |
| 9 | Marketer / Referral Department | In progress | Referral agents, campaigns, rewards, payouts, risk, and analytics |
| 10 | Hardening & Launch Readiness | Planned | Tests, security pass, performance, pagination, deployment checks |

## 6. Stage 1 — Shared Filter/Search Foundation

### Goal

Create reusable dashboard filtering patterns so every page can search and filter consistently.

### Build items

- [x] Create reusable filter components:
  - [x] text search input
  - [x] country selector
  - [x] status selector
  - [x] plan selector
  - [x] KYC status selector
  - [x] admin status selector
  - [x] date range fields
  - [x] clear filters button
- [x] Create URL query helpers for:
  - [x] reading params safely
  - [x] applying defaults
  - [x] building filtered links
  - [x] preserving params during pagination
- [x] Add shared pagination component.
- [x] Standardize empty states for filtered list pages.
- [x] Standardize loading/error states where client-side actions are used.

### Exit criteria

- Filter state survives refresh.
- Filter URLs can be shared.
- Accounts, KYC, Loans, Forex, Transactions, and Audit Logs can reuse the same pattern.

## 7. Stage 2 — Overview Control Center

### Goal

Make `/dashboard` the main admin command center.

### Filters

- [x] country
- [x] date range
- [x] module: `All`, `Loans`, `Forex`

### KPI cards

- [x] total accounts
- [x] active accounts
- [x] suspended accounts
- [x] pending KYC submissions
- [x] approved KYC submissions
- [x] active loan listings
- [x] active forex requests
- [x] active markets
- [x] forex-enabled markets
- [x] subscriptions by plan
- [x] active marketers
- [x] referrals this month
- [x] qualified referrals this month
- [x] pending marketer payouts

### Dashboard sections

- [x] latest registered users
- [x] latest pending KYC submissions
- [x] latest loan listings
- [x] latest forex requests
- [x] recent audit log entries
- [x] markets needing attention

### Controls

- [x] quick link to filtered Accounts
- [x] quick link to filtered KYC queue
- [x] quick link to filtered Loans
- [x] quick link to filtered Forex
- [x] quick link to Countries/Pricing
- [x] quick link to Audit Logs
- [x] quick link to Marketer Department

### Exit criteria

- Admin can open the dashboard and immediately see what needs attention.
- Every dashboard section links to the relevant filtered work page.

## 8. Stage 3 — Accounts Control Center

### Goal

Make `/users` and `/users/[id]` the complete account control surface.

### Account list filters

- [x] name
- [x] phone number
- [x] email
- [x] country
- [x] account status
- [x] subscription plan
- [x] KYC status
- [x] admin status
- [x] joined date range

### Account table columns

- [x] name
- [x] email
- [x] phone
- [x] country
- [x] plan
- [x] KYC status
- [x] account status
- [x] admin badge
- [x] joined date
- [ ] last activity where available
- [x] actions

### Backend/data work

- [x] Add admin-only account search endpoint or RPC.
- [x] Include email from Supabase Auth safely.
- [x] Join active subscription plan.
- [x] Join latest KYC status.
- [x] Support pagination and count.
- [x] Prevent non-admin access to email search.

### Account controls

- [x] view full profile
- [x] suspend account
- [x] reactivate account
- [x] deactivate account
- [x] grant admin access
- [x] revoke admin access
- [x] change subscription plan
- [x] view user's KYC record
- [x] view user's loan requests
- [x] view user's forex requests
- [x] view user's offers
- [x] view user's audit logs

### Account detail page

- [x] profile summary
- [x] contact information
- [x] account status controls
- [x] admin access controls
- [x] subscription panel
- [x] KYC summary
- [x] loan request history
- [x] forex request history
- [x] offer history
- [x] transaction history
- [x] audit trail

### Exit criteria

- Admin can find a user by name, phone number, or email.
- Admin can understand and control that user from one detail page.
- High-impact changes create audit records.

## 9. Stage 4 — KYC Control Center

### Goal

Give admins a complete KYC review workflow.

### KYC filters

- [x] applicant name
- [x] phone number
- [x] email
- [x] country
- [x] status
- [x] document type
- [x] submitted date range

### KYC controls

- [x] approve submission
- [x] reject submission with required reason
- [x] mark expired
- [x] view front document
- [x] view back document
- [x] view selfie
- [x] open linked account detail
- [x] show prior rejection reason
- [x] show review timestamp and reviewer

### Exit criteria

- Admin can review KYC without leaving the KYC flow.
- Every KYC status change writes an audit event.

## 10. Stage 5 — Loan Moderation

### Goal

Give admins visibility and control over loan listings and offers.

### Loan filters

- [x] title/search text
- [x] borrower name
- [x] borrower phone
- [x] country
- [x] status
- [x] listed date range

### Loan controls

- [x] view listing detail
- [x] view borrower profile
- [x] inspect offers
- [x] cancel/moderate listing
- [x] mark suspicious or needs review
- [x] write audit event for moderation

### Exit criteria

- Admin can locate and inspect risky or disputed loan activity.
- Admin can moderate listings without touching user-to-user funds.

## 11. Stage 6 — Forex Moderation

### Goal

Give admins visibility and control over forex requests and offers after Stage 4.7 schema support.

### Forex filters

- [x] requester name
- [x] requester phone
- [x] country
- [x] currency held
- [x] currency needed
- [x] status
- [x] listed date range

### Forex controls

- [x] view forex request detail
- [x] inspect offers
- [x] view requester profile
- [x] cancel/moderate request
- [x] write audit event for moderation

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

- [x] user name
- [x] country
- [x] status
- [x] date range

### Audit filters

- [x] actor
- [x] target user
- [x] event type
- [x] date range
- [x] admin-only events

### Exit criteria

- Admin can trace what happened, who did it, and which user/listing/market was affected.

## 14. Stage 9 — Marketer / Referral Department

### Goal

Build a complete marketer department inside the existing admin portal for referral agents,
referral attribution, country-aware campaigns, Nipanze-owned marketing rewards, payout workflow,
fraud/risk review, and performance analytics.

This stage never processes, holds, distributes, or represents P2P loan funds or forex settlement
funds. Marketer rewards are Nipanze marketing expenses, separate from platform revenue and
separate from user-to-user financial activity.

### Database foundation

- [x] Add additive patch: `sql/patch_marketer_department.sql`.
- [x] Reuse and extend existing `referrals` table.
- [x] Add `referral_marketers`.
- [x] Add `referral_campaigns`.
- [x] Add `referral_rewards`.
- [x] Add `referral_payouts`.
- [x] Add `referral_events`.
- [x] Add foreign keys, status checks, indexes, timestamps, and RLS policies.
- [x] Preserve campaign reward snapshots on reward rows.
- [x] Keep rewards/payouts separate from `transactions`.

### Routes

- [x] `/marketers` overview.
- [x] `/marketers/users` marketer list.
- [x] `/marketers/users/[id]` marketer detail.
- [x] `/marketers/referrals` referral list.
- [x] `/marketers/referrals/[id]` referral detail.
- [x] `/marketers/rewards` reward queue.
- [x] `/marketers/payouts` payout queue.
- [x] `/marketers/campaigns` campaign rules.
- [x] `/marketers/risk` fraud/risk queue.

### Filters and analytics

- [x] country filter.
- [x] date range filters where applicable.
- [x] campaign filter.
- [x] marketer status filter.
- [x] referral status filter.
- [x] reward status filter.
- [x] server-side pagination on list/queue pages.
- [x] overview KPIs for marketers, referrals, rewards, campaigns, and risk.
- [ ] richer charts for referrals/rewards over time.
- [ ] exported analytics reports.

### Controls

- [x] activate marketer.
- [x] suspend marketer.
- [x] deactivate marketer.
- [x] flag marketer for review.
- [x] approve/reject rewards.
- [x] place/release reward fraud hold.
- [x] mark reward paid only with explicit verified-payout confirmation.
- [x] move payouts through requested/review/approved/processing/paid/failed states.
- [x] activate/pause/end/deactivate campaigns.
- [ ] create/edit campaign forms.
- [ ] assign/remove campaign from marketer.
- [ ] regenerate referral code with stronger confirmation.
- [ ] structured rejection/failure reason capture in forms.

### Audit and security

- [x] All marketer mutation routes call `requireAdmin()`.
- [x] Service-role writes stay in route handlers/server code.
- [x] High-impact actions prompt confirmation.
- [x] Mutations write `audit_logs` records with before/after status where available.
- [x] Referral detail explains why a reward exists or has not been generated.
- [x] Missing-table screens point admins to `sql/patch_marketer_department.sql`.

### Exit criteria

- Admins can supervise marketers, referrals, rewards, payouts, campaigns, and risk inside the
  existing portal.
- Marketing rewards remain country/currency-aware.
- The department preserves Nipanze's non-custodial boundary.
- Important actions are URL-driven, admin-gated, and audited.

## 15. Stage 10 — Hardening & Launch Readiness

### Security

- [x] Confirm every dashboard route is admin-gated.
- [x] Confirm every mutating route calls `requireAdmin()`.
- [x] Confirm service-role key is never imported into client components.
- [x] Confirm email search is admin-only.
- [x] Confirm KYC documents are not publicly exposed.

### Reliability

- [x] Add pagination to heavy list pages.
- [x] Add graceful errors for missing optional Forex tables.
- [x] Add server-side validation to every mutation.

### Testing

- [x] Build check passes.

## 16. Immediate Next Build Order

1. Add shared filter utilities and small reusable filter controls. [DONE]
2. Upgrade `/dashboard` with richer KPIs and drill-down sections. [DONE]
3. Build the admin-only account search data path that supports email. [DONE]
4. Upgrade `/users` filters and pagination. [DONE]
5. Upgrade `/users/[id]` into a complete control page. [DONE]
6. Extend the same filter/control pattern to KYC, Loans, Forex, Audit Logs, and Transactions. [DONE]
7. Apply `sql/patch_marketer_department.sql` and seed initial referral campaigns/marketers. [NEXT]
8. Add marketer campaign create/edit forms and structured reason capture. [NEXT]

## 17. Definition of Done for First Milestone

The first milestone is complete when:

- [x] `/dashboard` shows meaningful overview metrics and attention queues.
- [x] `/users` can filter by name, phone number, email, country, status, plan, KYC, and admin state.
- [x] `/users/[id]` lets admins view and control the important parts of an account.
- [x] Admin-only email access is handled safely.
- [x] Account status/admin/plan changes are protected by `requireAdmin()`.
- [x] Important admin actions write audit records or have a clear audit implementation path.
