# ADDENDUM: "Provider type" step (Individual or Company / Organization)

Extends `FINAL_BUILD_PROMPT_PROVIDER_SERVICES.md` (Stage 4.14). Read that file, `.agents/AGENTS.md`, `BUILD_PLAN.md` first. All rules there still apply: Home is protected, flags default off, re-runnable SQL, staging first, tracker updated in the same commit.

## 1. Goal
Insert one new sheet, **B2 "Who is offering?"**, between sheet B (Choose Category) and sheet C (Category / Select Services). The user picks **Individual** or **Company / Organization** for that category. The choice is saved per user and per category, then the user continues to sheet C. Sheet C, D, E, F, G and the multi-select, bulk-atomic save flow do not change.

New flow: A -> FAB -> B (category) -> **B2 (provider type)** -> C (services) -> D/E/F (jobs) -> save -> A.

## 2. Sheet B2 design (inside the Add Service bottom sheet)
Same sheet chrome as B and C: back arrow, category name as title (e.g. "Machinery & Equipment"), 44px tap targets, existing tokens, light/dark, 360px, RTL.

- Eyebrow label: `STEP 1 OF 2` is NOT used here (jobs steps already use "STEP n OF 3"); use a plain small caption instead: "Offering in this category".
- Heading: **Who is offering?**  Sub-text: "This tells people whether they would deal with you or with your business. You can set it differently for each category."
- Two large selectable cards, single choice (radio behaviour, whole card is the tap target, radio indicator on the right):
  1. **Individual** (person icon): "I offer this myself, as a freelancer or sole provider."
  2. **Company / Organization** (building icon): "A registered business, agency, team or institution."
- Selected card: primary blue border (2px), light blue tint background, filled radio with check. Unselected: neutral border. Selection is shown by border + check icon + the text of the radio, never colour alone.
- Pre-selection: if a value is already saved for this category, that card is preselected. Otherwise nothing is preselected and the button is disabled.
- Footer helper line under the cards (small, neutral): "Selecting this does not verify you. Verification is separate and only asked where a service requires it."
- Sticky primary blue button **Continue**. Disabled state shows the reason beneath it: "Choose one option to continue".
- Behaviour on Continue: call `set_provider_category_type`; on success go to C. On failure show an inline error with Retry and stay on B2 (the selection is kept). Offline: show the existing offline SnackBar pattern, button stays enabled for retry, no queued write.
- Back from B2 returns to B with no change saved. Back from C returns to B2 with the saved value shown.
- Always shown after a category is chosen (it also holds the old S3 presentation fields). A saved identity is preselected and tagged "Current". Keeping it continues to C or D; picking the other one opens the switch flow (S2 confirm, S4 review); Change opens the identity switch flow (section 12). Back from C or D then returns to B (category list).

Optional, small and additive (confirm before building): in sheet G (card details) show a read-only "Offered as: Individual / Company" row with a Change action that reopens B2 for that category.

## 3. Scope rules specific to this step
1. **Per category.** A user can be Individual in Technology and Company in Transport. Saving one category never touches another.
2. **Services only.** The type describes who offers *services / equipment hire*. Work roles ("I want jobs in this category") are always a person's own profile and are not affected by the type, and never inferred from it (non-negotiable 9). If the user picked Company and turns the jobs switch on, show a one-line note above the roles: "Job profiles are personal and are saved under your own name."
3. **No verification effect yet.** Company vs Individual does not change evidence requirements, gating, status or matching. It is stored so `verification_requirements` can later ask for business registration for companies. Do not auto-grant or auto-require anything now.
4. **Not part of the "N selected" badge**, the capability soft cap, or screen A cards. A saved type with zero capabilities creates no card.
5. **Privacy.** Stored private to the owner. It is not added to any public view, Home, feed, listing card, or `v_provider_badges` in this change.
6. **Flags.** The step appears only when `capability_profiles_enabled` is on. Flag off = B goes straight to C exactly as today.

## 4. Data (Supabase, `sql/patch_provider_category_type.sql`, re-runnable, non-destructive)
```sql
create table if not exists public.provider_category_profiles (
  user_id       uuid not null references public.profiles(id) on delete cascade,
  category_slug text not null references public.need_categories(slug),
  provider_type text not null check (provider_type in ('individual','company')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (user_id, category_slug)
);

alter table public.provider_category_profiles enable row level security;
-- no anon grants
revoke all on public.provider_category_profiles from anon;

drop policy if exists pcp_owner_select on public.provider_category_profiles;
create policy pcp_owner_select on public.provider_category_profiles
  for select to authenticated using (user_id = auth.uid());
drop policy if exists pcp_admin_select on public.provider_category_profiles;
create policy pcp_admin_select on public.provider_category_profiles
  for select to authenticated using (private.is_admin());
-- writes only through the RPC (no insert/update policy for users)
```
RPC, following the repo pattern (`private.*_internal` + `SECURITY INVOKER` wrapper):
- `private.set_provider_category_type_internal(p_category_slug text, p_provider_type text)`: require `auth.uid()`; reject unknown or retired category (`financial_services`) and values other than `individual`/`company`; require `capability_profiles_enabled`; upsert on `(user_id, category_slug)`, set `updated_at`; write an audit-log row only when the value changes; use a `P02xx` error code taken from the unused range after checking `sql/`.
- `public.set_provider_category_type(...)` wrapper, granted to `authenticated` only.
- `public.get_my_provider_category_types()` returns `(category_slug, provider_type)` for the caller. Used by B2 to prefill and by G.
- Rate limit: reuse the per-user capability rate limiter.
- Rollback note: `drop function ...; drop table public.provider_category_profiles;` loses only this preference.
- Ship this as its own standalone, descriptively named SQL patch. Do NOT modify the monolithic `sql/patch.sql` (or `sql/merged.sql`) for schema, function or policy changes.
- Cascade: if a user is deleted the rows go. Removing the last capability in a category keeps the saved type (it is a preference).

## 5. Flutter
- New: `features/provider/presentation/widgets/provider_type_sheet.dart` (B2), a small `ProviderTypeCard` widget, `ProviderCategoryType` enum (`individual`, `company`), repository methods `getMyCategoryTypes()` / `setCategoryType()`, cubit state `categoryTypes: Map<String, ProviderCategoryType>` loaded once with the Provider Services data and cached with the existing offline cache (read only).
- Change: only the navigation in the Add Service sheet, B -> B2 -> C. Sheet C receives the category as before; it does not need the type to render.
- Do not touch Home, feed widgets, `ListingCard`, `NeedCard`, bottom nav, or the + sheet layout.
- Constants: add `Rpcs.setProviderCategoryType`, `Rpcs.getMyProviderCategoryTypes`, `Tables.providerCategoryProfiles`.
- l10n (en, sw, fr, rw, ar, RTL): `providerTypeTitle`, `providerTypeSubtitle`, `providerTypeIndividual`, `providerTypeIndividualDesc`, `providerTypeCompany`, `providerTypeCompanyDesc`, `providerTypeNotVerification`, `providerTypeChooseOne`, `providerTypeJobsPersonalNote`. English complete; others fall back and missing keys are listed.
- Accessibility: radio group semantics with a group label, each card exposes label + description + selected state, 44px minimum, contrast 4.5:1, 200% text scale (cards grow, no clipping), screen reader announces "selected".
- Analytics (no personal data): `provider_type_selected` with `category_slug` and `provider_type`.

## 6. Tests (add to the tracker's test matrix)
| Area | Case |
|---|---|
| Per category | Individual in Technology, Company in Transport: reopen app, both persisted, each prefilled on its own B2 |
| Independence | Changing the type for one category leaves all others and all capabilities untouched |
| Flow | B -> B2 -> C; Continue disabled until a card is chosen; Back from C returns to B2 with value; Back from B2 saves nothing |
| Unchanged | Sheet C service selection, bulk atomic save, soft cap, jobs steps D to F, screen A cards behave exactly as before |
| Jobs | Company + jobs switch on: roles saved as a personal profile, note shown, type not copied into work capabilities |
| Flag | `capability_profiles_enabled` off: no B2, B goes to C, no writes |
| RLS | Owner reads/writes own rows via RPC; other users and anon cannot read or write; direct insert/update by a user fails |
| Validation | Unknown category, retired `financial_services`, or invalid type value rejected server-side |
| Idempotent | Setting the same value twice changes nothing and writes no audit row; patch rerun changes nothing |
| Offline | Failed save keeps selection, shows retry, no queued write |
| Localization | 5 locales, RTL, dark mode, 360px, 200% text scale, no overflow |
| Home protection | Snapshots (4 tabs, light/dark, 360px), view and RPC output columns, feed results identical to baseline; no Home file in the diff |
| Regression | Loans, Forex, Needs, offers, accept, contact reveal, trust, watchlist, discovery plans unchanged |

## 7. Tracker updates (same commit as the work)
Add to Stage 4.14 in `BUILD_PLAN.md`: a decisions-log entry for each open question below; phase rows "P2 SQL provider_category_profiles + RPCs" and "P3 sheet B2 + navigation"; the tests above; verification log (analyze, tests, SQL checks, Home baseline diff). Do not mark Done without passing tests.

## 8. Open questions (recommend, then wait)
1. RESOLVED: B2 is always shown; the saved identity is preselected; a changed identity goes B2 -> S2 -> S4 (see `PROVIDER_FLOW_BUILD_ORDER.md`).
2. Should Company later require business registration evidence for regulated categories? (Recommended: yes, via `verification_requirements`, in a separate change.)
3. Show a public "Company" tag on provider badges and offers? (Recommended later; needs a privacy decision and an additive change to `v_provider_badges` only.)
4. Should a Company be able to list staff or multiple operators? (Out of scope here.)
5. Confirm the work-role note wording for Company users.
6. After Company -> Individual, keep hidden services (recommended) or delete them with a confirm dialog? See section 9.

## 9. REVISION (supersedes section 3 rule 2 and the "I want jobs in this category" switch everywhere)
The provider type now drives sheets C and D. The "Available for jobs" switch is removed from the UI and from Stage 4.14 sheets C and D. The per-category `work_profiles_enabled_<slug>` flags still decide whether roles are shown at all.

| Provider type for the category | Category sheet shows | Can save |
|---|---|---|
| Individual | Only "What roles do you do?" (STEP 1 OF 3, purple, multi-select roles), then the existing kind and qualifications steps | Work roles only (`capability_type='work'`) |
| Company / Organization | "What we offer" (blue, grouped service checkboxes), then "What roles do you do?" (purple, optional, same 3-step flow) | Services (`'service'`) and work roles (`'work'`) |

Rules:
1. Footer button adapts: roles ticked -> purple "Next: choose your kind" (services ticked at the same time are saved in the same atomic save when the flow finishes); only services ticked -> blue "Save services (N)"; nothing ticked -> disabled. Summary line above it: "2 services · 1 role selected".
2. Server-enforced: `save_provider_capabilities` reads the caller's `provider_category_profiles.provider_type` for the category and rejects `service` items for `individual` (new `P02xx` code). Work roles are accepted for both types. Still bulk, atomic, and never touches other categories.
3. Changing the type later: superseded by section 12. A category's identity is changed only through the switch flow (Provider Services -> Choose Category -> B2 -> S2 -> S4). The previous identity's services are set Inactive (kept, restorable), not hidden.
4. The "Job profiles are personal" note stays for Company, in the roles section subtitle.
5. Individuals can no longer list services or equipment hire. A sole trader who hires out machines must choose Company / Organization, so review the B2 wording ("Individual" = "I work myself, for others") against the business rules.
6. Tests to add: Individual sees no "What we offer" and cannot save services through the RPC; Company sees both and saves both in one transaction; type change keeps data and hides services; Company with roles only and with services only both save; footer states; other categories unchanged; roles flag/regional rules unchanged.

## 10. REVISION 2: two separate paths, and a Company details step
The design canvas now shows the two paths as separate rows. Build them as two flows that share only B and B2.

**Individual path (roles only):** A -> FAB -> B (category) -> B2 (choose Individual) -> C (What roles do you do?, STEP 1 OF 3) -> E (kind, STEP 2 OF 3) -> F (qualifications and proof, STEP 3 OF 3, purple) -> save -> A (summary shows Job cards only; filter chips are All and Jobs; no Services chip or section).

**Company path (services + roles + company details):** A -> FAB -> B (category) -> B2 (choose Company / Organization) -> D (What we offer, then What roles do you do?, blue STEP 1 OF 2) -> company details (blue STEP 2 OF 2) -> save -> A (summary shows Service cards labelled "<Category> · Company", plus Job cards labelled "Personal profile").

Rules:
1. Company roles do NOT go through E and F. Ticked roles are saved as `capability_type='work'` rows with empty metadata. Their status follows the capability's verification policy (section 11); a "Self-declared" label is never shown. The user adds machines (kinds) and qualifications later from the Job card (it opens the same E and F screens). The Job card note says "Add machines and qualifications to get matched".
2. D's footer is "Next: company details" (blue) whenever at least one service or role is ticked; disabled otherwise. D saves nothing by itself. Ticks are kept as a per-step draft so Back from the company details step returns to D unchanged.
3. The company details step has these fields, all optional: company or business name, registration number, team size (1–5, 6–20, 21–50, 50+), years in business (Under 1, 1–2, 3–5, 6–10, 10+), where you work (district or city only), and a "Proof for the verified badge" checklist (for Machinery: Fleet photos, Ownership or logbook, Business registration) with Add proof actions. Helper text: uploads alone do not verify; JPG, PNG or PDF up to 5 MB; you can save now and add proof later.
4. The footer button "Save company profile" performs ONE atomic save of services, roles and company details (see `COMPANY_PATH_BUILD_PROMPT.md`).
5. Naming: on the canvas the company details screen is labelled "G". In this repo "sheet G" already means card details (Stage 4.14), so name the new screen `CompanyDetailsStep` / "CD" in code, tests and the tracker.
6. The individual summary screen and the company summary screen are the same Provider Services page (screen A); only the data differs. Do not fork the page.

Files: see the canvas "Provider Type Screen" (artboards: B2 chooser, C, E, F, individual A; B2 Company, D, company details, company A).

## 11. REVISION 3: verification policy (supersedes anything above that says "Self-declared" or per-service evidence fan-out)
Source of truth: `VERIFICATION_SPEC.md` (the simple provider and capability verification spec). It wins over earlier sections on any conflict. Effects on this flow:
1. **Three policies, configured per capability** (never per whole category): `open` (active immediately, no proof, no label), `optional_proof` (active immediately, proof can be added later, badge only after admin approval), `required_proof` (inactive until proof is approved).
2. **No "Self-declared" label anywhere.** Remove it from screen A cards, card details and the roles flow. A verified badge appears only after an admin approves that capability's evidence.
3. **Card states** are Active, Inactive, Pending Review, Rejected. Open: Active, "No proof required". Optional proof: Active, "Proof can be added later", upload action. Required proof: Inactive, "Proof required before it goes live", "Upload documents"; Pending Review stays inactive; Rejected shows the reason and allows resubmission. Inactive capabilities cannot receive offers or be advertised, enforced in the backend (offer/matching functions and views), not only in the UI.
4. **Individuals:** evidence is per capability. This includes work roles when a role's policy requires proof; the qualification uploads in screen F feed the same evidence rows.
5. **Companies:** company verification is separate from capability verification. A company can submit a business registration certificate and/or licences or authorization documents, with statuses Not Submitted, Pending Review, Verified, Rejected (with reason). A company certificate never activates or verifies a regulated service. Services under `required_proof` still need their own approved evidence. This replaces the "evidence fan-out per ticked service" idea in `COMPANY_PATH_BUILD_PROMPT.md`.
6. **Screen D:** show a small "Needs proof" tag only on `required_proof` services, so the user knows they start inactive. No tag on open or optional services. The company details step shows the Company verification block (status pill, two optional uploads, the note that a registration certificate does not authorize regulated services).
7. **Storage and admin:** private storage, admin-only access, signed URLs. Basic admin queue for company submissions and individual capability submissions: open documents, approve or reject with a reason, record reviewer and time. No paid APIs or automated document checks.
8. **SQL:** inspect the existing `provider_capabilities` fields (`verification_level`, `evidence_url`, `verified_by`, `verified_at`) first and extend rather than duplicate. Standalone patch only; do not modify the monolithic `patch.sql`.
9. **Launch scope:** non-custodial; Loans and Forex unchanged; keep it simple and cheap.
10. **Tests to add (verification):** each of the three policies; approval, rejection and resubmission; a provider cannot self-verify or self-activate a required-proof capability; unauthorized users and anon cannot read documents; a required-proof capability receives no offers before approval; a company certificate does not activate a regulated service.

## 12. REVISION 4: identity switching (source: `IDENTITY_SWITCH_SPEC.md`, build prompt: `IDENTITY_SWITCH_BUILD_PROMPT.md`)
- B2 is always shown and merges the old S3 (identity plus how you are shown). If the identity changes, the flow is B2 -> S2 confirm -> S4 review, and every "Change" pill opens B2: Provider Services -> Choose Category -> B2 -> confirm dialog -> presentation -> review -> save.
- One active identity per user per category, enforced on the server and safe under concurrent requests. Switching is one atomic transaction, deletes nothing, creates no duplicates, and deactivates only the previous identity's capabilities in that category (kept, restorable).
- Verification never transfers between identities. Reviews, completed deals and history stay; accepted deals keep the identity and terms they were created with. Inactive capabilities cannot make offers.
- The presentation step defaults from existing data: Individual uses the personal display name; Company offers "Company name" or "Company with representative" and asks for the company name only if missing, with a live preview. Choosing Company never implies a verified business.
- This supersedes section 9 rule 3 and the "hidden services" open question.
