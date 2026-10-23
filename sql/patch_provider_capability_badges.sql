-- Complete the provider badge for the capability whose role evidence an admin
-- approves. Existing approved evidence on the same capability keeps its badge
-- if another item is rejected or expires. Safe to rerun.

begin;

create or replace function public.admin_review_provider_role_qualification(
  p_claim_id uuid,
  p_action text,
  p_reject_reason text default null,
  p_expires_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_admin uuid := auth.uid();
  v_claim record;
begin
  if not private.is_admin() then
    raise exception 'Unauthorized: Admin access required.' using errcode = '42501';
  end if;
  if p_action not in ('approve', 'reject', 'expire') then
    raise exception 'Action must be approve, reject, or expire.' using errcode = '22023';
  end if;

  select claim.*, pc.capability_slug, pc.user_id
  into v_claim
  from public.provider_role_qualification_claims claim
  join public.provider_capabilities pc on pc.id = claim.provider_capability_id
  where claim.id = p_claim_id
  for update of claim;

  if not found then
    raise exception 'Provider role qualification claim not found.' using errcode = 'P0212';
  end if;
  if p_action = 'approve' and v_claim.status <> 'pending_review' then
    raise exception 'Only submitted qualification evidence can be approved.' using errcode = '22023';
  end if;
  if p_action = 'approve' and p_expires_at is not null and p_expires_at <= now() then
    raise exception 'Evidence expiry must be in the future.' using errcode = '22023';
  end if;

  update public.provider_role_qualification_claims
  set status = case
        when p_action = 'approve' then 'verified'
        when p_action = 'reject' then 'rejected'
        else 'expired'
      end,
      reject_reason = case when p_action = 'reject' then coalesce(p_reject_reason, '') else null end,
      expires_at = case when p_action = 'approve' then p_expires_at else expires_at end,
      reviewed_by = v_admin,
      reviewed_at = now(),
      updated_at = now()
  where id = p_claim_id;

  -- The approval belongs to this exact provider capability, not the whole
  -- account or category, so only that capability receives the badge.
  if p_action = 'approve' then
    update public.provider_capabilities
    set verification_level = 'provider_verified',
        verified_by = v_admin,
        verified_at = now()
    where id = v_claim.provider_capability_id;
  elsif not exists (
    select 1
    from public.provider_role_qualification_claims claim
    where claim.provider_capability_id = v_claim.provider_capability_id
      and claim.is_claimed
      and claim.status = 'verified'
      and (claim.expires_at is null or claim.expires_at > now())
  ) and not exists (
    select 1
    from public.provider_capability_evidence evidence
    where evidence.provider_capability_id = v_claim.provider_capability_id
      and evidence.status = 'approved'
      and (evidence.expires_at is null or evidence.expires_at > now())
  ) then
    update public.provider_capabilities
    set verification_level = 'self_declared',
        verified_by = null,
        verified_at = null
    where id = v_claim.provider_capability_id;
  end if;

  insert into public.audit_logs
    (user_id, event_type, entity_type, entity_id, action, new_values)
  values
    (v_admin, 'admin_action', 'provider_role_qualification_claim', p_claim_id,
     'review_provider_role_qualification',
     jsonb_build_object(
       'action', p_action,
       'provider_capability_id', v_claim.provider_capability_id,
       'capability_slug', v_claim.capability_slug,
       'role_slug', v_claim.role_slug,
       'qualification_slug', v_claim.qualification_slug,
       'reject_reason', p_reject_reason,
       'expires_at', p_expires_at
     ));

  return true;
end;
$$;

revoke all on function public.admin_review_provider_role_qualification(uuid, text, text, timestamptz)
  from public, anon;
grant execute on function public.admin_review_provider_role_qualification(uuid, text, text, timestamptz)
  to authenticated;

-- Also keep badges synchronized for capability-level proof approvals. This
-- preserves the badge while any approved, unexpired proof remains on the same
-- capability, then clears it once none remain.
create or replace function private.sync_provider_capability_badge_from_approved_evidence()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_reviewer uuid;
  v_reviewed_at timestamptz;
begin
  if exists (
    select 1
    from public.provider_capability_evidence evidence
    where evidence.provider_capability_id = new.provider_capability_id
      and evidence.status = 'approved'
      and (evidence.expires_at is null or evidence.expires_at > now())
    union all
    select 1
    from public.provider_role_qualification_claims claim
    where claim.provider_capability_id = new.provider_capability_id
      and claim.is_claimed
      and claim.status = 'verified'
      and (claim.expires_at is null or claim.expires_at > now())
  ) then
    select approved.reviewer, approved.reviewed_at
    into v_reviewer, v_reviewed_at
    from (
      select evidence.reviewed_by as reviewer, evidence.reviewed_at
      from public.provider_capability_evidence evidence
      where evidence.provider_capability_id = new.provider_capability_id
        and evidence.status = 'approved'
        and (evidence.expires_at is null or evidence.expires_at > now())
      union all
      select claim.reviewed_by as reviewer, claim.reviewed_at
      from public.provider_role_qualification_claims claim
      where claim.provider_capability_id = new.provider_capability_id
        and claim.is_claimed
        and claim.status = 'verified'
        and (claim.expires_at is null or claim.expires_at > now())
    ) approved
    order by approved.reviewed_at desc nulls last
    limit 1;

    update public.provider_capabilities
    set verification_level = 'provider_verified',
        verified_by = coalesce(v_reviewer, new.reviewed_by, auth.uid()),
        verified_at = coalesce(v_reviewed_at, new.reviewed_at, now())
    where id = new.provider_capability_id;
  else
    update public.provider_capabilities
    set verification_level = 'self_declared',
        verified_by = null,
        verified_at = null
    where id = new.provider_capability_id
      and verification_level = 'provider_verified';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_provider_capability_badge_from_approved_evidence
  on public.provider_capability_evidence;
create trigger trg_sync_provider_capability_badge_from_approved_evidence
  after insert or update of status, expires_at
  on public.provider_capability_evidence
  for each row
  execute function private.sync_provider_capability_badge_from_approved_evidence();

-- Backfill approved proofs reviewed before this patch is installed.
with approvals as (
  select evidence.provider_capability_id, evidence.reviewed_by, evidence.reviewed_at
  from public.provider_capability_evidence evidence
  where evidence.status = 'approved'
    and (evidence.expires_at is null or evidence.expires_at > now())
  union all
  select claim.provider_capability_id, claim.reviewed_by, claim.reviewed_at
  from public.provider_role_qualification_claims claim
  where claim.is_claimed and claim.status = 'verified'
    and (claim.expires_at is null or claim.expires_at > now())
), latest_approval as (
  select distinct on (provider_capability_id)
    provider_capability_id, reviewed_by, reviewed_at
  from approvals
  order by provider_capability_id, reviewed_at desc nulls last
)
update public.provider_capabilities capability
set verification_level = 'provider_verified',
    verified_by = latest_approval.reviewed_by,
    verified_at = coalesce(latest_approval.reviewed_at, now())
from latest_approval
where capability.id = latest_approval.provider_capability_id;

commit;
