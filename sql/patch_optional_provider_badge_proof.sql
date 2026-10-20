-- Let providers voluntarily submit a supporting document for a badge, even
-- where proof is not needed to keep an open capability active. Admin approval
-- remains the only way this evidence can award provider_verified.
-- Apply after provider capability evidence, verification policy, and provider
-- type verification matrix patches. Safe to rerun; never changes open/required
-- activation policy or adds proof requirements to offering services.
begin;

insert into public.verification_requirements (
  scope_type,
  scope_id,
  provider_type,
  identity_required,
  phone_required,
  provider_verification_required,
  evidence_requirements,
  required_evidence,
  expires_after_days,
  is_active
)
select
  'capability',
  nc.slug,
  'both',
  false,
  false,
  false,
  jsonb_build_array('supporting_document'),
  array[]::text[],
  null,
  true
from public.need_capabilities nc
where nc.is_active
  and nc.verification_policy = 'open'
on conflict (scope_type, scope_id, provider_type) do nothing;

commit;

-- Existing open capabilities remain active. Only admin-approved submissions
-- receive provider_verified; rejected or pending documents do not change access.
