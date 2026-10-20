# FINAL BUILD PROMPT: Provider Services with multiple capabilities and Work Profiles (Nipanze)

You are a senior Flutter + Supabase engineer. Build the feature below in the existing Nipanze repo. The backend is **Supabase Cloud** (hosted), not a local stack.

## 0. DO THESE FIRST, IN ORDER (before writing any code)
1. **Read `.agents/AGENTS.md` completely and follow it** for repo conventions, commands, review rules and anything about how to work with this project. If something in this prompt conflicts with `.agents/AGENTS.md`, stop and tell me which rule conflicts and which you propose to follow. Never silently pick one.
2. Read `BUILD_PLAN.md` and `README.md`, and the SQL in `sql/` (`schema.sql`, `seed.sql`, `patch.sql`, `merged.sql` and the Needs / verification / marketing / creative patches). This feature EXTENDS the capability system from Stages 4.8 to 4.13 (`need_categories`, `need_capabilities`, `provider_capabilities`, `verification_requirements`, `can_perform_marketplace_activity`, `VerificationGateModal`, Needs -> offers -> accept -> contact reveal, `get_provider_opportunities`). Do not build a parallel system.
3. **Create the build plan and tracker for this feature** (section 7). It is the source of truth for what is built. Create it before any implementation and keep it updated after every phase.
4. **Explore the repo and Supabase project, report, and wait for my OK** (section 8). No implementation until I approve the plan.

## 1. Working with Supabase Cloud (rules)
- Write all database changes as re-runnable, non-destructive SQL patch files in `sql/` (for example `sql/patch_capability_profiles.sql`), following the repo's patch style. Also fold them into `sql/patch.sql` and `sql/merged.sql` the way earlier stages did, unless `.agents/AGENTS.md` says otherwise.
- **Never run anything against the production project without my explicit approval.** Apply and test on a staging/dev project first. If you have no access (CLI, MCP or credentials), do not guess: output the SQL and the exact steps for me to paste in the Supabase SQL editor, plus the verification queries and expected results.
- Never commit or print secrets, service-role keys or connection strings. Use existing env/config handling.
- Every migration includes: a dry-run or report mode where data moves, a verification query block, a rollback note, and idempotency (a second run changes nothing).
- Use Row Level Security on every new table; no `anon` grants unless explicitly needed; storage bucket for evidence is private with signed URLs only. Check `pg_cron` availability before scheduling jobs and fall back to documenting the schedule.
- Keep Edge Functions, RPCs and triggers consistent with existing patterns (`private.*_internal` + `SECURITY INVOKER` wrapper, `P02xx` error codes for Needs, audit log writes).
- Respect existing generated types / models and run the repo's analyze, test and codegen commands exactly as `.agents/AGENTS.md` describes.

## 2. Non-negotiables
1. **Multiple capabilities are required.** One account can hold many capabilities across categories at once: services (Excavator Hire, Crane Hire, Visa Assistance, Photography...) and work roles (Machine Operator, Driver...). Nothing may assume one category, profession or role per user.
2. **Each capability is independent**: its own details, evidence, verification status, gating, edit and remove. Editing or removing one never changes another. Verifying one never verifies another.
3. **Home and the Marketplace feed must not change** (section 9).
4. Never rename or delete existing category or capability slugs. Existing users' selections must survive the migration (dry-run report first).
5. Everything ships behind flags (section 14). Flag off = the app behaves exactly as today.
6. Identity KYC stays account-level. Provider verification is per capability.
7. **Evidence is not proof.** Uploaded documents are evidence for review. Phone verification and ID/KYC prove only who controls the account, never that someone is a legitimate agent, licensed professional or equipment owner. "Provider verified" is granted only by an admin approving that capability's evidence, never automatically by uploads, phone or KYC.
8. **Onboarding stays lightweight.** The only thing required to save a service or work role is ticking it (plus the role and kind for a work role). Everything else (qualifications, proof, experience, pay) can be added later, drafts are saved, and nothing blocks saving. Stronger verification is requested only at the gate points in section 6, for the capabilities and activities that require it.
9. **Providing a service and looking for a job are different intentions** and stay different records with different matching. A user may hold either or both (for example an excavator owner who also works as an operator). Never infer one from the other.

## 3. The UX to build (matches the attached screens A to G; reuse existing tokens and widgets)
The existing Provider Services page (`/account/services`) keeps its header, its "Work Profile" strip, its empty state ("No Services Added Yet") and its blue "+ Add Service" button. Categories and every other step live inside the **Add Service bottom sheet**, exactly as in the live app.

**Screen A: Provider Services (my summary). The user's own items appear FIRST.**
- Filter chips: All N, Services N, Jobs N.
- One card per capability, newest or most recently edited first: icon tile, title, a "Service" (blue) or "Job" (purple) tag, category, kind chips for jobs, a status pill (Self-declared / Pending review / Provider verified / Rejected / Expired) and a one-line note ("Fleet photos and logbook approved", "4 of 5 qualifications", "Add agency registration to verify"), and a three-dot menu (Edit, Pause jobs, Remove).
- Tapping a card opens sheet G.
- Below the cards: the Work Profile strip ("1 role · Available for jobs · 3 open jobs match"; or "Work profiles are not enabled yet" when the flag is off). It is a summary and shortcut only. The cards are the work profiles.
- Empty state unchanged until the first item is saved; then the first card replaces it.
- A work profile created inside any category must appear here immediately after saving.

**Add Service sheet** (opened by the FAB)
- **Sheet B, Choose Category:** search field, then the 14 categories (icon tile, name, one-line description, chevron). A green count badge shows how many capabilities the user already holds in that category.
- **Sheet C, Category (jobs OFF):** back arrow + category name; purple card "I want jobs in this category" with a switch (shown only if work profiles are enabled for this category and country); WHAT I OFFER with small titled groups of checkbox rows; sticky blue "Save services (N)". Saving never blocks on verification.
- **Sheet D, Category (jobs ON):** the switch turns purple; WHAT I OFFER collapses to a row ("2 selected" with a chevron); STEP 1 OF 3 "What role do you do?" with multi-select role cards (name + hint); sticky purple "Next: choose your kind".
- **Sheet E, Kind:** STEP 2 OF 3, the role's question ("Which machine do you operate?"), multi-select chips, count line. With several roles ticked, step through them one by one ("Role 1 of 2").
- **Sheet F, Qualifications and proof:** STEP 3 OF 3; role-specific checkbox list with an "Uploaded" tag where proof exists; dashed upload card; chips for years of experience, availability, languages; expected pay (amount + period); sticky "Save work profile".
- **Sheet G, Card details:** role/service title, status pill, "N open jobs match this profile", checklist "What is needed for the verified badge" with per-item state (Under review, Approved, Self-declared, Not added) and Add/Add proof actions; buttons Edit, Pause jobs for this role, Remove.
- After any Save the sheet closes, a short confirmation appears, and screen A refreshes.

Colours: Offer = blue, Jobs = purple. Status uses icon + text, never colour alone. Reuse existing design tokens; the attached canvas colours are fallbacks only.

## 4. Multiple capabilities: how it works
- Multi-select everywhere. The user can tick many services in a category, add other categories later, and add as many work roles as they like.
- **Each ticked service = one `provider_capabilities` row.** **Each ticked work role = its own row** with `capability_type='work'` (slug such as `work_machine_operator`), so several roles, separate verification, the existing requirement hierarchy, gating and matching all work with no new profile table. (Propose a different model in your plan only if you find a real blocker.)
- A user can hold several roles in one category and several kinds per role.
- Soft cap `max_provider_capabilities` (default 30, in `system_settings`); never gated behind Pro without asking me.
- Saving is **bulk and atomic**: one RPC `save_provider_capabilities(items jsonb)` upserts the ticked items and removes only items the user explicitly removed in this session, in one transaction. It must never delete capabilities from categories it did not touch.

## 5. Data and backend (extend minimally; details below)
- Reuse `need_categories`, `need_capabilities`, `provider_capabilities`, `verification_requirements`, `v_provider_badges`, admin queue.
- Add: `need_capabilities.capability_type` ('service' | 'work', default 'service'), `ui_group_slug`, `sort_order`; per-capability profile in `provider_capabilities.metadata` (kind_ids, qualification_ids, years_experience, availability, languages, willing_to_travel, expected_pay; keep existing audience metadata); `provider_capability_evidence(id, provider_capability_id, requirement_key, file_url, status pending|approved|rejected|expired, reject_reason, expires_at, reviewed_by, reviewed_at, created_at)`; `required_evidence text[]` and `expires_after_days` on `verification_requirements`; a view `v_my_capability_status` that derives Self-declared / Pending review / Provider verified / Rejected / Expired.
- Roles, kinds and qualifications: seed from `provider_services_v2.json` (attached; it now includes the Business Administrator / Office Manager role) as catalog tables or a versioned asset (propose which in your plan).
- Catalog regrouping: keep DB `need_categories` as they are and apply the 14 groups as `ui_group_slug` (recommended), so duration settings keys, `needs_enabled_<slug>` and verification rows keep working. On any slug collision keep the existing slug (for example `flight_tickets`, `excavator_hire`, `visa_assistance`, `driving_school`, `marketing_services`), record the new name as a label, and list the mapping. Merge duplicates (for example Wedding Photography + Graduation Photography -> photography) by re-pointing `provider_capabilities`, `needs_requests.capability_slug` and requirement rows, keeping the highest verification level and all evidence, with `legacy_slug` aliases so old links, saved plans and interests still work.
- Jobs reuse Needs: a Need with `details.engagement='hire_person'`, `details.role_id`, `details.kind_ids[]`, `details.required_qualification_ids[]`. Applications are `need_offers`. Extend the validate trigger so the offer-maker must hold the capability (and the work role) and meet the requirement table's evidence/verification rules. Needs durations, expiry, offer limits, blocks, trust and contact reveal stay as they are.
- Matching: pure SQL function `private.capability_match_score(need, provider_capability)`. Hard filters: category, capability/role, at least one shared kind. Score = ticked required qualifications / required (100 if none), whole percent, ties by approved-evidence count then recency. It also drives `get_provider_opportunities` and the "N open jobs match" counts.
- RLS: users read/write only their own capability and evidence rows; public views expose capability, level and counts only; evidence files private.

## 6. Verification (per capability)
- `can_perform_marketplace_activity(activity, category, capability)` stays authoritative; gates are server-enforced and mirrored by `VerificationGateModal` for: create provider capability, make an offer, accept, unlock contact.
- Users can never self-promote (existing trigger). Admin approval of that capability's evidence sets `provider_verified`. Licences expire and downgrade only that capability (nightly job + notification 14 days before).
- Rejections show a reason and allow resubmission. Every admin decision is audit-logged.
- Travel & International stays offerable only by `provider_verified` capabilities.
- Example: Excavator Hire = Provider verified, Visa Assistance = Pending review, Machine Operator = Self-declared. An offer on a visa Need is gated; an offer on an excavator Need is allowed.

## 7. BUILD PLAN AND TRACKER (create first, keep updated)
Create a new stage in `BUILD_PLAN.md` (for example "Stage 4.14: Provider capability profiles and Work Profiles") in the file's existing style, unless `.agents/AGENTS.md` says tracking lives elsewhere. It must contain:
1. **Scope and findings** from your exploration (what exists, what is missing, risks).
2. **Decisions log** with status (open / decided / date): work role as capability row, evidence table vs metadata, roles storage, ui grouping vs re-categorising, soft cap number, anything else.
3. **Phase table** with these columns: Phase | Task | Files / SQL | Tests | Status (Not started / In progress / Done / Blocked) | Date | Notes. One row per task, not just per phase.
4. **Per-category tracker**: a table of the 14 categories with columns Catalog seeded | Offer sheet | Roles/kinds/quals | Evidence rules | Hire Need | Flag state (global/country) | Status.
5. **Test tracker** mirroring the test matrix, with pass/fail and date.
6. **Flag tracker**: each setting from the enablement part, its current value per environment.
7. **Verification log**: for each phase, the commands run and results (analyze, tests, SQL checks, Home baseline diff).
Update the tracker in the same commit as the work. Do not mark anything Done without its tests passing.

Phases (each a small PR):
- P0 Plan, tracker, decisions, baselines (Home snapshots, view/RPC column dumps, feed query on seed data)
- P1 SQL catalog: `capability_type`, `ui_group_slug`, aliases, seed 14 categories, roles, kinds, qualifications; migration dry-run report. No UI change.
- P2 SQL: evidence table, requirements extensions, status view, RLS, private storage bucket, bulk save RPC, expiry job, admin approve/reject RPCs
- P3 Flutter: screen A (summary cards, chips, strip) + Add Service sheets B and C (multi-select across categories, save)
- P4 Flutter: sheets D to F (roles, kinds, qualifications, evidence upload, multi-role stepping) and sheet G
- P5 Hire-person Needs, validate trigger, `capability_match_score`, opportunities and counts
- P6 Admin portal: per-capability evidence queue, Work profiles settings page (flags per country and category), audit log
- P7 Localization (en, sw, fr, rw, ar, RTL), accessibility, dark mode, 360px, offline cached browsing, cleanup, final BUILD_PLAN/README update
After each phase: analyze, tests, SQL checks, Home baseline diff, short "how to try it", and update the tracker.

## 8. Explore, report, then wait
Reply with: how the current Provider Services page, picker, `provider_capabilities`, verification tables, offer validate trigger and `get_provider_opportunities` work today; the exact live catalog from Supabase; a diff against `provider_services_v2.json` with slug mapping; counts of rows that would move; a file-by-file plan; the draft Stage entry for BUILD_PLAN; risks; open questions; any conflict with `.agents/AGENTS.md`. Wait for my OK.

## 9. PROTECTED: Home and the Marketplace feed
Home is approved as it is: header "Nipanze" with the green "N active listings" line and bell; tabs For You / Loans / Forex / Needs and the filter button; shared listing cards; discovery prompts on For You only; Provider Opportunities where they appear now; bottom bar Home / Watchlist / + / Activity / Account.
- Do not edit Home, the feed widgets, `ListingCard`, `NeedCard`, `ListingExpiryIndicator`, the discovery card, bottom navigation, the + sheet layout, or theme values they use. No new banners, chips, sections, badges or tabs on Home.
- Hire-person Needs use the existing card with no new layout. Roles, qualifications and match % appear only inside Need detail and offer screens.
- `v_loan_listings`, `v_forex_listings`, `v_needs_listings`, `get_for_you_needs`, `get_provider_opportunities` keep columns, names, ordering and grants. Changes are additive only. With no new data, results are identical to today.
- Capture baselines before changing anything and diff after every phase. Any difference is a failure. If a task seems to need a Home file, stop and ask.

## 10. States, localization, accessibility
Empty, first item, many items, soft cap reached, removing the last role, pausing jobs (keeps data, hides from matching, confirm dialog), duplicate ticks, rejected evidence resubmission, expired evidence, offline (cached read, no queued writes, clear retry), upload failure, large lists (search over 12 items), drafts per step, Back never loses ticks, leaving mid-flow asks save/discard. All taxonomy strings in l10n keyed by slug (`cap.excavator_hire`, `role.machine_operator`, `kind.excavator`, `qual.operator_licence`) in en, sw, fr, rw, ar (English complete, others fall back, missing keys listed). RTL correct. Tap targets at least 44px, labels on icon buttons, contrast at least 4.5:1, 200% text scale, 360px, light and dark.

## 11. Test matrix (must pass; mirror it in the tracker)
| Area | Case |
|---|---|
| Summary screen | A saved service and a saved work profile both appear as cards on screen A immediately, with correct tag, category, kinds and status; filter chips count correctly |
| Multiple capabilities | One user saves Excavator Hire, Crane Hire, Visa Assistance, Photography, work_machine_operator, work_driver across 4 categories: all 6 present after reopen |
| Independence | Remove Crane Hire: others untouched. Edit Operator kinds: Driver unchanged. Verify Excavator Hire: others stay self-declared |
| Bulk save | Saving one category does not delete other categories' capabilities; a failing item rolls back the whole save |
| Cap | The 31st capability is rejected with a clear message; limit read from settings |
| Gating | Offer on a visa Need gated while visa is unverified; offer on an excavator Need allowed when excavator is verified |
| No self-verify | Direct update of level, `verified_*` or evidence status by a user fails |
| Roles and matching | Operator[excavator, loader] matches an excavator-operator Need; grader-only no match; 4 of 4 = 100%, 3 of 4 = 75% |
| Migration | Dry-run lists every moved row; rerun changes nothing; merged duplicates keep highest verification and all evidence; none dropped |
| Privacy | Public views show capability, level and counts only; no evidence, phone or exact address |
| Supabase | RLS verified for every new table and the storage bucket as owner, other user and anon |
| Home protection | Snapshots (4 tabs, light/dark, 360px), view and RPC columns, and feed results identical to baseline; flag off = no behaviour change; no Home file in the diff |
| Regression | Loans, Forex, Needs posting, offers, accept, contact reveal, trust, watchlist, discovery plans, expiry migration unchanged |

## 12. Definition of done
- A user can hold many capabilities across categories, each with its own details, proof, status and gating, and can add, edit, pause and remove them independently.
- Screen A shows the user's services and jobs first; any new work profile appears there immediately.
- All 14 categories behave as described in the section 13, driven by catalog data.
- Matching and "N open jobs match" work through the existing Need -> Offer -> Accept -> Contact flow.
- Migration loses nothing and reports every mapping. Flags let me enable per category and country without a deploy.
- Home is identical to the baseline; all tests pass; `flutter analyze` is clean; five locales, RTL, dark mode and 360px verified.
- The Stage entry in BUILD_PLAN.md and its trackers are complete and accurate.

---

## 13. WHAT HAPPENS IN EACH CATEGORY (acceptance reference)
Generate every screen from the catalog (`provider_services_v2.json` seeded into the DB). Behaviour below is data-driven: the same screens, different catalog rows. Evidence and gating below are SUGGESTED DEFAULTS seeded into `verification_requirements` and editable by admins. I am not a lawyer: list every regulated category in your plan so I can confirm it against local law per country before enabling it.

**Same for every category**
- *Offering services*: Add Service (FAB) -> sheet B (choose category) -> sheet C with the "I want jobs in this category" switch OFF and service groups with checkboxes. Ticking services and saving creates one capability per service. Verification never blocks saving. Saved items appear at once as cards on screen A.
- *Wanting jobs*: same sheet C, switch ON -> sheet D role picker (multi-select) -> sheet E kind question per ticked role -> sheet F qualifications and proof -> save creates one work capability per role (`capability_type='work'`), shown as a purple "Job" card on screen A.
- Status per capability: Self-declared, Pending review, Provider verified, Rejected (with reason), Expired. Each is independent.
- A hire-person Need in this category shows in the normal feed card; the match % and "Needs: ..." chips appear only in Need detail and offer screens.
- Every saved capability or work profile appears on screen A (the summary), is editable and removable from its own card, and opens sheet G with its own status and checklist.


### 13.1 Technology & Digital (`technology_digital`)
- **Rollout wave:** 2. **Regulation level:** Low.
- **Offer mode (sheet C):** 3 groups, 8 services: Build (Software Development, Website Development, Mobile App Development, Automation); Support & Infrastructure (IT Support, Networking, Cybersecurity); Other (Other Technology).
- **Jobs mode (sheet D, roles):** Developer, IT Technician, Security Specialist, Project Manager, Team Lead / Manager.
- **Kind step (sheet E):** Developer: "What do you build?" -> Frontend, Backend, Full-stack, Mobile, QA / Tester, DevOps | IT Technician: "What do you do?" -> Helpdesk, Hardware repair, Network installation, CCTV & access control | Security Specialist: "Which area?" -> Network security, Penetration testing, Security audits | Project Manager: "What kind of projects?" -> Software, IT infrastructure, Digital transformation | Team Lead / Manager: "What do you lead?" -> Dev team, IT / support team, Product.
- **Qualification ticks (sheet F):** Developer: Degree / Diploma in IT or CS; Portfolio or GitHub link; Cloud certification (AWS/Azure/GCP); 3+ years experience | IT Technician: CompTIA A+ / N+; CCNA; Own toolkit; 2+ years experience | Security Specialist: CEH; CISSP / CISM; ISO 27001; Police clearance | Project Manager: PMP / PRINCE2; Agile / Scrum certified; Led 3+ projects; Degree | Team Lead / Manager: Managed 5+ people; Degree; 3+ years leadership.
- **Evidence for services:** Self-declared. Optional portfolio/GitHub link.
- **Evidence for work roles:** Optional certifications (CompTIA, CCNA, cloud). Security Specialist: police clearance recommended.
- **Gating:** No hard verification gate.
- **Example hire-person Need:** Hire a Backend Developer (Kampala, 3 months, remote ok). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.2 Marketing & Promotion (`marketing_promotion`)
- **Rollout wave:** 2. **Regulation level:** Low.
- **Offer mode (sheet C):** 3 groups, 11 services: Campaigns (Digital Marketing, Social Media Marketing, Advertising Campaigns, Brand Promotion, Event Promotion, Affiliate Marketing); Content & Reach (Content Creation, Influencer Marketing, Product Reviews, I Have an Audience); Other (Other Marketing Services).
- **Jobs mode (sheet D, roles):** Marketer / Specialist, Content Creator, Marketing Manager, Campaign Project Manager.
- **Kind step (sheet E):** Marketer / Specialist: "Which channel?" -> Social media, SEO / SEM, Email, Brand, Community management | Content Creator: "What do you produce?" -> Video, Photo, Writing, Design, Podcast | Marketing Manager: "What scope?" -> Brand, Digital, Events & promotions | Campaign Project Manager: "Campaign type?" -> Digital, Field / activation, Event.
- **Qualification ticks (sheet F):** Marketer / Specialist: Marketing diploma / degree; Google Ads / Meta certified; Case studies or portfolio; 2+ years experience | Content Creator: Portfolio; Own equipment; Audience size proof | Marketing Manager: Degree; Managed budgets; Managed 3+ people | Campaign Project Manager: PMP / PRINCE2; Led 3+ campaigns.
- **Evidence for services:** Self-declared. "I Have an Audience" keeps its existing self-declared audience fields (platforms, follower count).
- **Evidence for work roles:** Portfolio / case studies. Audience size proof optional.
- **Gating:** No hard verification gate.
- **Example hire-person Need:** Hire a Social Media Marketer (Nairobi, 1 month). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.3 Business & Professional Services (`business_professional_services`)
- **Rollout wave:** 2. **Regulation level:** High (licensed professions).
- **Offer mode (sheet C):** 4 groups, 9 services: Finance & Legal (Accounting & Tax, Legal Services, Company Registration); Advisory (Business Consulting, HR Services); Design & Engineering (Architecture, Engineering, Driving School / Driver Training); Other (Other Professional Services).
- **Jobs mode (sheet D, roles):** Accountant / Finance Officer, Lawyer / Legal Officer, Engineer, Architect / Designer, HR Officer / Manager, Business Administrator / Office Manager, Consultant, Project Manager.
- **Kind step (sheet E):** Accountant / Finance Officer: "What area?" -> Bookkeeping, Tax, Audit, Payroll | Lawyer / Legal Officer: "What area?" -> Corporate, Property, Contracts, Compliance | Engineer: "Which discipline?" -> Civil, Electrical, Mechanical, Mining | Architect / Designer: "What do you design?" -> Buildings, Interiors, Landscape | HR Officer / Manager: "What area?" -> Recruitment, Payroll & benefits, Training & compliance | Business Administrator / Office Manager: "What kind of admin work?" -> Office administration, Operations support, Executive assistant, Records & documentation | Consultant: "Advisory area?" -> Strategy, Operations, Finance, Compliance | Project Manager: "What kind of projects?" -> Business, Compliance, Operations.
- **Qualification ticks (sheet F):** Accountant / Finance Officer: CPA / ACCA / CPA-U; Degree; Practising certificate; 3+ years experience | Lawyer / Legal Officer: Bar admission / practising certificate; LLB; 3+ years experience | Engineer: Degree in engineering; Registered with engineers board; Site experience | Architect / Designer: Registered architect; Portfolio; CAD/BIM skills | HR Officer / Manager: HR diploma / degree; IHRM / CIPD; 3+ years experience | Business Administrator / Office Manager: Diploma / degree in business administration; Office software skills (documents, spreadsheets, email); 2+ years experience; References | Consultant: Degree; Case studies; 5+ years experience | Project Manager: PMP / PRINCE2; Led 3+ projects.
- **Evidence for services:** Legal Services: practising certificate. Accounting & Tax and Company Registration: professional registration. Architecture/Engineering: board registration. Driving School: school licence.
- **Evidence for work roles:** Lawyer, Accountant, Engineer, Architect: professional registration or practising certificate required for the Provider verified badge.
- **Gating:** Offering regulated services to a Need requires provider_verified (set via verification_requirements, admin-editable).
- **Example hire-person Need:** Hire a Company Registration Officer (Kampala, contract). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.4 Education & Training (`education_training`)
- **Rollout wave:** 3. **Regulation level:** Medium (placements and nursing are regulated).
- **Offer mode (sheet C):** 2 groups, 12 services: Learning (Private Tutoring, Online Classes, Exam Preparation, Language Training, Computer Training, Professional Training, Vocational Training, Academic Consulting); Admissions & Placements (University Admissions, Study Abroad Guidance, Internship Placement, Health / Nursing Placements).
- **Jobs mode (sheet D, roles):** Teacher / Tutor, Trainer / Instructor, Placement Coordinator, Programme Manager.
- **Kind step (sheet E):** Teacher / Tutor: "What do you teach?" -> Primary, Secondary, University, Languages, Exam prep | Trainer / Instructor: "Training field?" -> Computer / IT, Vocational / technical, Professional / corporate, Driving | Placement Coordinator: "What placements?" -> Internships, Nursing / health, Study abroad, University | Programme Manager: "What programmes?" -> Training programmes, Placement programmes.
- **Qualification ticks (sheet F):** Teacher / Tutor: Teaching certificate / degree; Registered with teaching board; 2+ years teaching; Subject specialisation | Trainer / Instructor: Trade certificate; Trainer-of-trainers (ToT); Industry experience 3+ years | Placement Coordinator: Education or HR background; Partner network; Counselling certificate | Programme Manager: Degree; Managed 3+ programmes.
- **Evidence for services:** Tutoring and training: self-declared. Health/Nursing Placements and Study Abroad Guidance: agency/registration evidence.
- **Evidence for work roles:** Teacher/Tutor: teaching certificate or degree (optional verification). Placement Coordinator: partner/licence proof.
- **Gating:** Verification required only for Health/Nursing Placements and Study Abroad Guidance.
- **Example hire-person Need:** Hire a Maths Tutor (Entebbe, weekends). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.5 Events & Celebrations (`events_celebrations`)
- **Rollout wave:** 3. **Regulation level:** Low to medium.
- **Offer mode (sheet C):** 4 groups, 11 services: Planning & Styling (Event Planning, Decoration, Cakes, Catering); Equipment & Venue Setup (Tents, Event Equipment, Sound Systems, Lighting); Entertainment & Hosting (DJs / MCs, Event Transport); Other (Other Events).
- **Jobs mode (sheet D, roles):** Event Manager / Planner, MC / DJ, Event Crew / Technician, Caterer / Chef, Event Supervisor.
- **Kind step (sheet E):** Event Manager / Planner: "What events?" -> Weddings, Corporate, Birthdays & parties, Graduations, Funerals & memorials | MC / DJ: "Which role?" -> MC, DJ, Both | Event Crew / Technician: "What do you operate?" -> Sound, Lighting, Tents & setup, Stage | Caterer / Chef: "What kind?" -> Event catering, Cakes & baking, Buffet / plated | Event Supervisor: "What scope?" -> Venue, Logistics, Guest management.
- **Qualification ticks (sheet F):** Event Manager / Planner: Event planning certificate; Portfolio of 5+ events; Insurance / permit; Team of 3+ staff | MC / DJ: Own equipment; Sample mix / video; References | Event Crew / Technician: Technical training; Own tools; Event experience 1+ year | Caterer / Chef: Food handler certificate; Health permit; Culinary diploma | Event Supervisor: Managed 5+ events; Team leadership.
- **Evidence for services:** Self-declared. Catering: food handler or health permit for the verified badge.
- **Evidence for work roles:** Event Manager: portfolio of events. Caterer/Chef: food handler certificate. Crew: technical training optional.
- **Gating:** No hard gate. Verification boosts ranking and trust.
- **Example hire-person Need:** Hire an MC / DJ for a wedding (Jinja, one day). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.6 Photo, Video, Music & Talent (`photo_video_music_talent`)
- **Rollout wave:** 3. **Regulation level:** Low.
- **Offer mode (sheet C):** 3 groups, 12 services: Photo & Video (Photography, Videography, Video Editors); Music Production (Recording Studios, Music Producers, Mixing & Mastering, Songwriters, Singers / Vocalists); On-screen & Performers (Actors / Actresses, Dancers, Background Extras, Music Video Models).
- **Jobs mode (sheet D, roles):** Photographer / Videographer, Audio Engineer / Producer, Performer / Talent, Production Manager.
- **Kind step (sheet E):** Photographer / Videographer: "What do you shoot?" -> Weddings, Corporate, Fashion & portraits, Music videos, Real estate, Graduations | Audio Engineer / Producer: "What do you do?" -> Recording, Mixing & mastering, Beat production, Live sound | Performer / Talent: "What kind?" -> Singer, Dancer, Actor, Model, Extra | Production Manager: "What productions?" -> Video / film, Music, Live events.
- **Qualification ticks (sheet F):** Photographer / Videographer: Portfolio link; Own camera / drone kit; Drone licence; Editing skills | Audio Engineer / Producer: Own studio / DAW; Portfolio; Audio engineering diploma | Performer / Talent: Showreel / audition clip; Agency representation; Performance experience | Production Manager: Managed 3+ productions; Budget handling; Crew network.
- **Evidence for services:** Self-declared plus portfolio link. Drone work: drone permit for verified.
- **Evidence for work roles:** Photographer/Videographer: portfolio, own kit, drone licence. Performer/Talent: showreel. Occasion tags (Wedding, Graduation...) apply here.
- **Gating:** No hard gate.
- **Example hire-person Need:** Hire a Wedding Videographer (Mukono, one day). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.7 Beauty, Fashion & Styling (`beauty_fashion_styling`)
- **Rollout wave:** 3. **Regulation level:** Low.
- **Offer mode (sheet C):** 2 groups, 5 services: Beauty (Makeup Artists, Hair Stylists); Fashion (Bridal Styling, Stylists, Wedding Dresses / Bridesmaid Outfits).
- **Jobs mode (sheet D, roles):** Makeup Artist, Hair Stylist, Stylist / Designer, Salon / Studio Manager.
- **Kind step (sheet E):** Makeup Artist: "Specialty?" -> Bridal, Fashion / editorial, Film / stage, Everyday | Hair Stylist: "Specialty?" -> Braiding, Salon styling, Bridal hair, Barbering | Stylist / Designer: "Specialty?" -> Wardrobe styling, Tailoring, Bridal wear | Salon / Studio Manager: "What scope?" -> Salon, Fashion studio.
- **Qualification ticks (sheet F):** Makeup Artist: Cosmetology certificate; Portfolio; Own kit; Hygiene certification | Hair Stylist: Cosmetology certificate; Portfolio; Salon licence | Stylist / Designer: Fashion diploma; Portfolio; Own workshop | Salon / Studio Manager: Managed 3+ staff; Business licence.
- **Evidence for services:** Self-declared plus portfolio. Hygiene certificate optional.
- **Evidence for work roles:** Makeup Artist / Hair Stylist: cosmetology certificate optional. Salon Manager: business licence.
- **Gating:** No hard gate. Keep gender-inclusive: no gender filters or labels.
- **Example hire-person Need:** Hire a Bridal Makeup Artist (Kampala, Saturday). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.8 Construction & Building (`construction_building`)
- **Rollout wave:** 1. **Regulation level:** High (safety).
- **Offer mode (sheet C):** 4 groups, 9 services: Contracting (Building Contractors, Roofing, Excavation, Concrete); Trades (Plumbing, Electrical Works); Materials & Survey (Construction Materials, Surveying); Other (Other Construction).
- **Jobs mode (sheet D, roles):** Site Manager, Project Manager, Foreman / Supervisor, Skilled Tradesperson, Surveyor.
- **Kind step (sheet E):** Site Manager: "What type of sites?" -> Residential, Commercial, Infrastructure | Project Manager: "What kind of projects?" -> Residential, Commercial, Roads & civil | Foreman / Supervisor: "Which trade?" -> Masonry, Roofing, Concrete, Finishing | Skilled Tradesperson: "Which trade?" -> Mason, Plumber, Electrician, Carpenter, Welder, Painter, Roofer | Surveyor: "What type?" -> Land, Quantity, Topographic.
- **Qualification ticks (sheet F):** Site Manager: Civil/Construction diploma or degree; Registered with engineers/contractors board; 5+ years on site; Safety certification (OSHA) | Project Manager: PMP / PRINCE2; Degree; Delivered 3+ projects | Foreman / Supervisor: Trade test certificate; Managed 10+ workers; Safety training | Skilled Tradesperson: Trade test (Grade I/II/III); Licence (electrical/plumbing); Own tools; 2+ years experience | Surveyor: Registered surveyor; Degree / diploma; Own instruments.
- **Evidence for services:** Contractors: registration/licence. Electrical Works: electrical licence. Plumbing: trade test certificate.
- **Evidence for work roles:** Site Manager/Foreman: registration + OSHA/safety certificate. Skilled Tradesperson: trade test grade + licence where required. Surveyor: registration.
- **Gating:** Offers on contractor/electrical needs require the matching evidence (provider_verified).
- **Example hire-person Need:** Hire an Electrician (Wakiso, 2 weeks). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.9 Energy & Water (`energy_water`)
- **Rollout wave:** 1. **Regulation level:** High (electrical and drilling).
- **Offer mode (sheet C):** 3 groups, 9 services: Power (Solar Systems, Batteries, Backup Power, Generators, Electrical Installation); Water (Boreholes, Water Systems); Advisory (Energy Consulting, Other Energy Services).
- **Jobs mode (sheet D, roles):** Solar / Electrical Technician, Borehole / Water Technician, Energy Engineer, Project Manager.
- **Kind step (sheet E):** Solar / Electrical Technician: "What do you install?" -> Solar PV, Batteries & inverters, Generators, Wiring | Borehole / Water Technician: "What do you do?" -> Drilling, Pump installation, Plumbing & tanks, Water treatment | Energy Engineer: "Which area?" -> Solar design, Energy audits, Grid / mini-grid | Project Manager: "What kind of projects?" -> Solar, Water, Electrification.
- **Qualification ticks (sheet F):** Solar / Electrical Technician: Electrical licence; Solar installer certificate; Safety training; Own tools | Borehole / Water Technician: Water technician certificate; Drilling permit; Own equipment | Energy Engineer: Engineering degree; Registered engineer; Design software skills | Project Manager: PMP / PRINCE2; Delivered 3+ projects.
- **Evidence for services:** Solar Systems: installer certificate. Boreholes: drilling permit. Electrical Installation: electrical licence.
- **Evidence for work roles:** Solar/Electrical Technician: electrical licence + installer certificate. Water Technician: certificate/permit.
- **Gating:** Offers on installation Needs require provider_verified for those capabilities.
- **Example hire-person Need:** Hire a Solar Technician (Gulu, 1 week). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.10 Transport & Logistics (`transport_logistics`)
- **Rollout wave:** 1. **Regulation level:** High (vehicles and public safety).
- **Offer mode (sheet C):** 4 groups, 10 services: Freight (Cargo Transport, Bulk Delivery, Heavy Haulage, Agricultural Transport, Cold Chain & Refrigerated); Delivery & Moving (Courier, Moving Services); Vehicles (Truck Hire, Vehicle Transport); Other (Other Logistics).
- **Jobs mode (sheet D, roles):** Driver, Fleet / Operations Manager, Dispatcher / Coordinator, Loader / Mover.
- **Kind step (sheet E):** Driver: "What do you drive?" -> Truck / heavy, Pickup / van, Bus / minibus, Motorcycle courier, Tanker | Fleet / Operations Manager: "What fleet?" -> Trucks, Vans & couriers, Mixed | Dispatcher / Coordinator: "What area?" -> Route planning, Customs & clearing, Warehouse | Loader / Mover: "What work?" -> Moving, Warehouse, Loading.
- **Qualification ticks (sheet F):** Driver: Valid driving licence (class); PSV badge; Clean driving record; Defensive driving certificate; Own vehicle | Fleet / Operations Manager: Logistics diploma / degree; Managed 10+ vehicles; Transport licence | Dispatcher / Coordinator: Logistics experience; Customs clearing licence | Loader / Mover: Physical fitness; Experience 1+ year.
- **Evidence for services:** Heavy Haulage and Cargo: transport licence + vehicle photos. Cold Chain: vehicle photos (+ food safety proof). Courier/Moving: self-declared.
- **Evidence for work roles:** Driver: driving licence class (+ PSV badge if carrying passengers), clean record. Fleet Manager: transport licence.
- **Gating:** Driver and haulage offers require provider_verified. Licence expiry downgrades only that capability.
- **Example hire-person Need:** Hire a Truck Driver (Mbarara, 3 months, class CE). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.11 Machinery & Equipment (`machinery_equipment`)
- **Rollout wave:** 1. **Regulation level:** High (safety).
- **Offer mode (sheet C):** 4 groups, 8 services: Earthmoving (Excavator Hire, Loader Hire, Grader Hire); Lifting & Power (Crane Hire, Generator Hire); Farm & Industrial (Tractor Hire, Industrial Equipment); Other (Other Machinery).
- **Jobs mode (sheet D, roles):** Machine Operator, Equipment Mechanic, Fleet / Equipment Manager, Site Supervisor.
- **Kind step (sheet E):** Machine Operator: "Which machine do you operate?" -> Excavator, Loader, Grader, Crane, Tractor, Roller, Forklift, Bulldozer, Concrete mixer / pump | Equipment Mechanic: "What do you service?" -> Heavy plant, Generators, Hydraulics, Electrical systems | Fleet / Equipment Manager: "What fleet?" -> Construction plant, Farm machinery, Industrial equipment | Site Supervisor: "Which sites?" -> Earthworks, Quarry / mining, Farm.
- **Qualification ticks (sheet F):** Machine Operator: Operator licence / certificate; Safety / OSHA certificate; 3+ years experience; Medical fitness; Can work away from home | Equipment Mechanic: Mechanic trade certificate; Own tools; Field repair experience | Fleet / Equipment Manager: Managed fleet of 5+ machines; Diploma / degree; Maintenance scheduling | Site Supervisor: Plant experience; Team leadership; Safety certification.
- **Evidence for services:** Excavator/Loader/Grader/Crane/Tractor Hire: fleet photos + ownership or logbook. Generator Hire: equipment photos.
- **Evidence for work roles:** Machine Operator: operator licence/certificate + safety (OSHA) certificate; kind = machine type. Mechanic: trade certificate. Fleet Manager/Site Supervisor: experience proof.
- **Gating:** Equipment hire offers need provider_verified. Operator offers need an approved operator licence.
- **Example hire-person Need:** Hire an Excavator Operator (Mukono quarry, 3 months, UGX 150,000/day). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.12 Agriculture & Agribusiness (`agriculture_agribusiness`)
- **Rollout wave:** 2. **Regulation level:** Medium.
- **Offer mode (sheet C):** 3 groups, 6 services: Farm Operations (Farm Services, Irrigation); Inputs & Livestock (Seeds & Inputs, Livestock Sourcing); Market (Produce Buyers, Other Agriculture).
- **Jobs mode (sheet D, roles):** Farm Manager, Agronomist / Extension Officer, Veterinary / Livestock Officer, Farm Worker / Operator.
- **Kind step (sheet E):** Farm Manager: "What farm?" -> Crops, Dairy, Poultry, Mixed | Agronomist / Extension Officer: "What focus?" -> Crops, Soil & irrigation, Pest management | Veterinary / Livestock Officer: "What animals?" -> Cattle, Poultry, Small ruminants | Farm Worker / Operator: "What work?" -> Tractor operation, Irrigation, Harvesting, Spraying.
- **Qualification ticks (sheet F):** Farm Manager: Agriculture diploma / degree; Managed 5+ workers; 5+ years farming experience | Agronomist / Extension Officer: Degree / diploma in agronomy; Field experience | Veterinary / Livestock Officer: Veterinary licence; Diploma / degree; Vaccination certification | Farm Worker / Operator: Tractor licence; Pesticide handling certificate; Experience 1+ year.
- **Evidence for services:** Self-declared. Livestock Sourcing and Seeds & Inputs: business registration optional.
- **Evidence for work roles:** Veterinary Officer: veterinary licence required for verified. Farm Worker/Operator: tractor licence or pesticide handling certificate if claimed.
- **Gating:** Veterinary role gated; everything else optional.
- **Example hire-person Need:** Hire a Tractor Operator (Masaka, harvest season). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.13 Procurement & Sourcing (`procurement_sourcing`)
- **Rollout wave:** 2. **Regulation level:** Medium.
- **Offer mode (sheet C):** 3 groups, 9 services: Sourcing (Bulk Procurement, Equipment Sourcing, Imported Products, Hard-to-Find Products); Parts & Supplies (Electronics Procurement, Industrial Parts, Spare Parts, Medical & Lab Supplies); Other (Other Procurement).
- **Jobs mode (sheet D, roles):** Procurement Officer / Manager, Sourcing Agent, Clearing & Customs Agent.
- **Kind step (sheet E):** Procurement Officer / Manager: "What do you buy?" -> Industrial, Electronics, Medical & lab, General supplies | Sourcing Agent: "Where do you source?" -> Local, China, Dubai, India, Europe / USA | Clearing & Customs Agent: "What do you handle?" -> Imports, Exports, Freight forwarding.
- **Qualification ticks (sheet F):** Procurement Officer / Manager: Procurement diploma (CIPS or similar); Supplier network; 3+ years experience | Sourcing Agent: Import/export experience; Language skills; Supplier contacts | Clearing & Customs Agent: Customs clearing licence; Logistics experience.
- **Evidence for services:** Self-declared. Medical & Lab Supplies: business/pharmacy registration for verified.
- **Evidence for work roles:** Customs/Clearing Agent: clearing licence. Procurement Officer / Sourcing Agent: references and supplier proof optional.
- **Gating:** Clearing agent and medical supplies gated.
- **Example hire-person Need:** Hire a Clearing Agent (Malaba border, contract). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### 13.14 Travel & International (`travel_international`)
- **Rollout wave:** 4. **Regulation level:** Very high (consumer protection).
- **Offer mode (sheet C):** 3 groups, 11 services: Bookings (Flight Tickets & Bookings, Accommodation, Airport Transfers, Tour Packages); Documents & Cover (Visa Assistance, Travel Documentation, Travel Insurance); Specialised (Hajj & Umrah, International Relocation, Travel Consultation, Other Travel Services).
- **Jobs mode (sheet D, roles):** Travel Agent / Consultant, Tour Guide, Driver-Guide, Operations Manager.
- **Kind step (sheet E):** Travel Agent / Consultant: "What do you handle?" -> Flights, Tours & packages, Visas, Hajj & Umrah, Relocation | Tour Guide: "What tours?" -> Wildlife safari, Cultural, City tours, Adventure | Driver-Guide: "What vehicle?" -> Safari vehicle, Minibus, Airport transfers | Operations Manager: "What scope?" -> Tours, Visa & documentation, Travel desk.
- **Qualification ticks (sheet F):** Travel Agent / Consultant: IATA certification; Travel agency licence; 2+ years experience | Tour Guide: Tourism board guide licence; First aid certificate; Languages spoken | Driver-Guide: Valid driving licence (class); Tourism licence; Clean driving record | Operations Manager: Tourism diploma / degree; Managed 3+ staff.
- **Evidence for services:** ALL offers require provider_verified: agency registration + business licence. Hajj & Umrah: the specific operating licence. Insurance: insurer/agent proof.
- **Evidence for work roles:** Travel Agent: agency licence (IATA optional). Tour Guide: tourism board guide licence + first aid. Driver-Guide: driving licence + tourism licence.
- **Gating:** Existing rule: Travel & International offerable only by provider_verified capabilities. Launch last, per country.
- **Example hire-person Need:** Hire a Safari Tour Guide (Murchison Falls, 5 days). Matching: same category + role + at least one shared kind; score = ticked required qualifications / required.

### Common fields in every work role (sheet F, all categories)
ID verified (auto from KYC), years of experience, availability, willing to travel, references available, languages, certificate/licence upload, expected pay (amount + period). Occasion tags (Wedding, Birthday, Graduation, Corporate, Baby shower, Funeral/memorial, Anniversary, Engagement, Other) apply only to Events and Photo/Video/Music.

---

## 14. ENABLE the Work Profile system (flags, switches, rollout, safety)
The system must be switchable at four levels, all in `system_settings` using the existing pattern (`needs_enabled_<slug>`), readable by the app and editable in the admin portal with no deploy:
1. `capability_profiles_enabled` (global kill switch, default false): off = app behaves exactly as today, no new screens, no new data written.
2. `work_profiles_enabled` (global, default false): turns on work roles: the "I want jobs in this category" switch in the category sheet, work cards on screen A and the match counts. With only `capability_profiles_enabled` on, users get the multi-capability Offer flow without jobs.
3. `work_profiles_enabled_<category_slug>` (per category, default false; per-country override like `needs_enabled`): turns jobs on for one category in one country. A category that is off still shows its Offer services; its roles are hidden and the "I want jobs in this category" switch is not shown.
4. `hire_person_needs_enabled` (+ per category/country, default false): lets employers post hire-person Needs. Keep it off until workers exist in that category, so employers never see an empty market.
Also: `max_provider_capabilities` (default 30), `work_profile_requires_kyc` (default true).

**Rollout plan (waves are defaults, editable in the admin portal)**
- Wave 0: deploy dark. Flags off. Migration dry-run reviewed and applied. Baselines captured.
- Wave 1: Uganda only, staff and test accounts, `capability_profiles_enabled` on. Then jobs for Machinery & Equipment, Transport & Logistics, Construction & Building, Energy & Water (the categories where operators, drivers and technicians are most needed and verification evidence is clearest).
- Wave 2: Business & Professional, Procurement & Sourcing, Technology, Marketing, Agriculture.
- Wave 3: Education, Events, Photo/Video/Music, Beauty & Fashion.
- Wave 4: Travel & International, only for provider_verified capabilities and only after the compliance review for that country is recorded in BUILD_PLAN.
- Per wave: enable workers first, wait until there are enough profiles, then enable `hire_person_needs_enabled` for that category. Add other countries one at a time (existing per-country overrides).
- Each wave needs a recorded go/no-go: SQL checks pass, Home baselines unchanged, support and admin review queue staffed.

**What "enabling" must do in the app**
- The "I want jobs in this category" switch in sheet C appears only when `work_profiles_enabled` is on AND the category is enabled for the user's country. Otherwise the sheet shows Offer services only (no switch, no greyed-out control). The Work Profile strip on screen A shows "Work profiles are not enabled yet" when the global flag is off (as today).
- Turning a category off later hides it from matching and from the roles list but never deletes users' saved work profiles. Show "Currently unavailable in your country" on the user's existing card.
- The Work Profile strip on screen A shows "N open jobs match" only when `hire_person_needs_enabled` is on for the user's categories and N > 0.
- Admin portal: a "Work profiles" settings page with toggles for all four levels, per country and category, the wave plan, counts (capabilities, work profiles, pending evidence, open hire-person Needs), and an audit log of every flag change.

**Work-profile safety rules (build them in, they are not optional)**
- Adults only: work profiles are visible to employers only when `profiles.kyc_status = 'approved'` and the user is 18+. Users may save a draft before KYC but are not matched or listed until approved.
- Privacy: employers see role, kinds, qualifications with status, experience, availability, area (district or city only) and an anonymised id until an offer is accepted. Phone, exact address and evidence files are never shown. Contact is revealed only through the existing accept -> unlock flow.
- Fairness: no filters or fields by gender, age, religion, ethnicity or marital status, and no photo requirement. Keep gender-inclusive as in Stage 4.11.
- Anti-scam: hire-person Needs may not ask workers to pay a fee to apply or to be hired. Add a guard (text check on title/description plus a report button), surface "Report this job", reuse block and the admin review queue, and show "Nipanze does not hold or move funds, does not pay wages and does not verify employers" on the job detail and in the offer flow.
- Wage disclosure: pay is shown as amount + period + currency, never hidden behind "negotiable" only unless the employer chooses "Open to offers" (existing Needs pattern).
- Evidence: private bucket, signed URLs, 5 MB limit, JPG/PNG/PDF only, virus scan if available, auto-delete when a capability is removed.
- Rate limits: new capability and evidence uploads are rate-limited per user, and admin decisions are audit-logged.

**Admin and operations**
- Verification queue per capability and per role (approve / reject with reason / request more), SLA shown, bulk filters by category and country.
- Evidence expiry job (nightly) and notification to the user 14 days before expiry.
- Support: a read-only "why isn't this person matching?" panel showing flags, KYC state, category enablement and missing evidence.
- Analytics (no personal data): capability_selected, work_role_selected, evidence_uploaded, evidence_approved, match_viewed, offer_made_on_hire_need, plus funnel from screen A to saved work profile.

**Extra tests for enablement**
| Case | Expected |
|---|---|
| `capability_profiles_enabled` off | No new screens or writes; Home and all flows identical to baseline |
| Only capability flag on | Offer flow works with multiple capabilities; no "I want jobs" switch in any category sheet |
| `work_profiles_enabled` on, category off | That category shows Offer services only; roles hidden; existing profiles kept and marked unavailable |
| Category on in Uganda, off in Kenya | Ugandan user sees roles; Kenyan user does not |
| `hire_person_needs_enabled` off | Employers cannot post hire-person Needs; the Work Profile strip on screen A shows no match count |
| KYC not approved | Work profile saved as draft, not matched or listed |
| Fee-to-apply text in a job | Blocked or flagged, report path works |
| Flag change | Audit row written; takes effect without a deploy |

