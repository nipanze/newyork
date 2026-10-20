/**
 * Hand-written subset of the Supabase schema (see /sql/schema.sql in the
 * Flutter project) covering the tables and views this dashboard reads or
 * writes. Not exhaustive — extend as admin features grow. If you'd rather
 * generate this from the live database instead of maintaining it by hand:
 *
 *   npx supabase gen types typescript --project-id <ref> > lib/types.ts
 */

export type AccountStatus = "active" | "suspended" | "pending_verification" | "deactivated";
export type KycStatus = "not_submitted" | "pending" | "approved" | "rejected" | "expired";
export type SubscriptionPlan = "free" | "lender" | "pro";
export type SubscriptionStatus = "active" | "expired" | "cancelled" | "grace_period";
export type LoanStatus = "active" | "contracted" | "expired" | "cancelled";
export type OfferStatus = "pending" | "accepted" | "rejected" | "withdrawn" | "expired";
export type TransactionStatus = "pending" | "successful" | "failed" | "reversed";
export type MarketerStatus = "new" | "active" | "suspended" | "deactivated" | "under_review";
export type ReferralStatus = "clicked" | "registered" | "verified" | "qualified" | "rejected" | "fraud_hold";
export type ReferralRewardStatus = "pending" | "approved" | "rejected" | "paid" | "cancelled" | "fraud_hold";
export type ReferralPayoutStatus =
  | "requested"
  | "under_review"
  | "approved"
  | "processing"
  | "paid"
  | "failed"
  | "cancelled";
export type ReferralCampaignStatus = "draft" | "active" | "paused" | "ended" | "deactivated";

export type VerificationPolicy = "open" | "optional_proof" | "required_proof";
export type EvidenceStatus = "pending" | "approved" | "rejected" | "expired";
export type CompanyDocStatus = "pending" | "approved" | "rejected";
export type ProviderType = "individual" | "company" | "both";
export type CapabilityType = "service" | "role";
export type NeedRequestStatus = "active" | "matched" | "completed" | "expired" | "cancelled";
export type NeedOfferStatus = "pending" | "accepted" | "rejected" | "withdrawn" | "expired";

export type Profile = {
  id: string;
  full_name: string | null;
  phone: string | null;
  phone_verified_at: string | null;
  country: string;
  district: string | null;
  employment_type: string | null;
  employer_name: string | null;
  monthly_income: number | null;
  income_currency: string;
  account_status: AccountStatus;
  is_admin: boolean;
  free_unlocks_remaining: number;
  created_at: string;
  updated_at: string;
};

export type Subscription = {
  id: string;
  user_id: string;
  plan: SubscriptionPlan;
  status: SubscriptionStatus;
  started_at: string;
  expires_at: string | null;
  amount_minor_units: number;
  auto_renew: boolean;
};

export type KycVerification = {
  id: string;
  user_id: string;
  status: KycStatus;
  national_id_type: string | null;
  national_id_number: string | null;
  national_id_front_url: string | null;
  national_id_back_url: string | null;
  selfie_url: string | null;
  id_verified: boolean;
  selfie_verified: boolean;
  verified_by: string | null;
  rejection_reason: string | null;
  verification_notes: string | null;
  submitted_at: string | null;
  reviewed_at: string | null;
  expires_at: string | null;
};

export type Country = {
  code: string;
  name: string;
  currency_code: string;
  phone_prefix: string;
  is_active: boolean;
  /** v6.0 field — present once the forex migration has run. */
  forex_enabled?: boolean;
};

export type SubscriptionPrice = {
  id: string;
  country_code: string;
  currency_code: string;
  plan: "lender" | "pro";
  price_amount: number;
  price_minor_units: number;
  created_at?: string;
  updated_at?: string;
};

export type LoanRequest = {
  id: string;
  borrower_id: string;
  country: string;
  title: string;
  purpose: string;
  requested_amount: number;
  duration_months: number;
  preferred_repayment_plan: string;
  repayment_amount_per_period: number;
  repayment_timeline: string;
  district: string;
  number_of_offers: number;
  status: LoanStatus;
  listed_at: string;
  expires_at: string | null;
  contracted_at: string | null;
  suggested_interest_rate_pct: number | null;
};

export type LoanOffer = {
  id: string;
  request_id: string;
  lender_id: string;
  offer_amount: number;
  interest_rate_pct: number;
  late_fee_pct: number;
  repayment_frequency: string;
  installment_amount: number;
  status: OfferStatus;
  offered_at: string;
  accepted_at: string | null;
};

export type Transaction = {
  id: string;
  user_id: string;
  type: "subscription" | "contact_unlock";
  amount: number;
  currency_code: string;
  country: string;
  provider: string;
  provider_tx_ref: string;
  provider_tx_id: string | null;
  status: TransactionStatus;
  webhook_verified_at: string | null;
  created_at: string;
};

export type AuditLog = {
  id: string;
  user_id: string | null;
  event_type: string;
  entity_type: string | null;
  entity_id: string | null;
  action: string | null;
  description: string | null;
  previous_values?: Record<string, unknown> | null;
  new_values?: Record<string, unknown> | null;
  ip_address?: string | null;
  created_at: string;
};

export type SystemSetting = {
  setting_id: string;
  setting_key: string;
  country: string | null;
  setting_value: string | null;
  setting_type: "string" | "number" | "boolean" | "json";
  category: string | null;
  description: string | null;
  is_public: boolean;
};

export type ReferralMarketer = {
  id: string;
  profile_id: string;
  referral_code: string;
  status: MarketerStatus;
  default_campaign_id: string | null;
  joined_at: string;
  last_activity_at: string | null;
  risk_status: "clear" | "review" | "flagged";
  risk_reason: string | null;
  created_at: string;
  updated_at: string;
};

export type ReferralCampaign = {
  id: string;
  name: string;
  description: string | null;
  country: string | null;
  start_date: string | null;
  end_date: string | null;
  status: ReferralCampaignStatus;
  qualification_event: string;
  reward_type: "fixed" | "tiered" | "manual";
  reward_amount: number;
  reward_currency: string;
  campaign_budget: number | null;
  max_referrals: number | null;
  eligible_plans: string[];
  terms: string | null;
  created_at: string;
  updated_at: string;
};

export type ReferralReward = {
  id: string;
  marketer_id: string;
  referral_id: string | null;
  campaign_id: string | null;
  referred_user_id: string | null;
  reward_type: string;
  amount: number;
  currency: string;
  status: ReferralRewardStatus;
  reason: string | null;
  approved_at: string | null;
  rejected_at: string | null;
  paid_at: string | null;
  created_at: string;
  updated_at: string;
};

export type ReferralPayout = {
  id: string;
  marketer_id: string;
  amount: number;
  currency: string;
  payout_method: string | null;
  payout_destination_ref: string | null;
  status: ReferralPayoutStatus;
  failure_reason: string | null;
  requested_at: string;
  approved_at: string | null;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type TrustProfilePublic = {
  user_id: string;
  rating_avg: number | null;
  review_count: number;
  completed_deals_count: number;
  is_repeat_participant: boolean;
  phone_verified: boolean;
  response_time_bucket: string | null;
  is_verified: boolean;
};

export type NeedCategory = {
  slug: string;
  name: string;
  icon: string;
  sort_order: number;
  is_active: boolean;
  created_at: string;
};

export type NeedCapability = {
  slug: string;
  category_slug: string;
  name: string;
  is_active: boolean;
  verification_policy: VerificationPolicy;
  capability_type?: CapabilityType;
  created_at: string;
};

export type ProviderCapability = {
  id: string;
  user_id: string;
  capability_slug: string;
  verification_level: "self_declared" | "provider_verified";
  is_active: boolean;
  identity_type?: "individual" | "company" | null;
  evidence_url?: string | null;
  verified_by?: string | null;
  verified_at?: string | null;
  metadata?: Record<string, unknown> | null;
  created_at: string;
};

export type ProviderCategoryProfile = {
  user_id: string;
  category_slug: string;
  provider_type: "individual" | "company";
  identity_changed_at?: string | null;
  created_at: string;
  updated_at: string;
};

export type ProviderCompanyProfile = {
  user_id: string;
  category_slug: string;
  company_name: string | null;
  registration_number: string | null;
  team_size: "1-5" | "6-20" | "21-50" | "50+" | null;
  years_in_business: "<1" | "1-2" | "3-5" | "6-10" | "10+" | null;
  service_areas: string[];
  created_at: string;
  updated_at: string;
};

export type ProviderIdentityPresentation = {
  user_id: string;
  category_slug: string;
  identity_type: "individual" | "company";
  display_mode: "personal" | "company" | "company_with_representative";
  display_name: string | null;
  representative_name: string | null;
  status: "draft" | "active" | "inactive";
  created_at: string;
  updated_at: string;
};

export type ProviderCapabilityEvidence = {
  id: string;
  provider_capability_id: string;
  requirement_key: string;
  file_url: string;
  status: EvidenceStatus;
  provider_type?: ProviderType;
  reject_reason: string | null;
  expires_at: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type ProviderCompanyVerificationSubmission = {
  user_id: string;
  category_slug: string;
  document_type: "business_registration" | "business_licence";
  file_path: string;
  status: CompanyDocStatus;
  reject_reason: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type ProviderRoleQualificationClaim = {
  id: string;
  provider_capability_id: string;
  claim_key: string;
  evidence_url?: string | null;
  status: EvidenceStatus;
  reject_reason?: string | null;
  reviewed_by?: string | null;
  reviewed_at?: string | null;
  expires_at?: string | null;
  created_at: string;
  updated_at: string;
};

export type VerificationRequirement = {
  id?: string;
  scope_type: "capability" | "category";
  scope_id: string;
  provider_type: ProviderType;
  identity_required: boolean;
  phone_required: boolean;
  provider_verification_required: boolean;
  evidence_requirements: string[];
  required_evidence: string[];
  expires_after_days: number | null;
  is_active: boolean;
};

export type NeedRequest = {
  request_id: string;
  title: string;
  specification: string;
  category: string;
  category_slug?: string;
  budget: number;
  currency: string;
  location: string;
  country: string;
  urgency: string;
  status: NeedRequestStatus;
  listed_at: string;
  created_at: string;
  trust_is_verified: boolean;
};

export type NeedOffer = {
  id: string;
  need_id: string;
  offer_maker_id: string;
  price: number;
  currency: string;
  timeline_text: string;
  message: string;
  terms_locked_at: string | null;
  status: NeedOfferStatus;
  offered_at: string;
  accepted_at: string | null;
  withdrawn_at: string | null;
  expires_at: string | null;
  provider_identity_type?: "individual" | "company" | null;
  provider_display_name?: string | null;
  created_at: string;
  updated_at: string;
};

export type NeedContactReveal = {
  id: string;
  need_id: string;
  offer_id: string;
  requester_id: string;
  provider_id: string;
  unlocked_by: string;
  unlocked_at: string;
};

export type Database = any;
