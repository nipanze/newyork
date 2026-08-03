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

export interface Profile {
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
}

export interface Subscription {
  id: string;
  user_id: string;
  plan: SubscriptionPlan;
  status: SubscriptionStatus;
  started_at: string;
  expires_at: string | null;
  amount_minor_units: number;
  auto_renew: boolean;
}

export interface KycVerification {
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
}

export interface Country {
  code: string;
  name: string;
  currency_code: string;
  phone_prefix: string;
  is_active: boolean;
  /** v6.0 field — present once the forex migration has run. */
  forex_enabled?: boolean;
}

export interface LoanRequest {
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
}

export interface LoanOffer {
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
}

export interface Transaction {
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
}

export interface AuditLog {
  id: string;
  user_id: string | null;
  event_type: string;
  entity_type: string | null;
  entity_id: string | null;
  action: string | null;
  description: string | null;
  ip_address: string | null;
  created_at: string;
}

export interface SystemSetting {
  setting_id: string;
  setting_key: string;
  country: string | null;
  setting_value: string | null;
  setting_type: "string" | "number" | "boolean" | "json";
  category: string | null;
  description: string | null;
  is_public: boolean;
}

export interface TrustProfilePublic {
  user_id: string;
  rating_avg: number | null;
  review_count: number;
  completed_deals_count: number;
  is_repeat_participant: boolean;
  phone_verified: boolean;
  response_time_bucket: string | null;
  is_verified: boolean;
}

// Minimal Supabase Database generic — enough for the typed client without
// hand-maintaining every Row/Insert/Update permutation. Swap for the
// generated types (see comment above) when you want full type safety on
// inserts/updates too.
export type Database = {
  public: {
    Tables: {
      profiles: { Row: Profile; Insert: Partial<Profile>; Update: Partial<Profile> };
      subscriptions: { Row: Subscription; Insert: Partial<Subscription>; Update: Partial<Subscription> };
      kyc_verifications: { Row: KycVerification; Insert: Partial<KycVerification>; Update: Partial<KycVerification> };
      countries: { Row: Country; Insert: Partial<Country>; Update: Partial<Country> };
      loan_requests: { Row: LoanRequest; Insert: Partial<LoanRequest>; Update: Partial<LoanRequest> };
      loan_offers: { Row: LoanOffer; Insert: Partial<LoanOffer>; Update: Partial<LoanOffer> };
      transactions: { Row: Transaction; Insert: Partial<Transaction>; Update: Partial<Transaction> };
      audit_logs: { Row: AuditLog; Insert: Partial<AuditLog>; Update: Partial<AuditLog> };
      system_settings: { Row: SystemSetting; Insert: Partial<SystemSetting>; Update: Partial<SystemSetting> };
    };
    Views: {
      v_trust_profile_public: { Row: TrustProfilePublic };
    };
  };
};
