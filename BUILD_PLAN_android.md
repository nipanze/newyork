# BUILD_PLAN.md — Technical Log

> **Repo**: Flutter + Supabase matchmaking marketplace
> **Current focus**: Stage 4 technical backlog, Stage 4.5 country/currency readiness, README and documentation alignment
> **Updated**: August 2026

## 1. Purpose

This file is a technical log for the Nipanze app, not a marketing pitch.
It describes:
- the current architecture and implementation state
- the active screens and systems
- the staging roadmap with explicit criteria and next actions
- the actual repo status relative to the planned feature stages

The goal is to help the team track progress across systems, screens, operations, and implementation gaps.

---

## 2. Current Stage Summary

| Stage | Title | Status | Notes |
|---|---|---|---|
| 1 | Foundation | ✅ Complete | Core app, auth, routing, shared infrastructure established |
| 2 | Core Marketplace | ✅ Complete | Loan marketplace, request posting, offer flow, realtime feed |
| 3 | Polish & Supporting Features | ✅ Complete | Watchlist, Positions, notifications, profile/account, stable local app flows |
| 3.5 | Cloud Migration & Auth Hardening | ✅ Complete | Supabase cloud migration, RLS foundation, `private` schema, auth flow hardened |
| 3.8 | Loan & Forex Request System, Upfront KYC Gate & Calculations Redesign | ✅ Complete | Live repayment math calculator on Step 2, Free vs Pro plan controls split, dash '—' display for missing borrower terms, sponsored post badge, structured Due Day & Cutoff Time selectors for late-fee timing precision, shared upfront `KycGateScreen` on both Loan (`/listings/create`) & Forex (`/forex/create`) request creation, complete 5-language localization (EN, FR, AR, RW, SW), and strict button-disable validation when inputs are missing |
| 4 | Structured Deal Agreement, Contact Sharing & Trust System | ⬜ In progress | Design and stage checklist defined; implementation pending |
| 4.5 | Multi-Market Expansion | ⬜ In progress | Country/currency readiness is documented; database migration not yet applied |
| 4.7 | Forex Marketplace Expansion | ⬜ Planned | Forex module design exists; full schema/UI integration remains to be built |
| 5 | Admin & Compliance | ⬜ Planned | Admin dashboards and compliance tooling not yet implemented |
| 6 | Launch & Growth | ⬜ Planned | Production launch tasks remain ahead |

> Note: Stage numbers are a tracking convention. The important outcome is that Stage 1–3 are stable, while Stage 4 and later are the active product and technical backlog.

---

## 3. Architecture Snapshot

### 3.1 App structure

The app is built as one shared Flutter application with two feature modules:
- `features/marketplace/` — shared marketplace and listing logic
- `features/listings/` — loan request creation
- `features/forex/` — forex create/detail modules
- `features/positions/` — request/offer activity
- `features/auth/` — login/register/verification and onboarding
- `features/account/`, `features/profile/`, `features/kyc/` — user account management

### 3.2 Routing

`lib/core/router/app_router.dart` is the canonical screen map.
Key routes:
- `/auth/welcome`, `/auth/login`, `/auth/register`, `/auth/verify-email`, `/auth/reset-password`
- `/dashboard`, `/marketplace`, `/marketplace/:requestId`
- `/watchlist`, `/positions`, `/account`, `/profile`, `/admin`, `/pricing`
- `/listings/create`, `/forex/create`, `/forex/:requestId`, `/marketplace/agreement/:agreementId`, `/marketplace/deal-unlock/:agreementId`
- `/notifications`, `/kyc`, `/my-forex`

The current route map shows a single shell for authenticated screens and dedicated auth routes.

### 3.3 Core shared systems

- Auth: `AuthBloc` + Supabase auth
- State: `flutter_bloc` / `bloc`
- DI: `get_it` + `injectable`
- Navigation: `go_router`
- Supabase integration: `supabase_flutter`
- Localization: Flutter localization + `intl`
- Secure storage: `flutter_secure_storage`

### 3.4 Data / backend expectations

The app expects a single Supabase project and shared schema with:
- `profiles`, `loan_requests`, `loan_offers`, `watchlist`, `notifications`, `subscriptions`
- `countries`, `currencies`, `system_settings`, `reviews`, `audit_logs`
- `forex_requests`, `forex_offers` as planned future tables
- RLS and `SECURITY INVOKER` wrappers for critical access control

---

## 4. Implementation Reality Check

### 4.1 Verified from repo today

- `lib/features/auth/presentation/pages/login_page.dart` uses locale-based default country selection:
  - `EastAfricaCountries.findByLocale(WidgetsBinding.instance.platformDispatcher.locale)`
  - manual picker remains available
- `lib/core/constants/country_constants.dart` includes `findByLocale` and `findByPhone`
- `lib/features/marketplace/presentation/pages/loan_detail_page.dart` has been adjusted for row layout and overflow prevention
- `lib/core/router/app_router.dart` shows the actual current route surface, including forex create/detail pages
- `pubspec.yaml` lists actual packages used by the app
- `supabase/functions/` contains only two functions: `flutterwave-checkout` and `send-notification`

### 4.2 Current documentation mismatch

- `README.md` mentions packages not present in `pubspec.yaml` (`google_fonts`, `local_auth`, `flutter_local_notifications`)
- `README.md` lists edge functions that are not present in the repo
- `README.md` still includes legacy guidance about non-existent package versions and function names

### 4.3 Actual app behaviour vs. desired

- Country defaulting is currently based on device locale, not carrier network
- The app design has a `All / Loans / Forex` filter planned and `features/forex/` modules present, but the forex module is not fully completed
- Loan detail UI layout has been corrected to prevent overflow warnings on narrow screens

---

## 5. Active Product and Tech Log

### 5.1 Current active work items

1. **Stage 4 technical implementation**
   - wire selective transparency properly in backend and frontend
   - build trust & reputation signal surfaces
   - lock request and offer terms at publish/submit
   - complete contract generation and contact reveal flows
2. **Stage 4.5 multi-market readiness**
   - finalize `countries` + `currencies` schema design
   - ensure onboarding chooses country explicitly and defaults correctly
   - document exact country gating decisions for Uganda, Kenya, Tanzania, Rwanda, Nigeria, South Africa, Egypt
3. **Stage 4.7 forex expansion design**
   - make the forex module a full second project on the shared app
   - support forex-specific listing cards, request creation, selective transparency, and contract wording
4. **Documentation alignment**
   - update `README.md` and repo docs to reflect actual package list, current edge-function surface, and current cloud run commands

### 5.2 Technical log entries

- `2026-08-10`: Confirmed actual route surface in `lib/core/router/app_router.dart`; `AppRouter` includes `/forex/create` and `/marketplace/:requestId`.
- `2026-08-10`: Confirmed `login_page.dart` uses locale-based default and country constants. Carrier/infrastructure-based country detection is not implemented.
- `2026-08-10`: Confirmed `loan_detail_page.dart` fix addresses row overflow and amount/chevron alignment.
- `2026-08-10`: Confirmed README package list and edge function list are stale; the repo currently has only `supabase/functions/flutterwave-checkout` and `supabase/functions/send-notification`.
- `2026-08-12`: Implemented shared `KycGateScreen` for upfront KYC checking on both Loan (`/listings/create`) and Forex (`/forex/create`) request creation flows before form rendering. Refactored KYC document upload (`kyc_repository.dart`, `kyc_cubit.dart`, `kyc_page.dart`) to use cross-platform byte streaming (`XFile.readAsBytes()` + `uploadBinary`), resolving Web/Chrome `dart:io` file path runtime crashes. Added complete 5-language localization (EN, FR, AR, RW, SW) across all KYC components with full green checkmark / tick UI feedback, and enforced strict button disabling when required inputs/documents are missing.

---

## 6. Stage-by-stage Technical Checklists

### Stage 1 — Foundation

Completed items:
- [x] Flutter app bootstrap
- [x] `go_router` auth-aware routing
- [x] Supabase client integration
- [x] Login, register, verify email, reset password screens
- [x] Shared theme and localization scaffolding
- [x] DI configured with `get_it` + `injectable`
- [x] `AuthBloc` and auth state refresh via `GoRouterRefreshStream`
- [x] Basic app stability across Android, Web, Linux

### Stage 2 — Core Marketplace

Completed items:
- [x] Marketplace feed with loan listings
- [x] Loan request creation form and review flow
- [x] Offer creation and submission logic
- [x] Subscription gating for offer creation
- [x] Request owner acceptance flow
- [x] Realtime feed updates
- [x] Watchlist and Positions app surfaces
- [x] Notifications page and event handling

### Stage 3 — Polish & Supporting Features

Completed items:
- [x] Watchlist repository and UI
- [x] Positions repository and UI
- [x] Profile and account screens
- [x] KYC upload scaffolding
- [x] Empty/error states and offline banner
- [x] Local cache and secure storage integration

### Stage 3.5 — Cloud Migration & Auth Hardening

Completed items:
- [x] Cloud-ready shell scripts in repo (`run_cloud.sh`, `run_local.sh`, `run_linux.sh`)
- [x] RLS and security-aware Supabase architecture documented in README
- [x] Private storage for verification documents
- [x] Auth trigger and profile creation intent documented

### Stage 4 — Structured Deal Agreement, Contact Sharing & Trust System

Current status:
- [ ] Request/offered term locking implemented end-to-end
- [ ] `role` removal confirmed at data-model and UI gating levels
- [ ] Public trust badge row implemented and available on listing/profile surfaces
- [ ] Review submission and trust aggregation flows implemented
- [ ] Contract generation and contact reveal flows built and verified
- [ ] Selective transparency enforced by backend views/RPCs and frontend detail page

Recommended next steps:
- Add explicit DB-level governance for request ownership and offer participant access.
- Implement a shared `TrustBadgeRow` widget with zero-state rendering.
- Build `submit_review()` and `recompute_trust_aggregates()` backend flows.
- Verify `accept_offer` / `reveal_contact` semantics in the current codebase.

### Stage 4.5 — Multi-Market Expansion

Current status:
- [x] Country/currency design work documented in README and build plan
- [x] Locale-based default country selection exists in login
- [ ] Database migration for `countries`, `currencies`, and `profiles.country` not yet applied
- [ ] Loan request country propagation and currency references not yet fully implemented
- [ ] Country-based feed filtering not yet fully enforced in app queries

Core checklist:
- [ ] Create `countries` table and seed the seven target markets
- [ ] Create `currencies` table and seed the seven market currencies + `USD`
- [ ] Add `profiles.country` and backfill existing users
- [ ] Add `loan_requests.country`, `loan_requests.currency_code`, and country-locked triggers
- [ ] Add `system_settings.allow_foreign_currency_loans`
- [ ] Add country-aware pricing via `subscriptions.currency_code`
- [ ] Validate `MarketplaceRepository` default country feed and explicit market switching
- [ ] Document cross-border offers policy and global browse vs hard isolation decision

### Stage 4.7 — Forex Marketplace Expansion

Current status:
- [ ] Forex-specific tables and selective-transparency logic not yet built
- [ ] frontend UI for forex create/detail exists in route map but may not be finished
- [ ] currency safety gating is designed but not yet enforced

Core checklist:
- [ ] Create `forex_requests` and `forex_offers` tables
- [ ] Add `countries.forex_enabled` gating and `currencies.forex_trading_enabled`
- [ ] Build `v_forex_listings` and participant-scoped `v_forex_offers`
- [ ] Build forex-specific request creation flow and listing card
- [ ] Extend shared `accept_offer` / contract generation to forex wording
- [ ] Validate non-participant rate masking with direct API tests

### Stage 5 — Admin & Compliance

Planned items:
- [ ] Admin dashboard and KYC review tools
- [ ] Per-country toggles for lending and forex activation
- [ ] Currency-level toggle for forex trading enablement
- [ ] KPI reporting by market and request type
- [ ] SMS alert system integration with the existing send-notification function

### Stage 6 — Launch & Growth

Planned items:
- [ ] App store / play store packaging and compliance
- [ ] Onboarding without role selection, with country selection step
- [ ] Admin-finalized local subscription pricing per market/currency
- [ ] Payment integration for subscriptions only
- [ ] Launch checklist for Kenya, Tanzania, Rwanda, Nigeria, South Africa, Egypt

---

## 7. Actual screen and flow map

### Primary bottom-nav screens
- `Markets`
- `Watchlist`
- `Request`
- `Positions`
- `Account`

> Note: `DashboardPage` exists in the app as a separate authenticated route, but it is not part of the main bottom navigation shell.

### Auth flows
- `WelcomePage` → `LoginPage` / `RegisterPage` → `VerifyEmailPage` / `ResetPasswordPage`

### Core product flows
- Loan request creation: `ListingCreatePage`
- Loan detail and offers: `LoanDetailPage`
- Forex create: `ForexCreatePage`
- Forex detail: `ForexDetailPage`
- Agreement review: `AgreementReviewPage`
- Deal unlock: `DealUnlockPage`

### Country and locale handling
- Default country is selected from device locale using `findByLocale()`.
- Manual country selection is preserved in the auth flow.
- Carrier-based country detection is not yet present.

---

## 8. Key gaps and immediate next work

### Immediate technical gaps
- Backend enforcement of selective transparency for loan offers and forex offers
- Fully implemented trust and review flow
- Contract generation and `reveal_contact` gating
- Database migration for country-aware multi-market support
- Actual forex module completion and currency gating

### Documentation gaps
- README package list needs to match `pubspec.yaml`
- README edge-function list needs to reflect repo contents
- README deployment and env guidance should match actual run scripts and cloud flow

### Practical short-term plan
1. Update `README.md` to align with current repo state
2. Complete Stage 4 backend and frontend gating for selective transparency and contract/contact flow
3. Apply Stage 4.5 schema migrations and country/currency seeding in a dedicated branch
4. Build Stage 4.7 forex request/offer flow and verify with direct API tests
5. Review and test the `login_page.dart` country default behavior; decide whether locale is sufficient or if carrier detection should be added later

---

## 9. Recommended engineering practice

- Keep the two modules separate at the data/schema level but shared at the auth/trust/contact level.
- Treat the marketplace as a single experience with `All / Loans / Forex` filtering.
- Use RLS and backend views for access control rather than relying on client filtering.
- Track country and currency explicitly in each row that requires it.
- Avoid storing an offer country independently; infer it from the parent request.
- Log every key technical decision in the corresponding stage section.

---

## 10. Notes for the next review

- Confirm whether `forex` routes are fully wired in the UI and backend.
- Confirm whether `system_settings` currently supports per-country loan currency rules.
- Confirm whether `profiles.country` is persisted for new users and whether the country is mutable only through onboarding.
- Confirm whether `offer` visibility is currently gated by participant status in the backend.
- Confirm whether `contracts` and contact reveal are enforced by the `reveal_contact` backend function or a similar RPC.

---

*Technical log authored by the repository automation and review process.*
