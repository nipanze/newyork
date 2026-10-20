# Nipanze: Simple Provider and Capability Verification System

## Objective

Implement a simple, affordable verification system for Nipanze that allows us to launch quickly while reducing scams and misleading service claims.

**Important:** Nipanze is a startup with a limited budget. Do not build an expensive, complicated verification system. Use the existing architecture and database wherever possible. We will introduce more advanced verification features gradually as the business grows.

## 1. Company Verification

For company accounts, allow the company to upload either:

- A business registration certificate.
- Relevant business licences or authorization documents.

Requirements:
- Allow companies to submit available documents for manual admin review.
- Provide statuses: `Not Submitted`, `Pending Review`, `Verified`, and `Rejected`.
- Allow the admin to approve or reject submissions and provide a rejection reason.
- Store documents securely so only authorized administrators can access them.
- Do not integrate paid verification APIs or external registries at this stage.
- A general business registration certificate must not automatically authorize a company to provide every regulated service.

## 2. Individual Provider Verification

For individuals, verification must be handled **per capability/service**, not just once for the entire account.

A provider may offer several capabilities, and each capability must follow its own verification policy.

Implement three configurable policies:

### A. Open — No Proof Required

Examples: ordinary capabilities that do not require special authorization under the applicable rules.

- Allow the provider to activate the capability immediately.
- Do not require document uploads.
- Do not display a “Self-declared” label.
- Do not display a verified badge unless the capability has actually been verified.

### B. Optional Proof — Self-Declared and Active

Example: Cybersecurity, where Nipanze allows the provider to begin with a self-declared capability.

- Allow the provider to activate the capability without submitting evidence.
- The capability can be active and eligible to receive offers according to Nipanze's normal rules.
- Do not publicly display a “Self-declared” badge.
- Provide an option to upload supporting documents later.
- After the admin approves the evidence, display the verified badge for that specific capability.
- If proof is pending, keep the capability active where policy permits, but do not display the verified badge.

### C. Required Proof — Inactive Until Approved

Examples may include visa-related services, architecture, or engineering, depending on the specific service and applicable legal requirements.

- Require supporting documents before activating the capability.
- Keep the capability inactive while proof is missing or under review.
- Do not allow the provider to make offers or advertise the restricted capability while it is inactive.
- Allow the provider to upload the required documents.
- After admin approval, activate the capability and display its verified badge.
- If rejected, show the rejection reason and allow the provider to submit corrected documents.

**Important:** Configure the policy for each individual capability. Do not assume that every service within a broad category has the same verification requirements. Where a licence or legal authorization is mandatory, proof must be approved before the service becomes active.

## 3. Provider Dashboard / My Services

Create or update the provider's capability-management screen.

For each capability, show:
- Capability name.
- Current status: Active, Inactive, Pending Review, or Rejected.
- Whether proof is required or optional, where useful.
- An upload-document action when applicable.
- A verified badge only after approval.
- The rejection reason when applicable.

Example:

- **Cybersecurity** — Active; proof can be added later.
- **Graphic Design** — Active; no proof required.
- **Architecture** — Inactive; proof required.
- **Visa Services** — Inactive; required documents awaiting approval.

Keep the interface clean and professional. Do not add unnecessary labels, complicated onboarding steps, or excessive forms.

## 4. Admin Dashboard

Implement a basic manual review queue where an administrator can:

- View pending company verification submissions.
- View pending individual capability submissions.
- Open submitted documents securely.
- Approve or reject submissions.
- Enter a rejection reason.
- See which company or provider and capability each submission belongs to.
- Record who reviewed the submission and when.

Do not introduce automated document verification, paid APIs, or complex compliance workflows at this stage.

## 5. Database and Security

First inspect the existing database schema, migrations, verification logic, and provider capability implementation. Reuse and extend what already exists instead of creating duplicate systems.

The existing Nipanze project may already have a `provider_capabilities` table with fields such as `verification_level`, `evidence_url`, `verified_by`, and `verified_at`. Check the actual implementation before making changes.

Ensure the system can represent:

- The verification policy for each capability: `open`, `optional_proof`, or `required_proof`.
- Whether the provider's capability is active.
- The verification status of the capability.
- The location of submitted evidence.
- The reviewing administrator and verification timestamp.
- Company verification status separately from individual capability verification.

Use the project's existing conventions where possible. Add only the database fields and migrations genuinely required.

Security requirements:
- Store verification documents in private storage.
- Prevent unauthorized users from viewing verification documents.
- Enforce required-proof restrictions on the backend, not only in the user interface.
- Only authorized administrators can approve or reject verification.
- Providers must not be able to grant themselves a verified status or activate a capability that requires approval.
- Do not expose private document URLs or sensitive verification details publicly.

Create a new, descriptive, standalone SQL migration or patch for schema changes. **Do not modify the monolithic `patch.sql`** for schema, function, or policy updates.

## 6. Preserve Nipanze's Existing Business Model

- Nipanze is a non-custodial marketplace. Do not introduce payment holding, lending transactions, or unrelated financial functionality.
- Keep the current Loans and Forex launch scope intact.
- Make capability verification reusable for future Needs and service-provider categories.
- Keep the existing technology stack and architecture.
- Do not rebuild unrelated screens or introduce unnecessary dependencies.

## 7. Required Implementation Process

1. Inspect the existing README, BUILD_PLAN, database schema, migrations, provider capability screens, admin dashboard, and relevant security policies.
2. Explain briefly what already exists and what actually needs changing.
3. Implement the smallest complete solution that fits the current architecture.
4. Add or update the database migration, backend enforcement, provider interface, and admin review queue as necessary.
5. Test all three policies: open, optional proof, and required proof.
6. Test approval, rejection, resubmission, and unauthorized access.
7. Ensure required-proof capabilities cannot receive offers before approval.
8. Update the README and BUILD_PLAN to document the implementation and any remaining limitations.

Do not stop after writing a plan if the codebase is available and implementation is possible. Make the changes, run the relevant tests, and report what was completed and what still needs attention.

## Final Principle

**Keep Nipanze simple enough to launch now, safe enough to discourage obvious scams, and flexible enough to improve verification gradually as the company grows.** Do not overengineer the startup or delay launch with expensive verification systems.