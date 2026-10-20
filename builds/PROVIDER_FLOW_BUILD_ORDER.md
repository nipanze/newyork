# Provider Services: which screens change, the new flow order, and the build order

Context: the live app already has the original seven screens (A Provider Services, B Choose Category, C and D category sheets, E Pick your kind, F Qualifications and proof, G card status and details). This file says what happens to each one, in what order users see them, and in what order to build. The design is the canvas "Provider Type Screen". Detailed specs: `VERIFICATION_SPEC.md`, `PROVIDER_TYPE_STEP_PROMPT.md`, `COMPANY_PATH_BUILD_PROMPT.md`, `IDENTITY_SWITCH_BUILD_PROMPT.md`.

## 1. Screen map (old live screen -> what happens)
| Old live screen | Action | New screen(s) on the canvas | What changes |
|---|---|---|---|
| A  Provider Services (list) | UPDATE | "A · Provider Services (Individual)" and "(Company)" | Status pills become Active / Inactive / Pending Review / Rejected. No "Self-declared" label anywhere. Notes only where useful ("No proof required", "Proof can be added later", "Proof required before it goes live" + Upload documents). Cards show identity ("· Company", "· Individual", "· Personal profile"). Companies get a "Company verification" strip. Filter chips and the Add Service button stay. New entry to the switch flow ("Manage identity", see section 4). |
| B  Choose Category | KEEP | none (not redrawn) | Unchanged, including the green count badge. Only the next step changes: tapping a category opens B2 if that category has no identity yet, otherwise goes straight to C or D for its saved identity. |
| (new) B2  Who is offering? | NEW | "B2 · Who is offering?" and "B2 · Company selected" | Always the next screen after choosing a category. Merges the old S3: Individual or Company, plus how the provider is shown (display name / company name / representative). A saved identity is preselected and tagged "Current". Saved per category. |
| C  Category: services, jobs toggle off | REPLACE | "C · Individual: roles" and "D · Company: services + roles" | The "Available for jobs" toggle is removed. The identity decides the screen: Individual sees only "What roles do you do?"; Company sees "What we offer" and "What roles do you do?". |
| D  Category: jobs on, role cards | REPLACE (merged) | same two screens | The role cards move into C (Individual) and the roles section of D (Company). The collapsed "What I offer" row is dropped. |
| E  Pick your kind | UPDATE | "E · Individual: pick your kind" | Individual path only. Note text updated. Company roles skip it (added later from the Job card). |
| F  Qualifications and proof | UPDATE | "F · Individual: qualifications and proof" | Individual path only. Proof statuses follow the verification policy; no "Self-declared". |
| G  Tap a card: status and details | UPDATE | "G · Service card details" | Shows policy state (Active / Inactive / Pending / Rejected), rejection reason, what is needed, Resubmit or Upload documents, and an "Offering as … Change" row that opens the switch flow. |
| (new) Company details | NEW | "Company details and verification" | Company step 2: name, registration number, team size, years, areas, optional company verification uploads. Name it `CompanyDetailsStep` in code (the repo already uses "sheet G" for card details). |
| (new) Switch identity | NEW | "S1 · Provider Services + Choose Category" (existing, unchanged), "S2 · confirm", "S4 · review" (S3 is merged into B2) | Per-category identity switching, atomic and confirmed. |

## 2. Flows in the order the user sees them
1. **First time, Individual:** A -> Add Service -> B -> B2 (Individual) -> C (roles, STEP 1 OF 3) -> E (kind, STEP 2 OF 3) -> F (qualifications, STEP 3 OF 3) -> Save work profile -> A.
2. **First time, Company:** A -> Add Service -> B -> B2 (Company) -> D (services + roles, STEP 1 OF 2) -> Company details (STEP 2 OF 2) -> Save company profile -> A.
3. **Returning to a category that already has an identity:** A -> Add Service -> B -> straight to C or D (no B2); the "Offering as … Change" pill opens the switch flow.
4. **Review or fix one service:** A -> tap card -> G (status, reason, upload or resubmit).
5. **Category already has an identity:** A -> S1 (Choose Category) -> B2 (saved identity preselected, "Current"). Keep it: continue to C or D. Pick the other identity (and set how it is shown): S2 confirm -> S4 review -> Confirm switch -> A.

## 3. Build order (each stage ends with: analyze, tests, SQL checks, Home baseline diff, tracker update)
| Stage | Build | Screens touched | Prompt | Depends on | Done when |
|---|---|---|---|---|---|
| 1 | Verification policy: open / optional_proof / required_proof per capability, backend enforcement (inactive until approved, no offers), company verification record, basic admin queue | A (statuses), G (policy, reason, resubmit), remove "Self-declared" | `VERIFICATION_SPEC.md` + section 11 of `PROVIDER_TYPE_STEP_PROMPT.md` | existing capabilities | required-proof capabilities cannot go live or get offers without approval; cards and G show correct states |
| 2 | Identity per category + the C/D split | B2 (new), C (Individual), D shell for Company, E and F kept for Individual | `PROVIDER_TYPE_STEP_PROMPT.md` sections 1 to 10 | stage 1 (statuses on cards) | B -> B2 -> C -> E -> F -> A works for Individual; type saved per category; flag off = today's behaviour |
| 3 | Company path | D (services + roles), Company details, A for companies | `COMPANY_PATH_BUILD_PROMPT.md` | stage 2 (saved type), stage 1 (verification) | B -> B2 -> D -> Company details -> A saves services, roles and details atomically |
| 4 | Identity switching | S1 to S4, "Change" pills, G identity row | `IDENTITY_SWITCH_BUILD_PROMPT.md` | stages 1 to 3 | one active identity per category (server enforced), previous identity inactive but kept, verification never transfers |

Why this order: stage 1 is small and every later card depends on its states; stage 2 creates the saved per-category identity that stages 3 and 4 read; stage 4 needs the company data from stage 3 and the verification rules from stage 1. Stages 1 and 2 can ship together; ship 3 and 4 separately behind the flag.

## 4. Decisions this map settles (confirm in the inspection step)
- **B2 is always shown after choosing a category.** The saved identity is preselected. Changing it triggers S2 then S4; keeping it goes straight on.
- **S1 is your existing Provider Services page with the Choose Category sheet, unchanged.** No new category list or navigation.
- **Naming.** `CompanyDetailsStep` for the new step; "sheet G" stays the card-details screen.
- **Roles are personal.** Job roles are never deactivated or re-labelled by an identity switch.
- **Home stays untouched** in every stage.

## 5. Master prompt to give the coding agent
> You are a senior Flutter + Supabase engineer in the Nipanze repo. Read `.agents/AGENTS.md` first and follow it. Then read `BUILD_PLAN.md`, `README.md`, `PROVIDER_FLOW_BUILD_ORDER.md`, `VERIFICATION_SPEC.md`, `PROVIDER_TYPE_STEP_PROMPT.md`, `COMPANY_PATH_BUILD_PROMPT.md`, `IDENTITY_SWITCH_SPEC.md`, `IDENTITY_SWITCH_BUILD_PROMPT.md` and the SQL in `sql/`. The Provider Services screens A to G already exist in the app. Do NOT rebuild them: follow the screen map (section 1) to update, replace or add only what it says, and keep screen B as is.
>
> Work in the four stages of section 3, strictly in order. Before stage 1, inspect the repo and Supabase schema and report: what exists, what is reusable, conflicts, a file-by-file plan, risks and open questions, then wait for my OK. After each stage, stop and report: files changed, SQL patch added, rules implemented, tests run with results, Home baseline diff result, and how I can try it. Do not start the next stage until I approve.
>
> Hard rules for every stage: Home and the Marketplace feed must not change (additive only for views and RPCs); everything behind `capability_profiles_enabled` (default off); SQL only as standalone, descriptively named, re-runnable patches (never modify `sql/patch.sql` or `sql/merged.sql`); RLS on every new table, no anon grants, private storage for documents; per-capability verification never transfers between capabilities or identities; non-custodial, Loans and Forex unchanged; no new dependencies without a one-line reason; update `BUILD_PLAN.md` and its trackers in the same commit as each stage; never run anything against production without my explicit approval.
