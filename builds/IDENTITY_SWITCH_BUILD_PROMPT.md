# BUILD PROMPT: Category-specific provider identity switching (Individual <-> Company)

You are a senior Flutter + Supabase engineer in the existing Nipanze repo. Source spec: `IDENTITY_SWITCH_SPEC.md`. Design: the canvas "Provider Type Screen", row "Switching identity in one category" (screens S1 to S4). This builds on `PROVIDER_TYPE_STEP_PROMPT.md` (B2 and per-category type), `COMPANY_PATH_BUILD_PROMPT.md` (company path) and `VERIFICATION_SPEC.md` (per-capability verification). It extends them; it does not replace or duplicate them.

## 0. Do these first, in order (no code before step 4)
1. Read `.agents/AGENTS.md` completely and follow it. If anything here conflicts with it, stop and say which rule and what you propose.
2. Read `BUILD_PLAN.md`, `README.md`, the three prompts above, `IDENTITY_SWITCH_SPEC.md`, and the SQL in `sql/`.
3. Add "Stage 4.16: Provider identity switching" to `BUILD_PLAN.md` with a task-level tracker (Phase | Task | Files/SQL | Tests | Status | Date | Notes), decisions log, test tracker and verification log. Update it in the same commit as the work.
4. Inspect and report, then wait for my OK: Account and Your Services screens, `provider_category_profiles`, `provider_company_profiles` (if built), `provider_capabilities`, evidence tables, offers/deals tables and RPCs, public provider views, RLS, triggers, audit-log pattern, admin verification queue. List reusable pieces, conflicts, a file-by-file plan, risks and open questions. Do not assume the schema.

## 1. Non-negotiables
- Home and the Marketplace feed must not change (no edits to Home, feed widgets, `ListingCard`, `NeedCard`, discovery card, bottom nav, + sheet layout; existing views/RPCs keep columns, names, order, grants; additive only). Capture Home baselines first and diff after every phase.
- Behind `capability_profiles_enabled` (default false). Flag off = today's behaviour.
- SQL: standalone, descriptively named patch files only. NEVER modify the monolithic `sql/patch.sql` or `sql/merged.sql`. Re-runnable, non-destructive, RLS on every table, no `anon` grants, `private.*_internal` + `SECURITY INVOKER` wrapper, `P02xx` codes (check unused range), audit-log writes. Nothing runs against production without my explicit approval; if you lack access, output the SQL and exact steps. Never print secrets.
- Non-custodial; Loans and Forex unchanged; no new dependencies without a one-line justification; no unrelated refactors.
- Do not claim a switch succeeded until the database call has returned success.

## 2. Business rules (from the spec, made precise)
1. A user can be Individual in one category and Company in another.
2. Per user and category there is exactly ONE active identity. The active identity is the saved type in `provider_category_profiles` (primary key `(user_id, category_slug)` already guarantees one row). Direct API calls and concurrent requests cannot create two.
3. Switching deletes nothing. Services, roles, descriptions, locations, images, contact preferences, saved form data and evidence stay in their rows.
4. No duplicates: switching never creates a second copy of a capability, service, profile or account. Each capability row belongs to one identity (`identity_type`) and is deactivated or reactivated in place.
5. Verification never transfers. Individual proof does not verify the Company identity, and company verification or credentials never verify the Individual one. Each identity starts from its own verification state; required-proof capabilities need their own approved evidence under that identity.
6. Reviews, completed deals and reputation stay intact (see section 4).
7. The restriction applies to PROVIDING services only, not to browsing, requesting services, Loans or Forex.
8. This REPLACES the earlier rule "Company -> Individual keeps services hidden": previous-identity capabilities are set Inactive (kept, restorable), not hidden. Switching back restores them to the state their own policy and evidence allow (a required-proof capability stays inactive unless its evidence is still approved).

## 3. Flow and screens (match the canvas S1 to S4)
Path: `Provider Services -> Choose Category (S1, existing, unchanged) -> B2 (identity + how you are shown; saved identity preselected and tagged Current) -> if the identity changed: S2 confirm -> S4 review -> Save`. B2 is always shown and now includes the old S3 presentation fields. Keeping the saved identity continues to C or D. Every "Change" entry point opens B2.

- **S1 Provider Services + Choose Category.** This is the existing live screen and sheet, unchanged: do not redesign it. The category row already shows its badge; tapping a category opens B2.
- **S2 Confirm (dialog).** Shown only when B2's chosen identity differs from the saved one. Modal dialog (focus trapped, Cancel dismisses): "Switch to Individual?" ("This only changes <Category>. Your other categories stay as they are."), five points: service information is kept, nothing deleted; <previous identity> services here become inactive (kept, can be restored); new offers use the <new> identity; verification requirements may change and company verification does not carry over; accepted deals, reviews and history stay, personal roles stay active. Buttons: Continue (blue), Cancel. Explicit tap on Continue is required; no auto-advance.
- **S3 is merged into B2** (presentation). Defaults come from existing data.
  - To Individual: personal display name (from profile), relevant service info, compatible profile details; editable.
  - To Company: two radio cards, "Company name" (business name as the provider) and "Company with representative" (business name plus the user's name; only when authorized to represent the business). Company name field is required and prefilled from `provider_company_profiles` if present; error text "Required. We do not have a company name for you yet." when empty. Representative field prefilled from the profile. Live preview card of the public profile. Note: choosing Company does not make you a verified business. Other mandatory business information is requested only if missing.
  - "Continue to review" disabled until required fields are valid.
- **S4 Review (STEP 2 OF 2).** Rows: category; new identity (and the previous one); public name (with representative if chosen); "Reused from your current setup" (descriptions, locations, images, contact preferences, with counts); "Needs attention" (capabilities that will stay inactive because required proof is missing or pending, company verification status, any missing required info); explanation that the previous identity's services here become inactive, are kept, and can be restored. Buttons: Confirm switch (blue, loading state, double-tap guarded) and Back.
- **Result.** Success: "You are now offering <Category> as <identity>." Pending: "Your <identity> is set up. <N> service(s) will go live once proof is approved." Failure: nothing changed, show the reason and Retry. All strings in en, sw, fr, rw, ar (RTL); respect language and currency.
- States: loading, validation, error, success, pending-verification, offline (switch requires a connection; cached read only, no queued writes).

## 4. Offers, deals and public presentation
- New offers use the category's active identity and must come from an ACTIVE capability of that identity. Enforce in the offer RPC/trigger on the server (an inactive or other-identity capability cannot make an offer, even by direct API call).
- Existing offers and accepted deals keep the identity, display name and terms they were created with: add additive nullable snapshot columns on offers/deals (`provider_identity_type`, `provider_display_name`) filled at creation; leave historical rows' values as they were (backfill only if you can prove the identity at that time, otherwise leave null and render the stored provider as before). Do not cancel accepted deals, delete pending offers or rewrite history.
- Pending offers at switch time: show the count on S4 ("You have 2 pending offers. They stay as sent; you can withdraw them yourself.") and keep them untouched. Obtain confirmation (the Confirm switch tap) after showing this. Do not auto-withdraw.
- Public listings show the active identity and its approved presentation: for Company, business name (plus "Represented by <name>" only if chosen). Never expose internal IDs, evidence, registration numbers or private documents. Reviews and trust history stay attached to the user but are labelled by the identity under which they were earned; a new Company identity must not appear to have personally earned verification or credentials it has not been approved for. Do this through an ADDITIVE public view or additive columns; existing views keep their columns.

## 5. Data (reuse first; confirm in the inspection step)
- `provider_category_profiles` (user_id, category_slug, provider_type): the single active identity per category. Add `identity_changed_at`, `updated_at` if missing.
- `provider_capabilities`: add `identity_type` ('individual'|'company') if absent, backfilled from the category's saved type, plus a guard trigger: a capability may be `active` only if its `identity_type` equals the category's active identity, its policy allows it (open / optional_proof, or required_proof with approved evidence) and its owner matches.
- New `provider_identity_presentations(user_id, category_slug, identity_type, display_mode ('personal'|'company'|'company_with_representative'), display_name, representative_name, status ('draft'|'active'|'inactive'), created_at, updated_at)` with primary key `(user_id, category_slug, identity_type)`: one row per identity so each identity's presentation survives a switch. Reuse `provider_company_profiles.company_name` as the source of the business name (do not duplicate it; fall back to it when presentation is empty). RLS: owner select and admin select; writes only via RPC; no anon.
- Evidence and company verification stay in their own tables and are never copied across identities.
- Audit: one audit row per switch (user, category, from, to, counts of capabilities deactivated and reactivated, timestamp, actor).
- RPC `switch_provider_identity(p_category_slug text, p_to_identity text, p_presentation jsonb)` via `private.switch_provider_identity_internal` + wrapper. In ONE transaction: authenticate; lock the user's `provider_category_profiles` row for the category (`select ... for update`) so concurrent switches serialize; validate the target (must differ from current; flag on; category active; presentation fields valid, company name required for Company); upsert the target presentation (defaults filled from existing data) and keep the previous one; deactivate the old identity's capabilities in THIS category only (set inactive, keep rows); reactivate or leave inactive the target identity's existing capabilities according to their policy and evidence (never grant verified or active against policy); update the saved type; write the audit row; return the result (new identity, pending items, counts). Any failure rolls everything back. Never both active, never both unintentionally inactive.
- A read RPC `get_my_provider_identities()` returns, per category, active identity, display name, counts and pending-verification flags for S1 to S4.
- Existing capabilities for a category that had services as a Company and roles as an individual: roles are personal (see company prompt) and are NOT deactivated by a switch; only the identity-bound service capabilities flip. Confirm this rule in the inspection step.

## 6. Security
Owner-only changes; admin-only approvals; users cannot self-assign company verification, verified badges or active status; server validates identity and fields; inactive identity cannot offer; private evidence stays private; no internal identifiers or documents in public views; all changes audited; rate limit switches per user and category (for example 5 per day) to prevent flapping.

## 7. Phases (small PRs; after each: `flutter analyze`, `flutter test`, SQL checks, Home baseline diff, "how to try it", tracker update)
- P0 Plan, tracker, baselines, inspection report.
- P1 SQL: identity column and guard trigger on capabilities, presentations table, read RPC, RLS, audit, rollback note.
- P2 SQL: `switch_provider_identity` (atomic, locked), offer-time enforcement, additive offer/deal snapshot columns, additive public identity view.
- P3 Flutter: S2 confirm dialog from B2; wire "Change" pills to B2; S1 stays untouched.
- P4 Flutter: B2 presentation fields (defaults, validation, preview) and S4 review; result states.
- P5 Admin: show identity and presentation read-only in the review queue; verification stays per identity.
- P6 Localization, accessibility, dark mode, 360px, 200% text, RTL, offline, README and BUILD_PLAN.

## 8. Tests (add to the tracker)
All 16 from the spec, plus:
1. Individual -> Company and Company -> Individual in one category; presentation defaults come from existing data.
2. Preservation: descriptions, locations, images, contact preferences and saved forms identical before and after; no duplicate capabilities; switching back restores the previous identity's items.
3. One active identity per user and category: direct inserts or updates that would create a second active identity are rejected; two concurrent switch calls leave exactly one active identity and a consistent state; a forced failure mid-switch rolls back everything.
4. Cross-category: Individual in Technology and Company in Transport; switching Transport leaves Technology untouched.
5. Offers: an inactive capability or an other-identity capability cannot create an offer (direct RPC call too); pending offers and accepted deals keep their identity snapshot; deals and reviews intact; historical rows unchanged.
6. Verification: Company verification is not granted by switching; Individual proof does not activate a Company required-proof service and vice versa; required-proof capability stays inactive without its own approved evidence.
7. Roles: personal work roles are not deactivated by an identity switch (if confirmed in inspection).
8. Public view shows the correct active identity and presentation and no private fields.
9. Validation: missing company name blocks B2 Continue; invalid or same-identity target rejected server-side; rate limit enforced.
10. Dialog: Cancel changes nothing; Continue is required; double-tap on Confirm switch sends one request.
11. Flag off: no switching UI, no writes, B2 behaviour as before.
12. RLS: owner, other user, admin, anon on every new table and RPC.
13. Localization in 5 locales, RTL, dark, 360px, 200% scale, no overflow.
14. Home protection: snapshots, view and RPC columns and feed results identical to baseline; no Home file in the diff. Loans, Forex, Needs, offers, accept, contact reveal, trust, watchlist and discovery plans unchanged.

## 9. Definition of done
A user can switch one category between Individual and Company, keep their service information, choose how they are presented, review, and save without redoing setup. Only that category's previous-identity services become inactive; other categories, accepted deals, reviews and history are untouched; verification never transfers; the server enforces one active identity even under concurrency. Tests pass, analyze is clean, five locales, RTL, dark mode and 360px verified, README and BUILD_PLAN (Stage 4.16) complete. Report: files created or modified, migration added, rules implemented, tests run with results, limitations and manual steps.

## 10. Open decisions (recommend, then wait)
- D-I1 Switch rate limit: recommend 5 per day per category.
- D-I2 Should a switch that leaves zero active capabilities in the category warn the user on S4? (Recommended: yes, a note, not a block.)
- D-I3 For Company with representative: require a simple "I am authorized to represent this business" checkbox? (Recommended: yes, recorded in the audit row.)
- D-I4 Public label for reviews earned under the other identity: show "Earned as Individual"? (Recommended: yes, small text.)
- D-I5 Backfill of offer/deal identity snapshots for old rows: leave null (recommended) vs derive.
