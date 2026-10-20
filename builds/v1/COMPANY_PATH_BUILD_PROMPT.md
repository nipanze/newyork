# BUILD PROMPT: Company / Organization path (B2 -> D -> Company details -> A)

You are a senior Flutter + Supabase engineer in the existing Nipanze repo. This builds ONE path of Provider Services: what happens when a user chooses **Company / Organization** on screen B2. Individuals have their own path (B2 -> C -> E -> F -> A); do not change it here.

## 0. Do these first, in order (no code before step 4)
1. Read `.agents/AGENTS.md` completely and follow it. If anything here conflicts with it, stop and tell me which rule conflicts and which you propose to follow.
2. Read `BUILD_PLAN.md`, `README.md`, `PROVIDER_TYPE_STEP_PROMPT.md` (sections 1 to 10), `FINAL_BUILD_PROMPT_PROVIDER_SERVICES.md` (Stage 4.14), and the SQL in `sql/`. This EXTENDS Stage 4.14; do not build a parallel system.
3. Add a stage to `BUILD_PLAN.md` ("Stage 4.15: Company provider path") with a task-level tracker (Phase | Task | Files/SQL | Tests | Status | Date | Notes), a decisions log, a test tracker and a verification log. Keep it updated in the same commit as the work.
4. Explore the repo and Supabase project, report, and wait for my OK: how the Add Service sheet, B2, the category sheet, `provider_capabilities`, `provider_category_profiles`, `save_provider_capabilities`, `provider_capability_evidence`, `verification_requirements` and screen A work today; the live catalog for the categories involved; what is missing; file-by-file plan; risks; open questions.

## 0b. Verification policy (takes precedence over anything below that conflicts)
Read `VERIFICATION_SPEC.md` and section 11 of `PROVIDER_TYPE_STEP_PROMPT.md`. In short:
- Per capability policy: `open` (active, no proof, no label), `optional_proof` (active, proof can be added later, badge only after approval), `required_proof` (inactive until approved, no offers or advertising while inactive, enforced in the backend).
- Never show a "Self-declared" label. States shown are Active, Inactive, Pending Review, Rejected, plus the verified badge after approval and the rejection reason when rejected.
- Company verification is its own thing: optional business registration certificate and/or licences or authorization documents, statuses Not Submitted, Pending Review, Verified, Rejected. It never activates or verifies a regulated service. Each `required_proof` service needs its own approved evidence.
- Private storage, admin-only access, a basic admin review queue (company submissions and individual capability submissions, reason on rejection, reviewer and timestamp recorded). No paid APIs.
- Reuse `provider_capabilities` and its existing verification fields after inspecting them; extend, do not duplicate.

## 1. Rules that always apply
- Home and the Marketplace feed must not change: do not edit Home, feed widgets, `ListingCard`, `NeedCard`, `ListingExpiryIndicator`, the discovery card, bottom navigation, the + sheet layout, or their theme values. `v_loan_listings`, `v_forex_listings`, `v_needs_listings`, `get_for_you_needs`, `get_provider_opportunities` keep columns, names, ordering and grants (additive only). Capture baselines first (Home golden snapshots on 4 tabs, light/dark, 360px; view/RPC column dumps; a feed query on seed data) and diff after every phase. If a task seems to need a Home file, stop and ask.
- Everything is behind `capability_profiles_enabled` (default false); roles are also behind `work_profiles_enabled` and the per-category/country flags. Flag off = app behaves exactly as today.
- Supabase Cloud: re-runnable, non-destructive SQL patch files in `sql/` (standalone, descriptively named files only; do NOT modify the monolithic `sql/patch.sql` or `sql/merged.sql`), RLS on every new table, no `anon` grants, private storage with signed URLs, `private.*_internal` + `SECURITY INVOKER` wrapper, `P02xx` error codes, audit-log writes. Never run anything against production without my explicit approval; if you have no access, output the SQL and exact steps. Never print secrets.
- Slugs are stable. Per-capability verification stays independent: uploading or verifying one capability never changes another. Identity KYC stays account-level. "Provider verified" is granted only by an admin approving that capability's evidence, never by uploads, phone or KYC.
- Onboarding stays lightweight: ticking is all that is needed; everything else is optional and nothing blocks saving.
- No new dependency without a one-line justification; no unrelated refactors.

## 2. The flow to build
```
Add Service (FAB) -> B Choose Category -> B2 Who is offering? (Company / Organization)
 -> D  What we offer + What roles do you do?   (blue STEP 1 OF 2)
 -> CD Tell us about your company              (blue STEP 2 OF 2)
 -> save -> sheet closes, short confirmation -> A Provider Services (refreshed)
```
Reuse existing tokens. Blue = services/company, purple = roles. Status uses icon + text, never colour alone. Tap targets at least 44px. Match the canvas "Provider Type Screen" (company row).

### B2 (already specified in `PROVIDER_TYPE_STEP_PROMPT.md`)
Selecting Company and tapping Continue saves the type for this category through `set_provider_category_type`, then opens D.

### D: services + roles
- Header: back + category name. Pill: "Offering as Company / Organization" with Change (reopens B2).
- Blue progress bar (2 segments), "STEP 1 OF 2".
- **What we offer**: "Tick everything your company provides." Service groups from the catalog (a small "Needs proof" tag only on `required_proof` services) as bordered cards with an "N of M" count and 52px checkbox rows (selected row tinted blue, bold label).
- Divider, then **What roles do you do?**: "Optional. Tick the roles you work in. Job profiles are personal and are saved under your own name. You can add machines and qualifications later." Multi-select role cards (purple when selected). Shown only if `work_profiles_enabled` AND the category is enabled for the user's country; otherwise the roles section is hidden entirely (no greyed control).
- Footer: summary "2 services · 1 role selected" and blue **Next: company details**, disabled until at least one service or role is ticked. D saves nothing; ticks live in a per-step draft so Back from CD returns to D unchanged. Leaving mid-flow asks save/discard.
- Roles chosen here do NOT go through the kind and qualifications steps. They are saved as work capabilities with an empty profile; their status follows each role's verification policy (section 0b). No "Self-declared" label is shown.

### CD: company details (new screen)
Header: back + category name. Blue progress bar full, "STEP 2 OF 2". Heading "Tell us about your company"; sub "Everything here is optional. People see this before they contact you."
Fields (real labelled inputs, never placeholders as labels):
1. Company or business name (text, max 80).
2. Registration number (text, max 40, private: never shown publicly, visible to admins only).
3. Team size chips: 1–5, 6–20, 21–50, 50+ (single choice).
4. Years in business chips: Under 1, 1–2, 3–5, 6–10, 10+ (single choice).
5. Where do you work? (text, districts or cities, comma separated; helper: "District or city only. Your exact address is never shown.").
6. **Company verification** (optional, separate from services): a status pill (Not submitted, Pending review, Verified, Rejected with reason) and two upload rows: "Business registration certificate" and "Licences or authorization documents". Intro: "Optional. Upload one or both documents for manual review by Nipanze. A registration certificate does not authorize regulated services. Those are verified separately, per service." Services with a `required_proof` policy are NOT verified here: the info note says e.g. "Crane Hire needs its own approved proof before it goes live. Add it from Provider Services after saving."
Info note: "You can save now and add proof later. JPG, PNG or PDF, up to 5 MB each."
Footer: summary line and blue **Save company profile**. A failed save keeps the form and shows an inline error with Retry (no queued writes offline; clear offline message).

### A: Provider Services after saving (same page for all users)
- Filter chips: All N, Services N, Jobs N (Services chip and section appear only when the user holds services).
- One card per capability, most recently edited first:
  - Service card (blue "Service" tag): title, "<Category> · Company", status pill (Active, Inactive, Pending Review, Rejected) and a note only where useful ("No proof required", "Proof can be added later", "Proof required before it goes live" with an "Upload documents" button, or the rejection reason with "Resubmit"). The verified badge appears only after admin approval. A "Company verification" strip with its status sits at the top of the list for companies.
  - Job card (purple "Job" tag): title, "<Category> · Personal profile", status pill, note "Add machines and qualifications to get matched" until a kind and qualifications exist.
  - Three-dot menu: Edit, Remove (and Pause jobs for jobs).
- Work Profile strip below: "1 role · Available for jobs" (or "Work profiles are not enabled yet" when the flag is off).
- Tapping a card opens card details (existing sheet G of Stage 4.14) with its own status and checklist. Company service cards also offer "Edit company details" which reopens CD for that category. Job cards offer the E and F steps (kind, qualifications).
- Newly saved items must appear on A immediately after the save.

## 3. Data (Supabase; `sql/patch_company_profiles.sql`)
Reuse `provider_category_profiles` (type), `provider_capabilities`, `provider_capability_evidence`, `verification_requirements`, `v_my_capability_status`. Add one table:
```sql
create table if not exists public.provider_company_profiles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_slug text not null references public.need_categories(slug),
  company_name text check (char_length(company_name) <= 80),
  registration_number text check (char_length(registration_number) <= 40),
  team_size text check (team_size in ('1-5','6-20','21-50','50+')),
  years_in_business text check (years_in_business in ('<1','1-2','3-5','6-10','10+')),
  service_areas text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, category_slug)
);
-- RLS: owner select, admin select; no anon; writes only through the RPC.
```
- One row per user and category, so one account can be a company in Transport and an individual in Technology. Removing the last service in a category keeps the row (it is a preference).
- RPC `save_company_category(p_category_slug text, p_services text[], p_roles text[], p_profile jsonb)` via `private.save_company_category_internal` + `SECURITY INVOKER` wrapper. In ONE transaction it: checks `capability_profiles_enabled`; requires the caller's saved type for this category to be `company`; validates slugs against the active catalog and the country's enablement; upserts the service rows (`capability_type='service'`) and, only if roles are enabled, the work rows (`'work'`); upserts the company profile; enforces the soft cap `max_provider_capabilities`; writes audit rows on change. It removes only items the user explicitly un-ticked in this session for THIS category and never touches other categories. Any failing item rolls back everything.
- Reject `service` items for a category whose saved type is `individual` (server enforced). Work roles are allowed for both types.
- Evidence: company documents (certificate, licences) belong to a separate company verification record with statuses Not Submitted, Pending Review, Verified, Rejected (reason stored), reviewer and timestamp. Service evidence is per capability and follows that capability's policy (`open`, `optional_proof`, `required_proof`); a `required_proof` service stays inactive until its own evidence is approved. A company-level approval never activates a service. Backend enforcement: providers cannot set verified or active on a required-proof capability; inactive capabilities are excluded from offers and advertising.
- Evidence bucket path `evidence/<user_id>/<category_slug>/<requirement_key>/...`; private; signed URLs; 5 MB; JPG/PNG/PDF only; auto-delete when the capability is removed; rate limits per user.
- Privacy: company name and service areas may be shown to employers and customers only through a later, additive public view; in this change they are private to the owner and admins. Registration number is never public. No evidence, phone or exact address in any public view. (Decision D-C2: confirm whether company name is public.)
- Type switching: Company -> Individual keeps saved services, hides them from the category sheet, excludes them from matching and public badges, and shows "Hidden: offered as Company only" on A until the user switches back. Individual -> Company keeps roles and adds the services section.
- Company type changes no verification rule yet. Later, `verification_requirements` can add a business-registration requirement for companies (separate change).

## 4. Flutter
- New: `features/provider/presentation/widgets/company_details_step.dart` (CD), `CompanyProfile` model, repository `saveCompanyCategory(...)`, `getCompanyProfile(category)`, cubit state for the step draft (services, roles, company fields). D is the existing category sheet in Company mode; do not fork it: the provider type decides which sections render.
- Navigation only: B2 -> D -> CD -> close -> A refresh. Individual navigation is unchanged.
- Constants: `Rpcs.saveCompanyCategory`, `Tables.providerCompanyProfiles`.
- l10n in en, sw, fr, rw, ar (RTL): keys for every string above (`companyDetailsTitle`, `companyDetailsSub`, `companyName`, `companyRegistrationNumber`, `companyTeamSize`, `companyYearsInBusiness`, `companyServiceArea`, `companyProofTitle`, `companyProofNote`, `companySave`, `companyNextDetails`, ...). English complete; others fall back; missing keys listed.
- Accessibility: radio/checkbox semantics, labelled inputs, 44px targets, contrast 4.5:1, 200% text scale, 360px, light and dark, focus order top to bottom, error text associated with its field.
- Offline: cached read of the catalog and the loaded profile; no queued writes; clear retry.
- Analytics (no personal data): `company_path_started`, `company_services_selected` (count), `company_details_saved`, `company_proof_uploaded`.

## 5. Phases (small PRs; after each: `flutter analyze`, `flutter test`, SQL checks, Home baseline diff, "how to try it", tracker update)
- P0 Plan, tracker, decisions, baselines.
- P1 SQL: `provider_company_profiles`, `save_company_category`, validations, RLS, audit; verification query block and rollback note; dry-run not needed (no data moves).
- P2 SQL: company verification record and statuses, per-capability policy and active/status columns, backend enforcement (required-proof stays inactive, no offers), storage paths, rate limits.
- P3 Flutter: D in Company mode (sections, footer logic, drafts) and CD (fields, chips, validation).
- P4 Flutter: proof checklist and upload, per-state display, resubmit after rejection.
- P5 Flutter: A for Company users (cards, chips, Work Profile strip, "Edit company details", hidden-services state after a type change).
- P6 Admin: evidence queue grouped by company/category with per-capability approve/reject + reason; company profile read-only panel.
- P7 Localization, accessibility, dark mode, 360px, offline, cleanup, update `BUILD_PLAN.md` and README.

## 6. Test matrix
| Area | Case |
|---|---|
| Flow | B -> B2 (Company) -> D -> CD -> save -> A; Back from CD returns to D with ticks intact; Back from D returns to B2 with value; leaving mid-flow asks save/discard |
| D logic | Footer disabled with nothing ticked; enabled with only services, only roles, or both; summary text correct; roles section hidden when roles flag/country is off |
| Atomic save | Services + roles + company details saved in one transaction; a failing item rolls back everything; other categories untouched |
| Per category | Company in Transport and Individual in Technology: both persisted and each shows the right sections after reopen |
| Individual guard | RPC rejects `service` items for a category saved as `individual`; roles accepted |
| Roles | Company roles saved as work capabilities with empty metadata and the status their policy gives (no Self-declared label); no kind/qualification steps shown in the company flow; Job card prompts to add them |
| Verification | Open, optional-proof and required-proof services behave per policy; required-proof stays inactive until approved and gets no offers; reject with reason and resubmit; company certificate never activates a regulated service; approving one capability never verifies another; wrong type/size rejected; other users and anon cannot read rows or files |
| Type switch | Company -> Individual hides but keeps services; matching and public badges exclude them; switching back restores them |
| Cap | The 31st capability is rejected with a clear message; limit read from `system_settings` |
| RLS | Every new table and the storage bucket verified as owner, other user, admin and anon |
| Privacy | Registration number and evidence never in any public view; company name and areas not public in this change |
| Flags | `capability_profiles_enabled` off: no new screens or writes; roles flags off: no roles section |
| Offline | Failed save keeps the form and shows Retry; no queued write |
| A screen | New services and jobs appear immediately; chips count correctly; Services chip absent when none |
| Localization | 5 locales, RTL, dark, 360px, 200% scale, no overflow |
| Home protection | Snapshots, view/RPC columns and feed results identical to baseline; no Home file in the diff |
| Regression | Individual path, Loans, Forex, Needs, offers, accept, contact reveal, trust, watchlist, discovery plans unchanged |

## 7. Definition of done
- A user who picks Company on B2 gets D, then CD, then lands on A with their services and job roles saved atomically for that category only.
- Individuals are unaffected. Each category keeps its own type, company details and capabilities.
- Per-capability verification, privacy and flags behave as above; Home is identical to the baseline.
- All tests pass, `flutter analyze` is clean, five locales, RTL, dark mode and 360px verified, and Stage 4.15 and its trackers in `BUILD_PLAN.md` are complete.

## 8. Open decisions (recommend, then wait)
- D-C1 Resolved by the verification spec: company verification is separate, and each regulated service needs its own approved evidence.
- D-C2 Is the company name public to employers and customers? (Recommended: yes later, via an additive public view, after a privacy review.)
- D-C3 Should the company details step be skipped on later visits to the same category, or always shown prefilled? (Recommended: always shown prefilled, one tap.)
- D-C4 Should Company require a business registration number for regulated categories? (Recommended: separate change through `verification_requirements`.)
- D-C5 Can a company add staff or multiple operators? (Out of scope.)
