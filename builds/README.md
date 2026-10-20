# Nipanze README — Needs Layer Update + Implementation Guide

This file has two parts:

- **Part 1**: drop-in README edits, in the order they appear in your README.
- **Part 2**: how to implement it (database → Flutter → rollout).

The design rule throughout: **Loans and Forex stay exactly as they are.** The Needs layer is added beside them as a third module. It reuses the same auth, plans, trust, blocks, and contact-reveal machinery.

---

# PART 1 — README EDITS

## 1.1 Tagline + Overview (replace the first blockquote and the first Overview paragraph)

> Nipanze is a **need-first marketplace**. You say what you need — money, currency, a visa agent, an excavator, a specialist, a truck, a hard-to-find product — and people who can help make you offers. No bank, custodian, or intermediary ever holds your funds or currency. Live in Uganda first, built on one shared schema to expand across Kenya, Tanzania, Rwanda, Nigeria, South Africa, and Egypt.

Add to the end of the Overview section:

> **Jiji is inventory-first: "I have this, who wants it?" Nipanze is need-first: "I need this, who can help?"** Loans and Forex are the two financial modules. **Needs** is the third module and covers five non-financial categories where finding the right person is the hard part: Travel & International, Machinery & Equipment, Professional Services, Transport & Logistics, and Specialized Products & Procurement.

## 1.2 Replace "Two Projects, One Platform" with "Three Modules, One Platform"

| Shared (one platform) | Separate (three modules) |
|---|---|
| Auth, `profiles`, `subscription_plan`, `is_admin` | `loan_requests`/`loan_offers` · `forex_requests`/`forex_offers` · `needs_requests`/`need_offers` |
| `countries`, `currencies`, `system_settings` | `features/loans/` · `features/forex/` · `features/needs/` |
| Trust & reputation (`trust_aggregates`, `reviews`) | Card design: funded-% bar · Send/Rate/Receive panel · Need card (category + offers) |
| Selective transparency pattern (RLS + RPC) | Create flow: loan terms · currency pair · category-driven need form |
| Contact reveal, blocks, watchlist, notifications, KYC, Admin | Per-module regulatory review per market |
| One Marketplace screen with a module filter | Per-module launch sequencing |

Why not one generic "request" table: a loan, a currency exchange, and a visa-assistance need have different shapes. Force-fitting them makes all three worse. Three tables and three forms, with everything else shared.

### Marketplace service discovery

The Marketplace header is focused on browsing and keeps its notification bell, but no longer has a separate **Add Service** action. The bottom **Post** action remains the universal creation entry point for Loan Request, Forex Request, Need Request, and Offer a Service.

Service discovery is contextual in the feed rather than a permanent posting prompt: users without capabilities are invited to add services; providers can be shown genuinely new, unexplored categories or active Needs matching their capabilities. The card is omitted when there is nothing relevant to surface and appears after a variable number of listings.

## 1.3 New section — "The Needs Layer" (insert after "The Unified Marketplace Model")

### The five launch categories

| | Category | Core problem it solves | Example need |
|---|---|---|---|
| ✈️ | **Travel & International** | Hard-to-vet agents for visas, tickets, Hajj/Umrah | "Sweden visa assistance, December, UGX 500k budget" |
| 🚜 | **Machinery & Equipment** | Expensive assets people need temporarily | "Excavator for 3 months, Wakiso" |
| 🧑‍💼 | **Professional Services** | Finding the right specialist | "Company registration help, Kampala" |
| 🚚 | **Transport & Logistics** | Specialized or heavy transport on short notice | "20 tonnes of cement, Kampala → Gulu" |
| 🔎 | **Specialized Products & Procurement** | Things that aren't easy to find | "50 Epson L3150 printers, delivered to Mbarara" |

Loans (💰) and Forex (💱) remain first-class markets alongside these, not sub-categories of Needs.

### How a Need works

```
1. POST     → Anyone posts a Need for free (category-driven form: what, where, when, budget)
2. OFFER    → Providers with a matching declared capability make offers (price, timeline, message) — locked on submit
3. REVIEW   → The requester compares offers plus each provider's trust signals
4. ACCEPT   → Requester accepts one offer; the others are rejected
5. UNLOCK   → Contact details are revealed only after acceptance
6. CONNECT  → Parties proceed off-platform. Nipanze never handles payment for goods or services
7. RATE     → One review per side, feeding the same global trust aggregate
```

### Provider capabilities (what you can help people with)

- **Multi-select, per capability.** Someone can provide *Visa Assistance* and *Excavator Hire* at the same time. Each capability is its own row (`provider_capabilities`), not a single "profession".
- **Professional Services** includes specialist services performed for the requester, such as Accounting, Legal Support, Tax Filing, Business Registration, Marketing & Promotion, and **Driving School & Driver Training** (driver training and instructor services).
- **Transport & Logistics** focuses on moving goods, equipment, cargo, and bulk transport (Bulk Delivery, Cargo Transport, Cold Chain, Courier, Heavy Haulage, Moving Services, Truck Hire, Vehicle Transport).
- **Marketing & Promotion** remains in Professional & Business Services and expands to specific options such as TikTok Promotion, Content Creation, and Influencer Marketing. `I Have an Audience` optionally stores platforms, follower/member count, location, and interest in that capability row's `metadata`.
- **Music & Video** and **Weddings & Celebrations** are additional groups in the same Needs capability catalog. They cover performers and production teams, graduation and wedding photography/video, styling, outfits, event suppliers, planning, and social celebrations.
- These are opportunities for providers of any gender. They include creative, beauty, styling, performance, and event work that can especially resonate with women without creating a women-only marketplace or separate provider mode.
- Category and capability slugs stay stable across markets. Existing catalog rows support optional ISO country-code label overrides in `country_labels` JSONB (`UG`, `KE`, `TZ`, `RW`, `NG`, `ZA`, `EG`); clients use a country override when present and otherwise show the shared label. Need requests continue to carry their existing country and use the same country-aware feed and offer flow.
- Audience details are user-declared profile information, displayed separately from verification. They do not create an account mode or verified audience badge; verification remains admin-controlled by the existing capability verification system.
- **Offers require a matching capability.** You can only offer on a Need whose category you have declared a capability in. This stops "I provide everything" accounts.
- **Progressive verification, never trusted from onboarding alone:**

| Level | How earned | Shown as |
|---|---|---|
| 🟡 Self-declared | Ticked during onboarding or profile | "Offers Visa Assistance" |
| 📱 Phone verified | OTP (already in `profiles.phone_verified_at`) | + phone badge |
| 🪪 Identity verified | KYC approved (already in `kyc_verifications`) | + verified badge |
| 🟦 Provider verified | Admin review of capability-specific evidence (licence, fleet, portfolio) | "Verified Travel Provider" |
| ⭐ Earned | Completed connections + reviews | rating + completed count |

"Verified Provider" labels are only ever set by admin review. A user can never set their own verification level.

The legacy `marketing_services` slug is retained as the Marketing & Promotion display name, so existing provider rows remain valid. Specific marketing options use separate capability slugs and continue to participate in the existing capability-based Provider Opportunities matching.

Creative and event capabilities are added by `sql/patch_creative_events_capabilities.sql`. Providers can multi-select across all groups; each selection remains a `provider_capabilities` row and is matched by the existing Need-offer validation. No new request, offer, trust, verification, or interest system is introduced.

### Selective transparency for Needs (same tiers as Loans/Forex)

| Viewer | Sees |
|---|---|
| Anyone browsing | Need summary, budget, location, number of offers, coverage tier. Never individual offer terms |
| Provider who has **not** offered | Same as anyone browsing |
| Provider who **has** offered | Above, plus exact terms of competing offers (anonymized) |
| Requester | Every offer in full, plus each provider's trust signals |

Contact details stay locked for everyone until the requester accepts and unlocks.

### Non-custodial boundary for Needs

Nipanze does **not** hold payment for goods or services, run escrow, verify that a service was delivered, guarantee quality, or act as a travel agent, visa agent, equipment dealer, or carrier. It matches needs with offers and controls contact sharing.

## 1.4 New section — "Personalization: Intent-Based Onboarding & Home" (insert after Needs Layer)

### Onboarding asks two separate questions

No "Are you a provider or a visitor?" step. Those are system concepts, not identities.

1. **What brings you to Nipanze?** *(multi-select, max 3 as top interests)*: Money/financing · Currency exchange · Travel/Visa · Machinery/Equipment · Professional services · Transport/Logistics · Hard-to-find products · Something else
2. **Is there anything you can help people with?** *(optional, multi-select, skippable)*: capability picker grouped by category. Each tick becomes a self-declared `provider_capabilities` row.

Both answers are editable any time under **Account → Your Nipanze**.

### Interest profile: explicit + learned

| Signal | Source |
|---|---|
| Explicit | Onboarding picks, categories followed, categories muted |
| Behavioral | Needs opened, saved to watchlist, needs posted, offers made (`user_interest_events`, last 30 days) |
| Outcome | Accepted offers, completed connections, reviews |

Feed ranking = explicit weight + recent behavior. Muted categories are excluded outright.

### Home vs Markets

| | **Home** | **Markets** |
|---|---|---|
| Question it answers | "What might be useful to *me*?" | "Show me the marketplace" |
| Content | Greeting, search, **For You** (ranked), your interests (editable), saved items, **Provider Opportunities** (needs matching what you provide), explore-by-category | Full feed with filter row `For You · All · Loans · Forex · Needs`, category chips, country scope |
| Personalized | Yes | Only the `For You` tab |

**Provider Opportunities** appears on Home only if the user has at least one active capability: "People are looking for what you provide: 3 Travel, 2 Machinery." One account, both experiences, no separate provider mode.

### Context-aware discovery questions

The optional For You discovery card offers multi-select interest categories. Choices are stored privately in the existing `user_interests` table under its owner-only RLS policy; they are not Need posts, provider offers, or notification subscriptions. “Explore opportunities” opens the real Needs feed filtered to selected categories, or the available Needs feed when no category is selected. A zero-result filter offers the existing Need creation flow and confirms that preferences remain saved. Skipping or dismissing a question hides it without affecting the marketplace feed.

### Suggested bottom navigation (proposal — changes current nav)

Current: `Markets · Watchlist · Request · Activity · Account`
Proposed: **`Home · Markets · ➕ Post · Activity · Account`**

- The ➕ Post FAB opens a chooser: **Loan · Forex · Need**.
- Watchlist moves to a "Saved" row on Home, and stays reachable from Account.
- If you'd rather not touch the nav yet, ship Home as the first tab and keep the rest unchanged.

## 1.5 Edits to existing sections

**Feature access by plan** — add to each row:

| Plan | Add this |
|---|---|
| 🟢 Free | Post unlimited-per-plan-limit Needs · browse all Needs · accept offers received · make a small number of Need offers per month if you hold a matching capability (default **3/month**, admin-configurable via `system_settings.needs_free_offers_per_month`) |
| 🔵 Lender | Unlimited Need offers for capabilities you hold |
| 🟣 Pro | Above + priority placement for your Needs and offers, "Provider verified" review fast-track |

> **Open decision:** the plan is called "Lender" but now unlocks offers for a visa agent or truck owner. Either rename it (e.g. "Offers") or keep the internal enum value `lender` and change only the display label. Not blocking; the schema keeps `subscription_plan_enum` unchanged.

**Marketplace Feed & Listing Design** — filter row becomes `For You · All · Loans · Forex · Needs`. Add a card spec:

### Need listing card
- **Badge:** category icon + name (e.g. `✈️ Travel & International`)
- **Meta line:** location · timeline (e.g. "Kampala · December")
- **Title** (what is needed) and **budget** (in the listing's currency, or "Open to offers")
- **One-line summary**
- **Offer count** (e.g. "3 offers") and a compact expiry clock with a shrinking lifetime ring
- **Trust badges:** requester `⭐ No reviews yet` / `💎 0 completed`; `✓ Verified requester` when KYC approved
- **Star icon:** save to watchlist

Home and Markets share the same compact listing-card layout. Cards show their category, title, amount, relevant location, offer count, and module-specific metadata; age labels are not used as expiry. When `expires_at` is present, the blue/amber/red clock ring uses the fraction of the original listing lifetime remaining and opens a live, exact countdown. Missing expiry data produces no countdown. Loan repayment term remains loan-specific and is shown in loan details, never in listing-expiry metadata.

Status: this is implemented in the shared marketplace card and expiry indicator, with discovery prompts restricted to the For You tab and non-For-You tabs left as pure listing flows.

The provider-opportunities card remains mixed into the feed at its existing recommendation-selected position and keeps the existing capability-matching logic. Its surface, border, and spacing follow the listing cards.

**Regulatory Compliance** — add: *Needs categories carry their own sector rules. Travel and immigration assistance, Hajj/Umrah operators, freight, and professional services (legal, accounting, engineering) are licensed or regulated in many markets. Nipanze matches; it does not vouch for a provider's licence unless the "Provider verified" badge, granted after admin review, says so. Every market needs a per-category review before that category is enabled there.*

**Project Structure** — add:

```
features/
├── home/            # Personalized Home: For You, interests, provider opportunities
├── needs/           # 🟠 NEEDS PROJECT — create need, need detail, my needs, need offers
├── interests/       # Interest picker, follow/mute, behavior event recording
└── provider/        # Capability picker, "Your services", verification status
shared/widgets/      # + NeedCard, CategoryChip, CapabilityBadge, ProviderVerificationChip
```

**Screen / Route Map** — add:

| Route | Screen | Auth |
|---|---|---|
| `/home` | HomePage (personalized) | Yes |
| `/needs/create` | NeedCreatePage (category-driven form) | Yes (Free+) |
| `/needs/:requestId` | NeedDetailPage + offers | Yes |
| `/needs/my-needs` | MyNeedsPage | Yes |
| `/onboarding/interests` | InterestsStep | Yes |
| `/onboarding/capabilities` | CapabilitiesStep | Yes |
| `/account/services` | ProviderServicesPage | Yes |
| `/account/interests` | EditInterestsPage | Yes |

**Database Schema tables** — add:

| Table | Purpose |
|---|---|
| `need_categories` | The five categories (slug, name, icon, sort, `is_active`) |
| `need_capabilities` | Sub-capabilities per category (e.g. `visa_assistance`, `excavator_hire`) |
| `needs_requests` *(extended)* | Existing table plus `category_slug`, `capability_slug`, `details` (JSONB, category-specific fields), `number_of_offers`, `expires_at`, status lifecycle |
| `need_offers` | Provider offers: price, timeline, message. Locked on submit. No `country` column (read via `need_id`) |
| `need_contact_reveals` | Post-acceptance contact sharing for needs |
| `provider_capabilities` | Per-user declared capabilities plus `verification_level` (admin-controlled) |
| `user_interests` | Explicit interests / mutes |
| `user_interest_events` | Behavioral signals for ranking |

**Key functions/views** — add: `v_needs_listings` (rebuilt, adds coverage tier + trust), `get_public_need_offers(need_id)`, `accept_need_offer(need_id, offer_id)`, `unlock_need_contact(offer_id)`, `get_for_you_needs(country, limit)`, `get_provider_opportunities(limit)`, `record_interest_event(category, event)`.

**Roadmap** — add after Stage 4.7:

### Stage 4.8 — Needs Layer & Provider Services ✅ Implemented
- Needs categories + capabilities, extended `needs_requests`, `need_offers`, contact reveal, provider capabilities with progressive verification
- Intent-based onboarding, personalized Home, `For You` ranking, provider opportunities
- Per-category, per-market enablement flag (`need_categories.is_active` plus a country override in `system_settings`)

**Recent Updates** — add a dated entry summarizing: Needs module, five categories, onboarding intent step, Home vs Markets split, capability-gated offers, and the privacy fix on `needs_requests` (below).

---

# PART 2 — HOW TO IMPLEMENT

## 2.0 What already exists (build on it, don't redo it)

Your repo already has `needs_requests`, `v_needs_listings`, ~110 sample rows, and an insert/update policy for posting. The new work extends that table instead of replacing it. Two problems in the current patch need fixing first:

1. **`requester_id` is publicly readable.** The current patch grants `select` on the base table to `anon` with an "active rows" policy, which exposes the poster's UUID. That breaks the platform's masking rule. The SQL patch moves public reads to the view (which excludes it) and restricts the base table to the owner.
2. **`budget` is `integer`.** It overflows at ~2.1B, which is a realistic value for machinery in NGN or UGX. The patch widens it to `bigint`.

The existing sample rows use free-text categories (`'Home & Energy'`, `'Business Equipment'`…). The patch backfills `category_slug` from them with a best-guess map. Review that map, since most sample rows land in "Specialized Products".

## 2.1 Phase 1 — Database (run `patch_needs_layer.sql`)

Run order: the patch is idempotent and assumes `schema.sql` + `patch.sql` are already applied. It creates:

- Reference tables with the five categories and starter capabilities
- Extended `needs_requests` (category, details JSONB, offer count, expiry)
- `need_offers` with validation trigger (must be active, not self, must hold a matching capability, free-tier monthly cap)
- `provider_capabilities` with a trigger that forces `verification_level = 'self_declared'` unless the writer is an admin
- `user_interests`, `user_interest_events`
- RPCs: accept, unlock, public offer book, For You, provider opportunities, record event
- RLS on everything new; rebuilt `v_needs_listings`

Then verify:

```sql
select slug, is_active from need_categories order by sort_order;
select category_slug, count(*) from needs_requests group by 1;
-- as anon, this must fail or return zero rows:
select requester_id from needs_requests limit 1;
```

## 2.2 Phase 2 — Flutter data layer

```
lib/features/needs/
├── data/
│   ├── models/         need_listing_model.dart, need_offer_model.dart, need_category_model.dart
│   └── datasources/    needs_remote_ds.dart   // v_needs_listings, need_offers, RPCs
├── domain/
│   ├── entities/       need_listing.dart, need_offer.dart
│   └── repositories/   needs_repository.dart
└── presentation/
    ├── bloc/           needs_feed_cubit.dart, need_create_cubit.dart, need_detail_cubit.dart
    └── pages/          need_create_page.dart, need_detail_page.dart, my_needs_page.dart
lib/features/home/       home_cubit.dart, home_page.dart
lib/features/interests/  interests_cubit.dart, interests_repository.dart
lib/features/provider/   capabilities_cubit.dart, provider_repository.dart
```

Add constants in `core/constants`: `Tables.needRequests`, `Tables.needOffers`, `Views.needsListings`, `Rpcs.getForYouNeeds`, `Rpcs.acceptNeedOffer`, `Rpcs.unlockNeedContact`, `Rpcs.getProviderOpportunities`, `Rpcs.recordInterestEvent`.

**Category-driven create form.** Store category-specific fields in `details` JSONB and drive the form from a small per-category field config, so adding a field never needs a migration:

```dart
const needFormSchema = {
  'travel_international': [Field.text('destination'), Field.date('travel_date'), Field.int('travellers')],
  'machinery_equipment':  [Field.text('equipment_type'), Field.int('duration_days'), Field.bool('operator_needed')],
  'transport_logistics':  [Field.text('from'), Field.text('to'), Field.text('load_description')],
  // …
};
```

Keep `title`, `specification`, `budget`, `currency`, `location`, `country`, `urgency` as real columns. They are what the feed sorts and filters on.

## 2.3 Phase 3 — Marketplace integration

1. Extend `MarketplaceCubit` module filter enum: `forYou | all | loans | forex | needs`.
2. `needs` → query `v_needs_listings` with the same `country` scoping used for loans/forex.
3. `forYou` → call `get_for_you_needs`.
4. `all` → merge loans + forex + needs by `listed_at` (as you already do for loans + forex). Cap each source to avoid one module drowning the rest.
5. Add `NeedCard` and render it from the same list widget.
6. On card open / save / post / offer, call `record_interest_event` (fire-and-forget; never block the UI on it).

## 2.4 Phase 4 — Onboarding + Home

1. Add two steps after signup: `InterestsStep` (required, pick up to 3) and `CapabilitiesStep` (optional, skippable). Write `user_interests` and `provider_capabilities` rows.
2. Route guard: users with no `user_interests` rows are sent to `/onboarding/interests` once.
3. `HomePage` sections, each hidden when empty: greeting + search → For You (top 5) → Your interests (chips, edit) → Saved → Provider Opportunities (only if user has capabilities) → Explore by category.
4. Make Home the first tab. Only then decide on the nav change in 1.4.

## 2.5 Phase 5 — Provider trust

- Add `ProviderVerificationChip` reading `provider_capabilities.verification_level` plus existing phone/KYC status.
- Admin portal: a "Provider capabilities" queue (filter `self_declared`, approve → set `provider_verified`). Only admin can set the level, and the DB trigger enforces it.
- Reviews: add `need_deal_id` to `reviews` (same nullable-sibling pattern used for `forex_contract_id`) and extend `recompute_trust_aggregates` to count completed needs deals, so trust stays one global score across all three modules. *(Not included in the SQL patch; do it as a follow-up once needs deals exist.)*

## 2.6 Rollout order (smallest safe steps)

| Step | Ship | Risk |
|---|---|---|
| 1 | SQL patch + privacy fix | Low — no UI change |
| 2 | Needs tab in Markets (browse + post) using existing posting | Low |
| 3 | Offers + accept + unlock | Medium — new money-adjacent trust flow |
| 4 | Capabilities + capability-gated offers | Medium |
| 5 | Onboarding interests + Home + For You | Medium — changes first-run |
| 6 | Verification queue + badges | Low |
| 7 | Enable categories per market | Regulatory — gate each one |

Launch with **Machinery, Professional Services, Transport, Products** first. Enable **Travel & International** last and only for verified providers, since visa/Hajj fraud is the highest-harm category.

## 2.7 Tests to write

- Anon cannot read `requester_id` from `needs_requests`.
- A user without a capability in the category cannot offer (`P0203`).
- Free user's 4th offer in a month is rejected; Lender's is not.
- Non-participant sees only count + tier; offer-maker sees competing terms anonymized; owner sees all.
- Accepting one offer rejects the others and sets the need `matched`.
- A user cannot change their own `verification_level`.
- Muted category never appears in `get_for_you_needs`.
- Blocked user cannot see or offer on the blocker's needs.

## 2.8 Things to decide before Step 3

1. **Plan naming/gating for offers** (see 1.5).
2. **Do Needs need a locked agreement?** The patch skips agreements (accept → reveal only), since a visa or transport job doesn't have loan-style terms. If you want a locked record, add `need_agreements` mirroring `forex_agreements`.
3. **Contact-unlock fee:** still an open decision in your schema. If adopted, it applies to Needs too.
4. **Provider licence evidence** per category (what admin checks before "Provider verified").

---

# PART 3 — CENTRAL VERIFICATION & ACTIVITY SYSTEM

## 3.1 Central Platform-Level Verification (Extended KYC)

Identity verification is the central security and trust gate for the entire marketplace across all modules (Loans, Forex, Needs, Offers, and Provider Services).

- **Identity Verified (`profiles.kyc_status = 'approved'` / `kyc_verifications`)**:
  - Global pre-requisite for posting or making offers.
  - An unverified user can browse, search, view listings, save watchlist items, and view public profiles.
  - An unverified user **cannot** post Loan/Forex/Need requests, make Loan/Forex/Need offers, create service capabilities, accept offers, or unlock contact details.
- **Provider Verified (`provider_capabilities.verification_level = 'provider_verified'`)**:
  - Capability/category-specific verification based on administrative review of submitted evidence (licenses, certifications, fleet records).
  - Identity verification does not automatically grant provider verification.

## 3.2 Hierarchical Verification Requirements Engine

Verification rules are stored dynamically in `verification_requirements` and evaluated hierarchically:
`Capability Level` -> `Category Level` -> `Activity Level` -> `Global Level` (most specific rule applies).

- **Database Enforcement**: Server-side triggers and RPC guards enforce rules (`private.require_identity_verified`, `can_perform_marketplace_activity`).
- **Flutter Interception**: `VerificationGateModal.checkAndGate` intercepts posting and offer actions before forms open, prompting users to verify and returning them to their intended flow upon completion.

## 3.3 Activity Navigation Update

- Navigation bar, routes, tabs, and user-facing terminology transitioned from **Positions** to **Activity** (`AppRoutes.activity`, `navActivity`).

## 3.4 Standalone Database Migration

- `sql/patch_central_verification_system.sql`: Contains the complete standalone schema, RLS policies, trigger guards on requests/offers/capabilities/unlocks, and admin RPCs.

## Offline and cached browsing

Marketplace listings and the signed-in user's profile are kept in a lightweight
in-memory cache for the current app session. Activity and Provider Services
keep their last loaded view visible while a refresh is unavailable. If a
network request fails, the app retains loaded content and shows a brief
“You’re offline · Showing recently loaded data” SnackBar rather than replacing
the screen with a connection error. When connectivity returns, affected views
refresh automatically and show “Connection restored · Updating…”.

When no data has loaded yet, the screen offers an offline message and Retry.
This is stale-data browsing only: changes, offers, contact reveals, payments,
and other server-backed actions still require a successful server request and
are never queued. Session caches are cleared after a successful sign-out; data
is not persisted as an offline-first store.

---

# PART 4 — UNIFIED PROVIDER SERVICES & FINANCIAL CAPABILITIES

## 4.1 Single Source for Provider Capabilities
Provider Services is the single place where a user declares what they provide across all marketplace modules (Needs, Loans, Forex):
- **Provider Services financial capabilities** remain in Provider Services only; `financial_services` is not an active Needs category. Loans and Forex continue as standalone modules.
- **Multi-Category Capabilities**: Users can hold capabilities across multiple categories simultaneously (e.g. Loan Services + Forex / Currency Exchange + Business Consulting + Excavator Hire).
- **Service vs Professional Identity Separation**:
  - **Service**: What the provider offers (e.g., Loan Services, Forex / Currency Exchange).
  - **Professional Identity / Metadata**: Who they represent (Organisation/Bank name, Role, Professional Tag visibility, and Institution Matching permissions stored in capability metadata).
- **Edit Profile Cleanup**: Income type, employer name, and monthly income are collected contextually in loan requests rather than general profile editing. Bank and professional agent blocks are moved into Provider Services capability metadata.
- **Database Patch**: Consolidated into `sql/patch.sql` and `sql/merged.sql`.

## 4.2 Loan-only borrower information

- The Needs picker contains only active non-financial categories. Historical `financial_services` category and capability rows are retained but disabled; inserts or category changes cannot create financial Needs requests.
- Nipanze does not add a Financial Profile, Income Profile, or Banking Profile to Account, onboarding, or general profile editing.
- Employment status, employer/business name, government employee status, monthly income range and its currency, other income source, and preferred bank are collected inside Post → Loan only. Reusable values live in `public.borrower_information`, separate from `profiles` and all request/listing tables.
- The table grants access only to the authenticated owner through RLS. It is not joined into public marketplace views or included in a Loan, Forex, Needs, Offer, or public-profile payload.
- Future Loan Requests load the saved values into the loan form. The user can restore the saved values, edit them for the current request, and the edited values are saved for later Loan Requests. Loan amount, purpose, repayment terms, collateral, and other request details are still entered for each loan.
- Loan requests also save optional borrower-written context. Apply `sql/patch_loan_request_descriptions.sql` to existing databases before deploying the app update; new database setups receive the column from `sql/schema.sql`.
- Loan and Need forms offer compact, optional suggestions from the user's own recent requests. Need suggestions are loaded only for the signed-in requester; choosing one copies editable values into the form.
- Database changes are consolidated in `sql/patch.sql` and `sql/merged.sql`.

## 4.3 Private discovery plans and quick questions

- Lightweight discovery questions are driven by `discovery_question_templates` and shown as compact cards in the Home/Marketplace feed.
- Answers can save a private plan in `user_discovery_plans`; plans are owner-only under RLS and are not exposed in public listings, provider feeds, or profiles.
- `user_discovery_interactions` stores skip, dismiss, mute, answer, and save actions so the app can apply conservative cooldowns.
- Account -> Plans & interests lets users review, edit, and delete saved plans.
- The initial templates cover travel, education/career, business needs, and financial interests. Financial interests stay separate from Loans and Forex publishing flows.
- Database changes are consolidated in `sql/patch.sql` and `sql/merged.sql`.

## 4.4 Existing-post expiry migration

`sql/patch_migrate_existing_post_expiry_v1.sql` is a standalone, transactional data migration. Run it only after `sql/schema.sql`, `sql/patch.sql`, and the Needs layer are installed. Do not add it to or replace the monolithic `sql/patch.sql`.

| Market/category | Active duration |
|---|---:|
| Loans | 30 days |
| Forex | 7 days |
| Needs — Machinery & Equipment | 14 days |
| Needs — Professional Services | 14 days |
| Needs — Transport & Logistics | 7 days |
| Needs — Specialized Products & Procurement | 14 days |
| Needs — Travel & International | 14 days |

The migration reads these values from their existing global `system_settings` entries and stops before any data changes if they or any country overrides do not match the approved durations. Existing active posts are recalculated from their original `listed_at` value; `created_at` and `updated_at` are not used. It changes active rows only, expires those whose new deadline has passed, and leaves terminal-status rows, offers, reviews, and audit history untouched. A null listing timestamp or an unknown Needs category is reported and left unchanged for manual review. The audit output also flags seeded/development records (known seed UUID prefix for Loans/Forex; null `requester_id` for sample Needs).

The migration corrects the shared insert-expiry trigger to use the Forex setting and the Needs category setting, and adds the same configured expiry trigger for new Needs posts. It does not redefine or drop any listing views or recommendation RPCs, preserving their existing output columns, grants, and dependencies. The backfill marks past-deadline active posts expired; the existing active-status filters then exclude them from public feeds, `get_for_you_needs`, and Provider Opportunities. Offer inserts and acceptance state transitions fail closed for inactive, expired, or undated parent posts. A private status-sweep function is scheduled every five minutes when `pg_cron` is installed; reruns replace the named job rather than duplicating it. If `pg_cron` is not installed, the migration reports that automatic status transitions need scheduling. Feed exclusion and offer/acceptance guards still enforce expiry without `pg_cron`.

### Execution order

1. Back up the database and apply/test the base schema and marketplace patches, including Needs.
2. Run the standalone migration as the database owner in staging:

   ```sh
   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/patch_migrate_existing_post_expiry_v1.sql
   ```

   The same file can be pasted into the Supabase SQL editor; it manages its own transaction.
3. Review the before/after status counts, totals by market, updated/expired counts, terminal-status comparison, missing/invalid values, sample rows, and manual-review rows printed by the migration. Stop for review if the settings preflight fails or if unknown Needs categories/timestamps are reported.
4. Confirm the cron notice and the public-feed/RPC checks. If `pg_cron` is unavailable, enable it through the database's supported extension process and schedule `SELECT * FROM private.expire_marketplace_posts_v1()` every five minutes.
5. Run the migration a second time in staging. Correct data should report zero expiry updates and zero newly expired posts on this repeat run.
6. Only after staging verification, run the exact same file against production. Verify the emitted results there; no production execution is implied by this repository change.

No expiry-reminder sender was found in the repository. The migration emits no notifications and creates no reminder records. If the deployed notification worker sends two-day reminders, it must check that the post is still active, the current expiry cycle is due, and that cycle has not already been notified; it must exclude matched, cancelled, and expired posts.

### Verification record

The migration was executed against an isolated local PostgreSQL 15 fixture modeled on the repository schema (not production and not a full Supabase stack). First run: 3 Loans, 3 Forex, and 5 Needs examined; 2/2/3 expiry dates updated; 1 active post in each market became expired; one contracted Loan, one contracted Forex, and one matched Need remained terminal. The fixture contained no missing listing timestamps or expiry dates and one unmapped `financial_services` Need, which was skipped and reported. A supplemental run nulled one active expiry in each market; all three were restored from `listed_at`, and the following rerun updated zero dates and expired zero additional posts. Feed and Provider Opportunities expiry checks, insert-duration checks (30/7/category duration), valid live offer/acceptance transitions, and rejection of offers/acceptance for expired posts passed with Loan/Forex enum status types. Existing offer-validation triggers and acceptance RPCs remained present; one offer, review, and audit fixture row per table remained present. These are fixture results only; production record counts must come from the production run.

## 4.5 Post duration info card (Flutter UI)

Every request-creation screen now shows a compact informational widget telling the user how long their post will stay active. The duration is read directly from `PlatformLimits` (backed by `system_settings`), so it always matches the server-enforced expiry.

### Where it appears

| Screen | Step / location | Duration shown |
|---|---|---|
| Loan create (`listing_create_page.dart`) | Bottom bar — step 3 (final review) | 30 days |
| Forex create (`forex_create_page.dart`) | Above the Submit button + in the preview dialog | 7 days |
| Needs create (`needs_create_page.dart`) | Above the Post button + in the preview dialog | Category-specific (7 or 14 days); updates immediately when category changes |

### Widget — `PostDurationInfoCard`

Located at `lib/shared/widgets/post_duration_info_card.dart`. Accepts `durationDays` (int) and `compact` (bool). Uses `Theme.of(context)` colour tokens throughout — no hardcoded hex values. Supports all 5 app locales (`en`, `sw`, `fr`, `rw`, `ar`) and both light and dark themes.

### No database changes

The card is purely informational. Expiry enforcement remains in the server-side trigger `trg_fn_set_listing_expiry()` (patched in §4.4).

### New localization keys

| Key | Example (en) |
|---|---|
| `postDurationActiveDays(days)` | "Active for 30 days" |
| `postDurationFullNotice(days)` | "Your request will be active for 30 days." |
| `postDurationNotice` | "Your request will automatically expire after this period." |

### Tests

- `test/shared/widgets/post_duration_info_card_test.dart` — widget tests across all durations, compact/full modes, dark/light themes, and all 5 locales.
- `test/features/settings/platform_limits_test.dart` — unit tests for `PlatformLimits.durationForNeedsCategory` covering all approved Needs categories, the unknown-slug fallback, custom-map overrides, and `listingDurationDays` / `forexListingDurationDays` defaults.

## 4.6 Provider Services and Work Profiles

Provider capability declarations are separate from provider verification. Individuals use the roles, kinds, qualifications, and proof flow. Company / Organization users select grouped category services and may select personal work roles in the same step, then continue directly to company details; roles do not enter the individual kinds/qualifications steps. There is no intermediate Review services screen. Existing personal work profile metadata is preserved. Company profile and verification submissions are private to their owner and Nipanze administrators.

Company details, selected services, and work roles save through one transaction. Company registration and authorization documents are submitted separately for manual company review; they never verify or activate a regulated service. Individual service and role evidence stays attached to its capability. The private `provider-evidence` bucket accepts JPG, PNG, and PDF files up to 5 MB. The Admin dashboard's Provider evidence tab reviews individual capability evidence and separate company documents, with rejection reasons and reviewer timestamps.

Capability verification policy is configured per catalog capability as `open`, `optional_proof`, or `required_proof`. Required-proof capabilities remain inactive until all configured evidence is approved. Offers, opportunity matching, and provider badges filter inactive or company-only capabilities on the backend. Unverified capabilities do not display a “Self-declared” label.

Apply `sql/patch_provider_capability_evidence_security.sql` and `sql/patch_company_provider_path.sql` after the existing provider services/evidence patches. Then apply the standalone `sql/patch_provider_verification_policies.sql` patch. It adds per-capability policy and activity state, separate company verification submissions, private upload and admin review RPCs, and backend offer/matching gates. Do not deploy these patches to production without the required deployment approval.

Provider Services remain the service-offering surface: selected services and personal work roles are stored in `provider_capabilities` and continue to gate Needs offers server-side. Work-seeking is modeled separately by the standalone patch `sql/patch_job_seeking_profiles.sql`.

Provider identity is selected per category. The identity chooser keeps the saved Individual or Company / Organization type selected, and changing it requires an explicit confirmation and review before the server switches active service capabilities atomically. Individual providers offer personal roles; company service rows remain saved but inactive under Individual. Old service rows, their evidence, personal work roles, and other category identities are retained. Public presentation uses only the approved display name; private company records and evidence remain protected. Apply `sql/patch_provider_identity_switch.sql` after `sql/patch_provider_category_type.sql`, `sql/patch_company_provider_path.sql`, and `sql/patch_provider_verification_policies.sql`; validate it in staging before rollout.

The new patch adds owner-private `job_profiles`, `job_profile_roles`, `job_profile_role_work_types`, and `job_profile_qualification_answers` tables plus `v_my_job_profiles`. These records describe the work a user wants, the roles they qualify for, role-specific work types, self-declared qualifications, expected pay, availability, languages, and location preference. They do not grant Need-offer permissions and do not create an admin-verified provider badge.

The `/account/services` screen now shows a separate Work Profile section behind the public `job_profiles_enabled` setting. Job matching is intentionally shown as unavailable until a real jobs/opportunity source exists; no fake listings or match percentages are generated.

Apply order:

1. Apply the existing Needs/provider capability SQL patches.
2. Apply `sql/patch_capability_profiles.sql` if capability roles/kinds/qualifications are not already present.
3. Apply `sql/patch_job_seeking_profiles.sql`.
4. Enable `system_settings.job_profiles_enabled` only after staging verification.
