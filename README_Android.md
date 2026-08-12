# Nipanze — Flutter + Supabase

## A Non-Custodial Digital Lending & Forex Matchmaking Marketplace — Launching in Uganda, Built for Africa

> Nipanze is a peer-to-peer financial marketplace that connects people who need money with people willing to lend, and people who hold one currency with people who need it, through structured requests, offers, and controlled contact sharing — without a bank, custodian, or intermediary holding any funds or currency. Live in Uganda first, architected on one shared schema and one shared app to expand across **Kenya, Tanzania, Rwanda, Nigeria, South Africa, and Egypt** — without a redesign.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Status: MVP](https://img.shields.io/badge/Status-MVP-blue.svg)
![Stack: Flutter + Supabase](https://img.shields.io/badge/Stack-Flutter%20%2B%20Supabase-purple.svg)

A cross-platform fintech app built with Flutter and Supabase, targeting Android, iOS, Web, and Desktop (Linux, Windows, macOS).

---

## Table of Contents

- [Overview](#overview)
- [Two Projects, One Platform](#two-projects-one-platform)
- [Problem Statement](#problem-statement)
- [Solution](#solution)
- [The Unified Marketplace Model](#the-unified-marketplace-model)
- [Multi-Market Architecture](#multi-market-architecture)
- [Currencies — Local, Cross-Border, and USD](#currencies--local-cross-border-and-usd)
- [Key Features](#key-features)
- [Business Model](#business-model)
- [Transparency & Controlled Contact](#transparency--controlled-contact)
- [Trust & Reputation Signals](#trust--reputation-signals)
- [Foreign Exchange (Forex)](#foreign-exchange-forex)
- [Marketplace Feed & Listing Design](#marketplace-feed--listing-design)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Screen / Route Map](#screen--route-map)
- [Database Schema](#database-schema)
- [Supabase Setup](#supabase-setup)
- [Getting Started](#getting-started)
- [Environment Configuration](#environment-configuration)
- [Key Packages](#key-packages)
- [Edge Functions](#edge-functions)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Regulatory Compliance](#regulatory-compliance)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

---

## Overview

Nipanze is a **peer-to-peer financial marketplace** built on a single, unified account model. There is no "borrower account" or "lender account" — every user sees the same marketplace and performs an action (**Post Request** or **Make Offer**) depending on what they click. Access to each action is gated purely by `subscription_plan`, not by any stored role.

As of v6.0, Nipanze runs on **one shared Supabase project and one Flutter app across every market it operates in**, and hosts **two feature-modules on that shared foundation — Loans and Forex** — see [Two Projects, One Platform](#two-projects-one-platform). Uganda is the launch market; Kenya, Tanzania, Rwanda, Nigeria, South Africa, and Egypt are the planned expansion markets, in that order. A user's marketplace defaults to their own country; posting, browsing, offers, and trust signals all carry a `country` value that's enforced at the data layer, not just filtered in the UI. See [Multi-Market Architecture](#multi-market-architecture).

Nipanze does **not** hold funds, accept deposits, issue loans, pool capital, guarantee repayment, track repayments, convert or hold currency, guarantee exchange rates, or act as a financial institution or currency broker, in any market it operates in. It simply helps financial requests and offers — loan or forex — meet through structured discovery, matching, and controlled connection.

Posting a request (loan or forex) is free for everyone. To post either a loan request (`/listings/create`) or a forex request (`/forex/create`), users must complete identity verification (`kycApproved`). An upfront, multilingual **KYC Gate Screen** (`KycGateScreen`) intercepts unverified users before they enter either creation form, explaining status and step-by-step guidance. Document upload (`/kyc`) uses cross-platform byte streaming (`XFile.readAsBytes()` + `uploadBinary`), ensuring full compatibility across Chrome/web, mobile, and desktop without `dart:io` runtime failures. Action buttons across forms and upload screens are strictly disabled until all required inputs are populated. The entire app, including the KYC gate, is fully localized across 5 languages (**English, French, Arabic, Kinyarwanda, and Swahili**). Making offers requires the **Lender** plan. Suggesting preferred terms on a posted request requires the **Pro** plan. Contact details remain hidden until a contract is generated after an offer is accepted. Listing detail itself uses **tiered visibility** — see [Transparency & Controlled Contact](#transparency--controlled-contact) — so exact offer terms are only visible to the request owner and to other offer-makers competing on that same listing.

**Core Principle:** One marketplace per country, one shared platform underneath, two feature-modules on top. Capability comes from your subscription plan; your default feed comes from your country; which module you're using (Loans or Forex) comes from what you click — none of these is a fixed identity baked into separate infrastructure.

---

## Two Projects, One Platform

Nipanze ships **Loans** and **Forex** as two distinct feature-modules — each with its own request/offer tables, its own create-request flow, its own listing-card design, and (in BUILD_PLAN.md) its own stage checklist and exit criteria — running on **one shared app, one shared Supabase project, and one shared account system.** This is not two apps wearing the same logo, and it's not a single blended feature either. It's the middle path:

| Shared (one platform) | Separate (two projects) |
|---|---|
| Auth, `profiles`, `subscription_plan`, `is_admin` | `loan_requests` / `loan_offers` vs `forex_requests` / `forex_offers` |
| `countries`, `currencies`, `system_settings` | `features/loans/` vs `features/forex/` Flutter modules |
| Trust & reputation (`trust_aggregates`, `reviews`) | Listing-card design (funded-% progress bar vs Send/Rate/Receive panel) |
| Selective transparency machinery (same RLS/RPC pattern) | Create-request form (loan terms vs currency pair + rate) |
| Contracts, contact reveal (`accept_offer`, `reveal_contact`) | Per-module RLS/RPC pairs (`v_lender_offers`/`get_public_listing_offers` vs `v_forex_offers`/`get_public_forex_offers`) |
| Watchlist, Positions, Notifications, KYC, Admin | Per-module regulatory review, per market (`countries.is_active` for lending, `countries.forex_enabled` for forex, independently toggled) |
| One `Marketplace` screen, filterable by module | Per-module launch sequencing (a market can go live for Loans before Forex, or vice versa) |

**Why this split, not full separation:** a request owner and an offer-maker shouldn't need two accounts, two logins, or two apps to do two closely related things — post a need, get offers, agree terms, get introduced. Full separation would mean re-implementing auth, trust, contracts, and contact-reveal twice for no product benefit. **Why not fully blended either:** a loan and a currency exchange are different enough in shape (loan terms vs. exchange rate; funded-% progress vs. Send/Rate/Receive) that force-fitting them into one generic "request" schema and one generic listing card would make both worse. Two tables, two forms, two card layouts — one everything else.

This mirrors the marketplace mockup: **one Marketplace screen, one `All / Loans / Forex` filter row, one bottom nav** — but a `Loan` badge and a `Forex` badge render structurally different cards underneath.

---

## Problem Statement

Across Uganda and Nipanze's planned expansion markets, access to affordable capital — and to fair currency exchange — faces critical barriers:

- **Long bank procedures:** Formal approvals can take too long for urgent needs
- **Lack of collateral:** Many people needing funds cannot meet traditional security requirements
- **Limited financial history:** Thin credit files exclude people with real repayment ability
- **High interest rates:** People needing funds lack flexible, competitive alternatives
- **Limited visibility:** People willing to lend struggle to find requests and assess repayment ability
- **Weak lending structure:** Informal lending lacks a reliable marketplace for discovery, offers, and connection
- **Poor exchange rates and bureau spreads:** Bank and bureau-de-change rates often sit well off the rate two individuals could agree on directly, and cross-border/diaspora currency needs are common but poorly served
- **Fragmented markets:** Cross-border and diaspora lending and currency-exchange relationships already exist informally (East Africans, Nigerians, South Africans, and Egyptians abroad funding family back home, or converting currency person-to-person) but have no structured platform to happen on safely

Many lending options still focus on collateral and institutional gatekeeping instead of giving people a structured way to show income, intent, and repayment plans — and almost none are built to serve more than one country, or more than one type of financial matchmaking, without becoming a different product per market or per use case.

---

## Solution

Nipanze provides a single marketplace structure — replicated per country on shared infrastructure, and covering both loan and forex requests — where:

- Anyone can publish a structured funding or currency-exchange request for free, in their own country and currency
- Every loan request includes loan details, source of income, loan purpose, and repayment ability; every forex request includes the currency pair, amount, and optional preferred rate
- Anyone can browse listed requests for free, defaulting to their own country with the option to browse other active markets
- Making an offer requires the Lender plan; the offer carries the offer-maker's own amount and terms (interest/return expectation for loans, exchange rate for forex), in the request's currency
- The request owner reviews available offers and accepts the one that fits
- Contact details are revealed only after the request owner accepts an offer
- Both parties connect outside the platform
- The platform supports discovery, matching, and controlled contact sharing — nothing more, in every market it serves, for either request type

**We are not a lender, a broker, or a bureau de change. We are a matchmaking marketplace — one platform, one region at a time, two ways to match: money now for money later, or currency you have for currency you need.**

---

## The Unified Marketplace Model

Nipanze moved away from a role-based design (`borrower` / `lender`) to a **unified, action-based** model. This section is the source of truth for how capability works across the app — see [BUILD_PLAN.md](BUILD_PLAN.md) for the full rationale and migration history.

### The decision

- One interface for every user — no separate borrower/lender screens or signup paths
- No `role` column stored on the account
- Users choose a **subscription plan**, not an identity
- The same person can post a request *and* make offers, at any time, from the same login, in any country their account belongs to, on either the Loans module or the Forex module

### Single entry point after login

Every user lands on the same dashboard:

1. **Marketplace** — all loan and forex listings for the user's active country, filterable by `All / Loans / Forex`
2. **Post Request** — always visible, Free tier and up, choosing Loan or Forex when posting
3. **Offers Panel** — offers *received* on your requests, and (if your plan allows) offers *you've made* on others' requests, across both modules

There is no "select your role" step anywhere in the app. A user simply acts:

- Clicks **Post Request** → picks Loan or Forex → acting as the request owner for that listing
- Clicks **Make Offer** → acting as the offer-maker for that listing, loan or forex

### Feature access by plan

| Plan | Access |
|---|---|
| 🟢 **Free** | Post basic loan or forex requests (loan: amount, duration, purpose with live repayment math calculation · forex: currency pair, amount, settlement preference) · Browse marketplace · Accept received offers · Watchlist, Positions, Notifications, KYC · Full visibility into public trust signals on every profile · ❌ Cannot make offers · ❌ Cannot suggest terms when posting (lenders propose terms; borrower detail shows `—` when no terms suggested) |
| 🔵 **Lender** | Everything in Free, **plus**: make offers on any listing, loan or forex (in-country or cross-border, see [Multi-Market Architecture](#multi-market-architecture)) · set interest rate, late payment fee, and repayment schedule on loan offers · set exchange rate, available amount, and terms on forex offers |
| 🟣 **Pro** | Everything in Lender, **plus**: suggest terms when posting a request — interest rate, late fee, and repayment schedule for a loan request, or a preferred exchange rate for a forex request · priority visibility for posted requests · live comparison sparklines & delta analytics · Sponsored post support · improved matching · Verified badge · advanced trust insights |

No plan is ever labeled "Borrower Plan," "Lender-only," or "Forex Plan," and no plan is ever country- or module-specific — a single `subscription_plan` applies to the account regardless of which country's marketplace they're viewing or whether they're acting in Loans or Forex. Each plan name describes the *unlocked capability*, not the person holding it or the module. A single user can hold only **one** `subscription_plan` at a time (`free | lender | pro`), and Pro is a strict superset of Lender, which is a strict superset of Free.

### The one exception: `is_admin`

`is_admin` is a true role, separate from the subscription plan, since it governs platform moderation rather than marketplace participation. It is the **only** role in the system, and admin access spans every country and both modules.

---

## Multi-Market Architecture

Nipanze runs on **one shared Supabase database and one set of tables for every country it operates in** — not a separate database, project, or table set per market, and not a separate schema per module. This section explains the design and why. Full schema-level detail lives in [BUILD_PLAN.md](BUILD_PLAN.md#-multi-market-expansion-model-v60).

### Scope: Uganda first, then six planned markets

Nipanze's launch and expansion plan spans **seven countries across three African regions**, not a single trading bloc — a deliberate shift from an earlier East-Africa-only framing:

| Country | Code | Currency | Currency Code | Phone Prefix | Region |
|---|---|---|---|---|---|
| 🇺🇬 Uganda | `UG` | Ugandan Shilling | `UGX` | `+256` | East Africa — **launch market** |
| 🇰🇪 Kenya | `KE` | Kenyan Shilling | `KES` | `+254` | East Africa |
| 🇹🇿 Tanzania | `TZ` | Tanzanian Shilling | `TZS` | `+255` | East Africa |
| 🇷🇼 Rwanda | `RW` | Rwandan Franc | `RWF` | `+250` | East Africa |
| 🇳🇬 Nigeria | `NG` | Nigerian Naira | `NGN` | `+234` | West Africa |
| 🇿🇦 South Africa | `ZA` | South African Rand | `ZAR` | `+27` | Southern Africa |
| 🇪🇬 Egypt | `EG` | Egyptian Pound | `EGP` | `+20` | North Africa |

All seven are seeded in the `countries` table from the Stage 4.5 migration onward. Uganda is the only market with `is_active = TRUE` at launch; the other six activate independently, in the order listed above, as each clears its own pricing, payment-rail coverage, and compliance review — see [Roadmap](#roadmap). Seeding all seven up front means the country picker, admin per-country settings, and currency-formatting logic never need a schema change to support a market that hasn't launched yet.

> **This list replaces an earlier East African Community (EAC)-only framing.** Burundi, South Sudan, DR Congo, and Somalia — previously scoped as EAC-completeness markets — are not currently on Nipanze's roadmap. The schema pattern below still supports adding any of them later the same way any new country is added (one row insert), but they are not part of the current seven-market plan.

### Why one shared schema, not one per country

A per-country table design (`loan_requests_uganda`, `loan_requests_nigeria`, …) was considered and rejected: it would multiply every RLS policy, trigger, view, and RPC in this schema by the number of countries, turn cross-market admin reporting into a UNION query across up to seven tables, and make launching a new country a migration project instead of a one-row data insert. Instead:

- **One `countries` reference table** (`code`, `name`, `currency_code`, `phone_prefix`, `is_active`, `forex_enabled`) — adding a new market is one row insert (already done for all seven); *launching* lending in a market is one `UPDATE ... SET is_active = TRUE`; *launching* forex in a market is the independent `forex_enabled` flag
- **`profiles.country`, `loan_requests.country`, and `forex_requests.country`** — indexed, non-nullable columns that make every user and every listing's market explicit and queryable
- **`loan_offers` and `forex_offers` have no country of their own** — an offer's country is always its parent request's country, read through the join, so there's exactly one source of truth for "what market is this offer in," not one that can drift out of sync across seven markets or two modules

### How filtering works

A user's marketplace feed defaults to their own `profiles.country`, across both Loans and Forex. A Nigerian user sees Nigerian listings by default; a South African user sees South African listings by default — and so on for all seven markets. This is enforced at the application query layer (`MarketplaceRepository` filters `v_loan_listings WHERE country = :userCountry` and `v_forex_listings WHERE country = :userCountry`), with an explicit, user-initiated option to browse other active markets — a deliberate choice over hard per-country RLS isolation, because diaspora and cross-border lending and currency exchange (funding a family request back home, or converting currency for someone back home, from elsewhere in the region) is a real, valuable use case this design wants to support rather than block. Forex, being inherently cross-currency, leans on this browse-other-markets path more than loans do — see [Foreign Exchange (Forex)](#foreign-exchange-forex).

### Regulatory diversity across these seven markets is real — flagged, not glossed over

Unlike the earlier EAC-only framing, where all target markets shared a regional bloc and broadly similar mobile-money-led payment landscapes, this seven-market list spans **materially different regulatory regimes and payment landscapes**: East Africa's mobile-money-dominant rails differ from Nigeria's card/bank-transfer-and-fintech-native rails, South Africa's mature card/EFT banking system, and Egypt's currency-control history around the EGP. Nipanze is not a law firm and this document does not constitute legal advice — every market on this list needs its own local regulatory review before `countries.is_active` (lending) or `countries.forex_enabled` (forex) is flipped, and that review should be treated as **more consequential** now than it was under a single-bloc EAC plan, not routine. See [Regulatory Compliance](#regulatory-compliance).

### What stays global regardless of country

Public trust signals (rating, review count, completed-deal count, badges) reflect a user's **entire on-platform history across every market and both modules**, not a per-country or per-module reset — a lender's track record follows them whether they're browsing Kenya for the first time or their tenth deal in Uganda, and whether that history is loan deals, forex deals, or a mix of both. See [Trust & Reputation Signals](#trust--reputation-signals).

### Launching a new market

Adding a country requires **no schema migration** — all seven are already seeded. Launching lending in one is: flip `countries.is_active` to `TRUE`, finalize that market's `system_settings` overrides and local-currency subscription pricing, confirm payment-rail coverage with the chosen aggregator for that specific country, and localize KYC document-type expectations at the app layer. Launching forex in that same market is a **separate**, independently-timed decision — flip `countries.forex_enabled` only after its own currency-exchange-facilitation compliance review, which can clear on a different timeline than lending. See [BUILD_PLAN.md](BUILD_PLAN.md) Stage 4.5, Stage 4.7, and Stage 6 for the full migration and per-market launch checklist.

---

## Currencies — Local, Cross-Border, and USD

Nipanze's `currencies` reference table is decoupled from `countries` on purpose, because currency questions turned out to be more granular than "one country, one currency":

| Question | Answer | Where it's decided |
|---|---|---|
| Can I post a loan request in my own country's currency? | Always yes | Default — no flag needed |
| Can I post a loan request in USD instead of my local currency? | Only where the market allows it | `system_settings.allow_foreign_currency_loans` (per country) — a loan is not a currency trade, so this is a lighter check, mainly about that country's rules on foreign-currency-denominated P2P lending |
| Can I pay my subscription in USD instead of local currency? | Yes, wherever offered | Pure billing-currency choice — no different in kind from billing in local currency |
| Can a forex request trade *into or out of* USD (or any currency)? | Only if that currency is explicitly cleared for forex trading | `currencies.forex_trading_enabled` — this is the one with real exposure to currency-exchange/bureau-style licensing, so it defaults to **off** for every currency until reviewed |

### `currencies` table

```sql
-- currencies (conceptual)
code                    TEXT PRIMARY KEY   -- ISO 4217, e.g. UGX, KES, TZS, RWF, NGN, ZAR, EGP, USD
name                    TEXT NOT NULL
is_market_currency      BOOLEAN NOT NULL DEFAULT FALSE   -- TRUE for the 7 currencies tied to a live/planned Nipanze country
market_country          TEXT REFERENCES countries(code)  -- set only when is_market_currency = TRUE
forex_trading_enabled   BOOLEAN NOT NULL DEFAULT FALSE    -- gates use in a forex_requests pair, independent of loan usage
created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
```

Seed: the seven market currencies (`UGX`, `KES`, `TZS`, `RWF`, `NGN`, `ZAR`, `EGP`) plus `USD`. All eight rows exist from the Stage 4.5 migration; `forex_trading_enabled` starts `FALSE` for every one of them, including the market currencies — a currency being someone's home currency does not automatically clear it for cross-border forex trading, which needs its own review even for UGX-vs-KES. This keeps "add a currency to the reference table" and "clear a currency for forex trading" as two separate, deliberately un-bundled decisions.

### Why this shape, not one flag on `countries`

A single `countries.currency_tradeable` flag was considered and rejected, because it conflates two different things: whether a currency exists in Nipanze's vocabulary at all (needed for loans and subscriptions, lower stakes) versus whether it's cleared to appear in a forex pair (needed only for Forex, higher stakes, closer to bureau-de-change territory). Splitting them means Nigeria's NGN can be fully usable for NGN-denominated loans and NGN subscription billing on day one, while NGN's forex-trading clearance is reviewed and flipped on its own timeline — without touching the Loans module at all.

---

## Key Features

### Posting a Request (Free plan and above)

- **Free access** — post loan or forex requests without paying to list, in any active market
- **Structured loan requests** — title, amount, duration, purpose, district, income source, and repayment ability, in the requester's local currency by default, or USD where `allow_foreign_currency_loans` permits
- **Structured forex requests** — currency held, currency needed, amount, optional preferred rate, and settlement preference, limited to currency pairs where both currencies have `forex_trading_enabled = TRUE`
- **Repayment visibility** — show the marketplace how a loan will be repaid
- **Flexible outcomes** — receive and compare offers from multiple lenders or offer-makers
- **My Requests** — track posted loan and forex requests and responses in one place (Positions tab)
- **Controlled contact** — personal contact details stay hidden until an offer is accepted, on either module

### Making Offers (Lender plan and above)

- **Free browsing** — review requests before subscribing to the Lender plan
- **Repayment context** — assess loan purpose, requested amount, duration, and repayment plan; or currency pair, amount, and requested rate for forex
- **My Offers** — manage loan and forex offer activity in one place (Positions tab)
- **Custom terms** — offer your own amount, interest rate, late payment fee, and repayment schedule for loans (locked on submit); offer your own exchange rate, available amount, and settlement terms for forex (also locked on submit), denominated in the listing's currency
- **Cross-border capital** — offer on listings outside your home country, subject to the platform's current cross-border policy (see [BUILD_PLAN.md](BUILD_PLAN.md)) — the default and primary path for forex offers
- **Return potential** — fund selected loan requests directly, or exchange currency directly

### Suggesting Terms (Pro plan)

- **Negotiating leverage** — suggest a preferred interest rate, late payment fee, and repayment schedule when posting a loan request, or a preferred exchange rate when posting a forex request (locked on publish)
- **Priority visibility** — Pro-posted requests get improved placement and matching, in whichever market they're posted, Loans or Forex

### Platform Features

- **Free posting** — anyone can create a loan or forex request without a listing fee, in any active market
- **Free browsing** — anyone can browse requests before subscribing, defaulting to their own country
- **Subscription-gated offers** — making offers requires an active Lender (or Pro) plan, independent of country or module
- **Locked bidding** — both suggested posting terms and offer terms are locked on submission; no post-publish edits, for loans or forex
- **Contract generation** — a digital contract (loan agreement or exchange agreement) is auto-generated when a request owner accepts an offer
- **Single account, one dashboard** — every user posts and offers from the same account and screen, in every country their profile belongs to, across both modules
- **Marketplace main screen** — live feed of loan and forex requests, filterable by `All / Loans / Forex`, each with its own card design — see [Marketplace Feed & Listing Design](#marketplace-feed--listing-design)
- **Non-custodial architecture** — Nipanze never holds, pools, converts, or moves user funds or currency, anywhere
- **Controlled contact sharing** — contact details are revealed only after a contract is generated, loan or forex
- **Selective transparency** — listing detail shows broad listing signals to non-participants, keeps offer count/coverage visible to the request owner, and unlocks exact offer terms only for the request owner and for offer-makers who have themselves bid on that listing
- **Public trust signals** — rating, review count, completed-deal count, repeat-participant badge, and phone-verification status are visible on every profile, free, regardless of plan, country, or which module the deal history comes from — see [Trust & Reputation Signals](#trust--reputation-signals)
- **Pro Advanced Filters** — Pro-tier users can use advanced filters (categorical employment type, bucketed income range, suggested-terms, owner KYC verification status) next to the notification bell, with database-level self-gating
- **Compliance built-in** — append-only audit trail from day one, across both modules

---

## Business Model

Nipanze generates revenue primarily through subscriptions — not interest spreads and not currency-exchange spreads — via a single upgrade path, applied consistently across every market and both modules (Loans and Forex). A small, clearly-disclosed contact-unlock fee is under consideration as a secondary revenue lever; see [Trust & Reputation Signals](#trust--reputation-signals) for how it would fit alongside subscriptions without becoming a fee tied to loan performance or exchange rate.

| Plan | Unlocks |
|---|---|
| 🟢 **Free** | Post basic requests (loan: amount, duration, purpose · forex: currency pair, amount) · browse · accept offers received · full visibility into every counterparty's public trust signals |
| 🔵 **Lender** *(subscription)* | Everything in Free + make offers with full terms — loan (amount, interest, late fee, schedule) or forex (rate, amount, terms) |
| 🟣 **Pro** *(subscription)* | Everything in Lender + suggest terms when posting a request (loan interest/late fee/schedule, or forex preferred rate) + priority visibility + improved matching + verified badge + advanced trust insights |

Users pay to unlock offer-making (Lender), and pay more to also unlock posting leverage and stronger trust signaling (Pro) — identically whether they're active in Loans, Forex, or both. A single `subscription_plan` enum drives all of it — there is no separate "Forex Plan" or "Premium Borrower" product. The plan tiers and what they unlock are identical across every market and both modules; only the **subscription price** varies by market and currency.

**Local subscription pricing is configured per country/currency and finalized by admin for each market.** A UGX amount is never reused as the same numeric price in NGN, ZAR, EGP, or another market's currency; each market's published price reflects its own local willingness-to-pay and launch readiness. `subscriptions.amount_minor_units` is currency-agnostic on its own and only meaningful together with the subscriber's `profiles.country` (or, if the user opts into USD billing, `currencies.code = 'USD'`). There is no separate forex subscription price — the same `subscriptions` row and price point governs offer-making and term-suggestion for both Loans and Forex.

Nipanze does **not** earn interest margins, custody fees, lending spreads, exchange-rate spreads, or any fee tied to loan or exchange performance, in any market. Any future contact-unlock fee is a flat, disclosed marketplace-access fee — never priced off a deal's interest rate, exchange rate, amount, or outcome.

**Payments (Stage 6):** subscription charges (and, if adopted, the contact-unlock fee) are processed via Flutterwave, Paystack, or a comparable aggregator, covering mobile money, cards, and bank transfer/EFT rails as appropriate per market. This is scoped **strictly to Nipanze's own revenue** — it never touches money or currency exchanged between two matched users, which stays off-platform per the non-custodial model above, for both loans and forex. Rail coverage varies significantly by country across this seven-market list — see [Multi-Market Architecture](#multi-market-architecture) — so each market's aggregator support is verified before that market's `is_active` flag is flipped, rather than assumed from another market's success.

---

## Transparency & Controlled Contact

Nipanze is **transparent before matching and controlled by design**, in every country it operates in and for both Loans and Forex. Requests show enough structured information for potential counterparties to make informed decisions, while personal contact details remain protected until the request owner accepts an offer, and exact offer terms remain protected until a viewer has skin in that specific deal.

Contact details are revealed **only after an offer is accepted** — enforced at the API layer, not just the UI.

### Request Structure

Each **loan** request must include:

- **Loan details:** request title, amount needed, duration, purpose, and district
- **Source of income:** salary, business income, side income, or other repayment source
- **Repayment preference:** weekly, monthly, or one-time payment
- **Repayment ability:** amount payable per period and structured repayment timeline (including specific Due Day of month/week and Due Cutoff Time for precise late-payment fee timing)
- **Currency:** the requester's local currency by default, or USD where the market's `allow_foreign_currency_loans` setting permits it

Each **forex** request must include:

- **Currency held** and **currency needed** — both must have `forex_trading_enabled = TRUE` in `currencies`
- **Amount** to exchange
- **Settlement preference** — how and where the two parties intend to meet or settle, disclosed as a preference only, never brokered by the platform

Free-plan loan requests do **not** carry interest rate, late payment fee, or repayment schedule — lenders set all terms in their offers. Free-plan forex requests do **not** carry a target rate — offer-makers propose their own rate.

Pro-plan loan requests can additionally suggest a preferred interest rate, late payment fee, and repayment schedule. Pro-plan forex requests can additionally suggest a preferred exchange rate. Both are **locked on publish** and give the request extra negotiating leverage when offers come in.

### Selective Transparency Model

Listing detail pages use **tiered visibility**, not a single public/private split, for both loan and forex listings. Every visitor sees enough to gauge how competitive a request is; only people with skin in that specific deal see its exact offer terms. This tiering logic is identical in every country and for both modules — only the currency label (or currency pair) attached to the numbers changes.

| Viewer | What they see on a listing |
|---|---|
| **Visitor / any logged-in user browsing** | Loan: funded % (progress bar), number of offers, an aggregate coverage tier, and the full request summary — in the listing's own currency. Forex: currency pair, amount needed, number of offers, and an aggregate rate-coverage tier — never individual offered rates |
| **Lender/Pro-plan holder who has not offered on this listing** | Same as a visitor — full offer-level detail stays locked until they place an offer on this specific request |
| **Offer-maker who has placed an offer on this listing** | Everything a visitor sees, **plus** the exact terms of every offer on this listing — amount/interest/late-fee/schedule for a loan, or rate/amount/terms for forex — their competitive position against other offer-makers |
| **Request owner** | Full detail on every offer submitted to their request, whichever module it's from, plus offer timestamp |

Contact details stay locked for everyone, at every tier, until a contract is generated and unlock is confirmed — that boundary is unchanged by this model, by which country the listing is in, or by whether the listing is a Loan or a Forex request; selective transparency only governs *offer terms*, not identity.

Public trust signals (rating, review count, deal count, badges) are a separate, always-public layer that sits on top of this model — see below.

### Field Masking Rules

#### Public Loan Listing (`v_loan_listings` view)

**Exposed:** `request_id`, `title`, `purpose`, `district`, `country`, `currency_code`, `duration_months`, `requested_amount`, `preferred_repayment_plan`, `repayment_amount_per_period`, `repayment_timeline`, `listed_at`, `expires_at`; `number_of_offers` and `offer_coverage_tier` are borrower-only on listing detail

**Masked before acceptance:** request-owner id, income source, employer/salary details, email, phone, full name, national ID, and private verification documents

#### Public Forex Listing (`v_forex_listings` view)

**Exposed:** `request_id`, `currency_held`, `currency_needed`, `amount`, `country`, `settlement_preference`, `number_of_offers`, `rate_coverage_tier`, `listed_at`, `expires_at`

**Masked before acceptance:** request-owner id, email, phone, full name, national ID, and private verification documents

#### Loan Offers (`v_lender_offers` view) — participant-gated detail

**Exposed only to the request owner and to offer-makers who have themselves placed an offer on that same request:** offer amount, interest rate, late payment fee, repayment schedule, timestamp

**Exposed to everyone:** total number of offers on the listing, and the aggregate `offer_coverage_tier`

#### Forex Offers (`v_forex_offers` view) — participant-gated detail

**Exposed only to the request owner and to offer-makers who have themselves placed an offer on that same forex request:** rate offered, amount available, settlement terms, timestamp

**Exposed to everyone:** total number of offers on the listing, and the aggregate `rate_coverage_tier`

#### Post-Acceptance Contact Sharing

Revealed only after the request owner accepts an offer and confirms unlock: legal name, phone, and email — regardless of country, and regardless of whether the underlying request was a loan or a forex exchange.

### Platform Boundary

Nipanze helps participants discover each other and make informed matching decisions, in whichever market they're in, for loans and for currency exchange alike. It does not handle money, convert or hold currency, track repayments, guarantee repayment, guarantee an exchange rate, or manage the relationship after contact details are revealed, anywhere.

---

## Trust & Reputation Signals

Selective transparency (above) governs *deal terms*. Trust & reputation signals are a separate, always-public layer that governs *counterparty credibility* — independent of deal-term visibility, country, and module. A user's trust profile spans every market they've used and both Loans and Forex — it does not reset at a border or between the two modules.

### Public trust signals (Free — visible to everyone, on every profile, in every market)

| Signal | Source | Notes |
|---|---|---|
| ⭐ Rating average + review count | Post-deal reviews left by the other party to a completed contract — loan or forex, across all countries | Only the counterparty on a completed deal can leave a review; one review per contract |
| 📊 Completed deals count | Count of contracts the account has been a party to (as owner or offer-maker), loan and forex combined, across all countries | Reflects on-platform activity, not repayment or settlement outcome |
| 🔁 Repeat participant badge | Awarded after a second completed deal, loan or forex, anywhere in the region | Signals an account is an active, returning marketplace participant |
| 📱 Phone verified badge | OTP verification at signup, tracked in `profiles.phone_verified_at` | Free, lightweight — distinct from full KYC |
| ⏱️ Typical response time | Rolling median time-to-first-action on offers/requests received, loan or forex | Computed server-side; shown as a bucket (e.g. "Responds quickly"), never an exact timestamp pattern |

A profile with no history yet renders these as **"No reviews yet"** and **"0 completed"** — the same badge slots, just at their zero-state, exactly as shown on fresh listings in the marketplace mockup — never hidden or omitted.

### Pro-tier trust enhancements (monetized layer)

| Enhancement | Plan | Description |
|---|---|---|
| 🟦 Verified badge | Pro | Awarded after full KYC review, distinct from and stronger than the free phone-verified badge |
| 📊 Offer/request success rate | Pro | Share of an account's offers accepted, or requests that reached a contract, computed across all markets and both modules |
| 🚀 Priority visibility | Pro | Pro-posted requests and Pro offer-maker profiles get improved placement, loan or forex |
| 🔍 Reliability score | Pro | A single derived score combining rating, completion count, and response time, shown only to Pro viewers looking at a counterparty |

### Reviews

- A review can only be left by the counterparty on a **completed contract**, loan or forex (one review per contract, per direction)
- Reviews are a star rating (1–5) plus optional short text
- Reviews are immutable once submitted and logged to `audit_logs`

---

## Foreign Exchange (Forex)

Nipanze extends the same unified marketplace model beyond lending to **peer-to-peer foreign exchange (forex) requests** — connecting people who hold one currency and need another with people willing to exchange, directly, without a bank or bureau de change sitting in the middle. Forex is the second of Nipanze's two modules — see [Two Projects, One Platform](#two-projects-one-platform) — running on the same shared schema, subscription plans, and non-custodial boundary as Loans.

**Core Principle:** Forex is matchmaking, not exchange. Nipanze never holds, converts, or moves currency on anyone's behalf, in any market.

### Fits the existing unified model

- **Post a Forex Request** — free, same as posting a loan request
- **Make a Forex Offer** — requires the Lender plan, same as making a loan offer
- **Suggest a preferred rate** on a posted forex request — requires the Pro plan
- One dashboard, one Positions tab, one `subscription_plan` gates both modules identically

### Request structure

A forex request specifies:

- **Currency held** and **currency needed** — both must have `forex_trading_enabled = TRUE`
- **Amount** to exchange
- **Preferred rate** (optional) — Pro-only field, locked on publish
- **Settlement preference** — in-person, mobile money, bank transfer, or other off-platform method, disclosed as a preference only

An offer against a forex request specifies:

- **Exchange rate offered**
- **Available amount**
- **Terms** (settlement method, timing) — locked on submit

### Cross-border and cross-currency by nature

A forex request is inherently about two currencies, and the primary use case (diaspora/cross-border transfer) is inherently cross-border. A Uganda-registered user can post `UGX → KES`, `UGX → NGN`, or `UGX → USD` (where USD is cleared for trading), just as a Nigeria-registered user might post `NGN → ZAR`. `forex_requests.country` still tells you *where the requester is*; it never constrains *which two currencies* the request is about. Nipanze does **not** perform the conversion or quote a "platform rate" anywhere — every rate shown is a specific offer-maker's own proposed rate.

### Selective transparency and trust — same model, no exceptions

Forex listings use the identical tiered-visibility model as loans (see [Transparency & Controlled Contact](#transparency--controlled-contact)) and feed the identical global trust aggregate as loans (see [Trust & Reputation Signals](#trust--reputation-signals)). A user's forex deal history and loan deal history contribute to one combined reputation, not two separate scores.

### Non-custodial by design

- **Does not** hold, pool, or transfer either currency, at any point
- **Does not** act as a broker, dealer, or counterparty to the exchange
- **Does not** guarantee a rate, quote a platform rate, or guarantee the exchange completes
- **Does not** touch settlement — cash, mobile money, or bank transfer between the two parties happens entirely off-platform, after contact is revealed

### A genuinely separate compliance surface

Currency-exchange facilitation can carry its own licensing requirements distinct from loan matchmaking, even within a market where lending is already cleared — this is why `countries.forex_enabled` is a flag independent of `countries.is_active`, and why `currencies.forex_trading_enabled` is independently gated per currency (see [Currencies](#currencies--local-cross-border-and-usd)). Uganda launching with lending active does not imply Uganda launches with forex active on day one.

### Schema

| Table | Purpose |
|---|---|
| `forex_requests` | Structured exchange requests: `currency_held`, `currency_needed`, `amount`, optional `preferred_rate` (Pro-only, locked on publish), settlement preference, `country` (locked at insert, same trigger pattern as `loan_requests`) |
| `forex_offers` | Offers against a forex request: `rate_offered`, `amount_available`, `terms` (locked on submit) — no `country` of its own, read through `request_id → forex_requests.country` |

---

## Marketplace Feed & Listing Design

The Marketplace screen is the one shared surface where both modules meet — a live feed with an `All / Loans / Forex` filter row, and two structurally different listing-card layouts underneath depending on which module a listing belongs to.

### Filter row

`All` · `Loans` (🌾) · `Forex` (🔀) — three pill-style tabs above the feed; `All` interleaves both modules chronologically, `Loans` and `Forex` each show only their own module's listings. Filtering here is purely presentational — it's the same `country`-scoped queries against `v_loan_listings` and `v_forex_listings` described in [Multi-Market Architecture](#multi-market-architecture), just merged or split for display.

### Loan listing card

- **Badge:** `Loan` (green dot)
- **Meta line:** district/region · duration (e.g. "Eastern · 18 months")
- **Title** and **amount** (in the listing's currency)
- **One-line summary** (purpose)
- **Funded-% progress bar** and **"Xd left"** countdown
- **Offer countdown** on participant-visible offer rows, driven by `loan_offers.expires_at`
- **Localized detail copy** for listing terms, offer cards, collateral, countdowns, and profile-driven labels; currency labels come from the listing/user market instead of assuming UGX
- **Trust badges:** `⭐ No reviews yet` (or the real rating once it has one) and `💎 0 completed` (or the real count)
- **Star icon** (top-right) — save to watchlist

### Forex listing card

- **Badge:** `Forex` (blue dot)
- **Meta line:** location · turnaround (e.g. "Kampala · Instant")
- **Title** as a directional pair (e.g. "USD → UGX Exchange")
- **Headline amount** in the currency the requester needs
- **One-line summary**
- **Send / Rate / Receive panel** — three-part row: `You Send` (amount + currency held), the proposed/aggregate `Rate`, `You Receive` (amount + currency needed) — this replaces the loan card's funded-% bar, since a forex request doesn't have a "funded percentage," it has a rate
- **`⚡ Urgent` tag** — shown when a forex request is time-sensitive (e.g. near its `expires_at`, or explicitly flagged by the requester at posting — same urgency signal already used for watchlist closing-soon styling, surfaced here as an inline tag instead of a card border)
- **Trust badges:** same `⭐ No reviews yet` / `💎 0 completed` pattern as loan cards, since trust is module-agnostic
- **Star icon** (top-right) — save to watchlist

### Shared elements

- **Bottom navigation:** `Markets · Watchlist · Request · Positions · Account` — unchanged by the two-module split, since Positions and Watchlist already span both `loan_requests`/`forex_requests` and `loan_offers`/`forex_offers`
- **Request FAB:** center action opens the request-type choice (Loan or Forex) before branching into the module-specific create form
- **Live listing count + status dot** at the top of the feed (e.g. "16 listings • live") — counts across both modules when `All` is selected, or the filtered module's count when `Loans`/`Forex` is selected

---

## How It Works

```
1. POST       → User posts a structured loan or forex request for free, in their own country and currency
2. BROWSE     → Marketplace defaults to the user's country; browsing other active markets is optional
                 (default behavior for forex, given its inherently cross-currency nature)
                 → sees broad listing signals; request owners see offer count/coverage, while offer-makers unlock their own exact offer detail
3. OFFER      → Lender/Pro plan holders make offers with their own amount and terms —
                 interest rate/late fee/schedule for a loan, or exchange rate/amount/terms for forex
                 → Placing an offer unlocks full offer-level detail on that listing for that offer-maker
4. REVIEW     → Request owner compares available offers with full exact-term detail and each offer-maker's trust signals
5. ACCEPT     → Request owner selects one offer; contract is auto-generated
6. UNLOCK     → Contact details are revealed only after contract unlock
7. CONNECT    → Parties proceed independently outside the platform
8. RATE       → Both parties may leave a one-time review on the completed contract, feeding the reviewee's global trust signal
```

---

## Architecture

| Layer | Technology | Responsibility |
| --- | --- | --- |
| Frontend | Flutter 3.x + Dart | UI, state management, routing, local cache |
| State Management | BLoC + Cubit | Predictable unidirectional data flow |
| Navigation | GoRouter | Declarative routing with auth guards |
| DI Container | get_it + injectable | Service locator with code-gen |
| Auth | Supabase Auth | Email login, JWT, session management |
| Database | Supabase Postgres | Relational data, RLS, triggers, functions — one shared schema for every market and both modules |
| Realtime | Supabase Realtime | WebSocket updates for marketplace requests and offers, loan and forex |
| Storage | Supabase Storage | Optional profile and verification documents |
| Functions | Supabase Edge Functions (Stage 5) | Server-side logic, PDF generation |

---

## Project Structure

```
lib/
├── main.dart                       # Supabase init, DI setup
├── core/
│   ├── theme/                      # AppTheme — DM Sans / DM Mono, dark/light
│   ├── router/                     # GoRouter, auth redirect guards, route constants
│   ├── config/                     # SupabaseConfig — reads --dart-define at build time
│   ├── constants/                  # Tables, Views, Rpcs, Channels, SettingKeys, Countries, Currencies
│   ├── errors/                     # AppException hierarchy, parseSupabaseError()
│   └── di/                         # Injectable config, GetIt locator
├── features/
│   ├── auth/                       # Login, Register, Verify Email, Reset Password, Onboarding (incl. country select)
│   ├── dashboard/                  # Home stub (redirects to marketplace post-login)
│   ├── marketplace/                # Live feed (v_loan_listings + v_forex_listings), All/Loans/Forex filter, country filter
│   ├── loans/                      # 🟢 LOANS PROJECT — create loan request, my loan requests, loan detail, loan-specific widgets
│   ├── forex/                      # 🔵 FOREX PROJECT — create forex request, my forex requests, forex detail, Send/Rate/Receive widgets
│   ├── watchlist/                  # Saved listings (loan or forex), closing alerts
│   ├── positions/                  # My Requests · My Offers (same account, two views, both modules)
│   ├── account/                    # Subscription plan, profile, verification, country setting
│   ├── offers/                     # My Offers page (loan and forex offers)
│   ├── notifications/              # Notification centre, unread badge
│   ├── kyc/                        # Optional verification, status display, country-appropriate document types
│   ├── trust/                      # Trust badges, ratings, reviews, reputation summary (global, module-agnostic)
│   ├── profile/                    # User profile, edit
│   └── admin/                      # Verification review, user management, audit logs, per-country + per-module settings (admin only)
│       └── */
│           ├── data/               # DataSources (Supabase) + Models
│           ├── domain/             # Entities, UseCases, Repository interfaces
│           └── presentation/       # BLoC + Pages + Widgets
├── shared/
│   ├── models/                     # LoanListingModel, ForexListingModel, OfferModel, UserModel, TrustProfileModel, CountryModel, CurrencyModel…
│   └── widgets/                    # MainScaffold, ProfileSummary, VerificationChip, TrustBadgeRow, CurrencyLabel, SendRateReceivePanel
supabase/
sql/
│   ├── schema.sql                  # Full schema — tables, triggers, RPCs, views (multi-market, 7 countries, loan + forex, from v6.0)
│   └── seed.sql                    # Seed data — users, listings, offers (Uganda-only until Stage 4.5 seed additions)
│   └── migrations/                 # Incremental migrations, including Stage 4.5 (multi-market) and Stage 4.7 (forex)
assets/
    ├── fonts/                      # DM Sans (body) + DM Mono (numeric values)
    └── images/                     # Onboarding illustrations
```

> `features/loans` and `features/forex` are the two "projects" referenced throughout this README — separate directories, separate models, separate create-flows, separate listing-card widgets — sitting inside one shared app and calling one shared Supabase backend. `features/marketplace`, `features/positions`, `features/trust`, and `features/watchlist` are the shared surfaces that read from both.

---

## Screen / Route Map

| Route | Screen | Auth Required |
| --- | --- | --- |
| `/` | SplashPage | No |
| `/onboarding` | OnboardingPage (incl. country select) | No |
| `/auth/login` | LoginPage | No |
| `/auth/register` | RegisterPage | No |
| `/auth/verify-email` | VerifyEmailPage | Yes (unverified) |
| `/auth/forgot-password` | ForgotPasswordPage | No |
| `/marketplace` | MarketplacePage (tab 1) — `All / Loans / Forex` filter, defaults to user's country | Yes |
| `/marketplace/:requestId` | LoanDetailPage + Offers | Yes |
| `/forex/:requestId` | ForexDetailPage + Offers (Send/Rate/Receive panel) | Yes |
| `/watchlist` | WatchlistPage (tab 2) | Yes |
| `/positions` | My Requests + My Offers (loan and forex) | Yes |
| `/account` | AccountPage (tab 4) — includes country setting | Yes |
| `/loans/create` | LoanCreatePage | Yes (Free plan and up) |
| `/loans/my-loans` | MyRequestsPage | Yes |
| `/forex/create` | ForexCreatePage | Yes (Free plan and up) |
| `/forex/my-forex` | MyForexRequestsPage | Yes |
| `/offers` | MyOffersPage (loan and forex) | Yes (Lender/Pro plan) |
| `/notifications` | NotificationsPage | Yes |
| `/kyc` | KycPage | Yes |
| `/profile` | ProfilePage | Yes |
| `/profile/:userId/reviews` | UserReviewsPage | Yes |
| `/admin` | AdminDashboardPage | Yes (`is_admin`) |

---

## Database Schema

The full schema lives in `sql/schema.sql`. Apply against the Supabase Cloud project:

```bash
psql "postgresql://postgres:<password>@<project-ref>.supabase.co:5432/postgres" -f sql/schema.sql
psql "postgresql://postgres:<password>@<project-ref>.supabase.co:5432/postgres" -f sql/seed.sql
```

### Tables

| Table | Purpose |
| --- | --- |
| `countries` | Reference table: `code`, `name`, `currency_code`, `phone_prefix`, `is_active` (lending gate), `forex_enabled` (independent forex gate). Seeded with all 7 launch/expansion markets. |
| `currencies` | **New, v6.0.** Reference table: `code`, `name`, `is_market_currency`, `market_country`, `forex_trading_enabled`. Seeded with the 7 market currencies + USD, all `forex_trading_enabled = FALSE` by default. |
| `profiles` | Core user profile. Extends `auth.users` 1-to-1. Carries `country` and `phone_verified_at`. No stored role — capability comes from `subscription_plan`, shared across Loans and Forex. |
| `system_settings` | Platform config, with an optional `country` column, and (v6.0) `allow_foreign_currency_loans` per country |
| `subscriptions` | `subscription_plan` enum (`free` \| `lender` \| `pro`) — gates offer-making and term-suggestion on both modules; priced per market via `amount_minor_units`, optionally billed in USD |
| `kyc_verifications` | Optional verification and admin review. Approval drives the Pro-tier "Verified" badge. |
| `loan_requests` | Structured funding requests; `country` locked at insert; `currency_code` defaults to local currency, may be `USD` where permitted |
| `loan_offers` | Offers made on loan requests. No `country` column — read via `request_id → loan_requests.country` |
| `forex_requests` | Structured currency-exchange requests: `currency_held`, `currency_needed` (both must be `forex_trading_enabled`), `amount`, optional `preferred_rate`, settlement preference, `country` locked at insert |
| `forex_offers` | Offers made on forex requests: `rate_offered`, `amount_available`, `terms`. No `country` column — read via `request_id → forex_requests.country` |
| `watchlist` | User-saved listings, loan or forex |
| `contact_reveals` | Post-acceptance contact sharing, loan or forex, logged in `audit_logs` |
| `notifications` | In-app notification feed |
| `reviews` | One-time post-contract review, loan or forex. Feeds a user's global trust signals |
| `audit_logs` | Append-only compliance trail |
| `refresh_tokens` | JWT refresh token store with rotation chain |
| `referrals` | Referral programme tracking |
| `transactions` | Stage 6. Flutterwave/Paystack (or equivalent) payment records for subscriptions and contact-unlock fees only — never P2P loan funds or exchanged currency |

### Key Functions and Triggers

| Name | Type | Purpose |
| --- | --- | --- |
| `handle_new_auth_user()` | Trigger fn | Syncs `auth.users` → `public.profiles` |
| `accept_offer(request_id, offer_id, owner_id)` | RPC | Atomic offer acceptance + contact eligibility, for loan or forex offers |
| `get_public_listing_offers(request_id)` | RPC | Anonymized public offer book for active loan listings |
| `get_public_forex_offers(request_id)` | RPC | Anonymized public offer book for active forex listings |
| `submit_review(contract_id, rating, comment)` | RPC | Records a one-time post-contract review, loan or forex; refreshes global trust aggregates |
| `recompute_trust_aggregates(user_id)` | Trigger fn | Recalculates trust signals across all countries and both modules |
| `trg_fn_set_request_country` | Trigger fn | Copies `country` onto a new `loan_requests` row at insert; locked thereafter |
| `trg_fn_set_forex_request_country` | Trigger fn | Copies `country` onto a new `forex_requests` row at insert; locked thereafter |
| `trg_fn_validate_forex_offer` | Trigger fn | Validates `currency_held`/`currency_needed` are both `forex_trading_enabled` at request-creation time |

### Key Views

| View | Purpose |
| --- | --- |
| `v_loan_listings` | Public marketplace loan listings, `country` + `currency_code` |
| `v_forex_listings` | Public marketplace forex listings, `country` + `currency_held`/`currency_needed` + `rate_coverage_tier` |
| `v_user_marketplace_activity` | Dashboard — loan and forex requests posted and offers made, in one query |
| `v_lender_offers` | Loan offer activity, participant-scoped exact terms |
| `v_forex_offers` | Forex offer activity, participant-scoped exact rate/amount/terms |
| `v_marketplace_activity` | Marketplace KPIs, filterable/groupable by `country` and `request_type` |
| `v_marketplace_pro_filters` | Pro-only marketplace filter signals |
| `v_trust_profile_public` | Public trust signals, global across country and module |
| `v_trust_profile_pro` | Pro-only extension — success rate and reliability score |

---

## Supabase Setup

### 1. Cloud Project

1. Create (or use the existing) Supabase project — one project serves every market and both modules
2. Apply the schema and seed:
   ```bash
   psql "postgresql://postgres:<password>@<project-ref>.supabase.co:5432/postgres" -f sql/schema.sql
   psql "postgresql://postgres:<password>@<project-ref>.supabase.co:5432/postgres" -f sql/seed.sql
   ```
3. Confirm `countries` has all 7 markets seeded, with `UG` as the only `is_active = TRUE` row, and confirm `currencies` has all 8 rows (`UGX`/`KES`/`TZS`/`RWF`/`NGN`/`ZAR`/`EGP`/`USD`) with `forex_trading_enabled = FALSE` before onboarding any users
4. Create the `verification-documents` storage bucket (private) if it doesn't already exist

### 2. Auth Bridge Trigger

The `handle_new_auth_user()` function runs automatically on every `auth.users` INSERT, creating the corresponding `public.profiles` row.

### 3. Studio

Use the Supabase Dashboard for table browsing, auth user management, and storage inspection.

---

## Getting Started

### Prerequisites

- Flutter SDK `>=3.0.0`
- Dart SDK `>=3.0.0`
- Supabase CLI
- A configured Supabase Cloud project

### Installation

```bash
git clone https://github.com/your-org/nipanze.git
cd nipanze
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Running the App

#### Cloud

Create a `.env.local` file with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, then run:

```bash
./run_cloud.sh chrome
```

You can also target Android or Linux with the same script:

```bash
./run_cloud.sh android
./run_cloud.sh linux
```

#### Local

Create a `.env.local` file with `LOCAL_SUPABASE_URL` and `LOCAL_ANON_KEY`, then run:

```bash
./run_local.sh
```

For Linux desktop local development:

```bash
./run_linux.sh
```

### Building for Production

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...

flutter build web --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

---

## Environment Configuration

Create `.env.local` from `.env.example` and fill in values.

```env
# Cloud
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=eyJ...

# Local development
LOCAL_SUPABASE_URL=http://localhost:54321
LOCAL_ANON_KEY=your-local-anon-key

# Service role key — only for Edge Functions or server-side testing.
# NEVER bundle this in the Flutter client.
SUPABASE_SERVICE_ROLE_KEY=eyJ...
LOCAL_SERVICE_ROLE_KEY=your-local-service-role-key
```

---

## Key Packages

| Package | Purpose | Stage |
| --- | --- | --- |
| `supabase_flutter ^2.x` | Auth, database, Realtime, storage | 1 |
| `flutter_bloc ^8.x` | BLoC state management | 1 |
| `go_router ^14.x` | Declarative routing with auth guards | 1 |
| `get_it + injectable` | Dependency injection with code-gen | 1 |
| `flutter_secure_storage ^10.x` | Secure token storage | 1 |
| `hive_flutter ^1.1.0` | UI-layer cache only | 1 |
| `animate_do ^4.2.0` | FadeIn/SlideIn animations | 1 |
| `lottie ^3.1.2` | Loading and empty state animations | 2 |
| `shimmer ^3.0.0` | Skeleton loading screens | 2 |
| `percent_indicator ^4.2.3` | Loan funded-% progress indicators | 2 |
| `fl_chart ^1.2.0` | Portfolio and analytics charts | 3 |
| `cached_network_image ^3.3.1` | Network image caching and placeholders | 2 |
| `image_picker ^1.1.2` | Camera and gallery image selection | 2 |
| `intl ^0.20.2` | Formatting and localization utilities | 1 |
| `equatable ^2.0.5` | Value equality for models and states | 1 |
| `dartz ^0.10.1` | Functional programming helpers | 1 |
| `shared_preferences ^2.3.2` | Simple on-device key-value storage | 2 |

---

## Edge Functions

| Function | Purpose |
| --- | --- |
| `flutterwave-checkout` | Mock Flutterwave checkout session initialization and verification |
| `send-notification` | Push / notification request handler for the app |

---

## Testing

```bash
flutter test
flutter test test/features/auth/auth_bloc_test.dart
flutter test integration_test/integration_test.dart -d linux
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

### Test Accounts

**Password for all accounts: `Test1234!`**

| Email | Country | Subscription | Best for testing |
|---|---|---|---|
| `david.mukasa@gmail.com` | UG | Free | Contracted loan request; contact reveal triggered |
| `james.okello@outlook.com` | UG | Pro | Active loan request with two pending offers |
| `admin1@nipanze.ug` | UG | Free (`is_admin = true`) | Full admin dashboard access |
| `wanjiru.kamau@gmail.com` | KE | Free | Confirms KE feed/currency rendering (KES) |
| `amani.mwakalinga@gmail.com` | TZ | Free | Confirms TZS currency rendering |
| `uwase.claudine@gmail.com` | RW | Pro | Confirms RWF Pro term suggestions |
| `chidinma.okafor@example.ng` *(new, v6.0)* | NG | Lender | Confirms NGN currency rendering and cross-border offer placement into UG |
| `thandiwe.dlamini@example.co.za` *(new, v6.0)* | ZA | Pro | Confirms ZAR Pro term suggestions and gating |
| `youssef.hassan@example.eg` *(new, v6.0)* | EG | Free | Confirms EGP currency rendering; flagged for extra forex-review scrutiny given EGP's currency-control history |
| `mutesi.grace@gmail.com` | UG | Lender | Active `UGX → KES` forex request with two pending rate offers |
| `nonparticipant.tester@gmail.com` | UG | Free | Verifies non-participants see only `rate_coverage_tier` on forex listings |

---

## Deployment

| Target | Available now | Command |
| --- | --- | --- |
| Android APK (sideload) | ✅ | `flutter build apk --release` |
| Web | ✅ | `flutter build web --release` |
| Linux desktop | ✅ | `flutter build linux --release` |
| Edge Functions | ✅ (free tier) | `supabase functions deploy` |
| DB Migrations | ✅ | `supabase db push` |
| Android Play Store | Stage 6 | `flutter build appbundle --release` |
| iOS App Store | Stage 6 | `flutter build ios --release` |

---

## Security

- **No fund custody** — Nipanze never holds, pools, converts, or moves user money or currency, in any market
- **RLS on all tables** — Postgres enforces access control, not just the application layer
- **Plan, country, and currency-eligibility checked server-side** — never trusted from the client
- **Payment status is webhook-verified only**
- **JWT auth** — Supabase issues short-lived JWTs; sessions auto-refresh
- **Service role key never in client**
- **Controlled contact sharing** — loan or forex
- **Selective offer-term transparency** — enforced via RLS/RPC
- **Reviews are participant-gated** — enforced server-side
- **Append-only audit log**
- **Private documents** — verification documents never exposed in listings
- **Refresh token rotation**
- **`--dart-define` credentials**

---

## Regulatory Compliance

> Nipanze operates as a technology marketplace. We do not hold funds, accept deposits, issue loans, pool capital, set interest rates, convert or hold currency, or set exchange rates, anywhere. **Nipanze is not a law firm and this document is not legal advice** — every market listed here needs its own local regulatory review before launch, and that review carries meaningfully different weight across this seven-market list than it would across a single regional bloc.

**We DO:** Provide marketplace infrastructure, show requester-provided information, manage controlled contact sharing, facilitate discovery, and surface on-platform trust signals so participants can make informed matching decisions — consistently, per market, for both loan and forex requests.

**We DO NOT:** Accept deposits, hold or pool user funds or currency, issue loans, set interest rates or exchange rates, guarantee returns or exchange outcomes, act as a bank, financial institution, or currency broker, process P2P payments, track repayments or settlement, convert currencies, or claim to measure real-world repayment or settlement behavior, in any country.

Each market carries its own regulatory review, on two independent tracks — lending (`countries.is_active`) and currency-exchange facilitation (`countries.forex_enabled` and `currencies.forex_trading_enabled`) — before either flag is set to `TRUE`. Uganda, Kenya, Tanzania, and Rwanda share a broadly similar regional regulatory and payment-rail context; Nigeria, South Africa, and Egypt each sit in a materially different regulatory and payments environment and should be treated as requiring independent, ground-up review rather than an extension of East African findings. This is a launch-checklist item per market and per module, not a schema concern — and not a substitute for qualified local legal counsel in each market.

---

## Roadmap

See [BUILD_PLAN.md](BUILD_PLAN.md) for the full, authoritative stage-by-stage roadmap.

### Stage 1 — Foundation ✅ Complete
### Stage 2 — Core Marketplace ✅ Complete
### Stage 3 — Polish & Supporting Features ✅ Complete
### Stage 3.5 — Cloud Migration & Auth Hardening ✅ Complete

### Stage 4 — Structured Deal Agreement, Contact Sharing & Trust System ⬜ Planned
- Locked-term bidding, selective transparency, trust & reputation layer, contract auto-generation, contact reveal, `role` column removal

### Stage 4.5 — Multi-Market Expansion ⬜ Planned
- `countries` + `currencies` tables seeded with all 7 markets and 8 currencies; `country` added to `profiles`/`loan_requests`; marketplace feed defaults to the user's country

### Stage 4.7 — Forex Marketplace Expansion ⬜ Planned
- `forex_requests` / `forex_offers` tables; `countries.forex_enabled` and `currencies.forex_trading_enabled` gates; same selective-transparency and trust-signal reuse as Loans; `All / Loans / Forex` marketplace filter and forex-specific listing card (Send/Rate/Receive panel)

### Stage 5 — Admin & Compliance ⬜ Planned
### Stage 6 — Launch & Growth ⬜ Planned
- Per-market rollout in the order: Uganda (live) → Kenya → Tanzania → Rwanda → Nigeria → South Africa → Egypt, each with its own lending *and* separately-timed forex go/no-go

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

---

## License

MIT License — see the [LICENSE](LICENSE) file for details.

Copyright © 2024–2026 Nipanze Platforms Limited. All rights reserved.

---

## Contact

**Nipanze Platforms Limited**
Email: <contact@nipanze.ug>
Website: <https://nipanze.ug>

---

*Made with ❤️ for financial inclusion across Africa*
