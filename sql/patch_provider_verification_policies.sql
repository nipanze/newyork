-- Configurable per-capability verification policies and separate company
-- document review. Apply after provider capability and evidence patches.
-- Safe to rerun; does not modify public listing or feed view signatures.
begin;

alter table public.need_capabilities
  add column if not exists verification_policy text not null default 'open';
alter table public.need_capabilities
  drop constraint if exists need_capabilities_verification_policy_check;
alter table public.need_capabilities
  add constraint need_capabilities_verification_policy_check
  check (verification_policy in ('open', 'optional_proof', 'required_proof'));

alter table public.provider_capabilities
  add column if not exists is_active boolean not null default true;
create index if not exists idx_provider_capabilities_active_slug
  on public.provider_capabilities(capability_slug, is_active);

create or replace function private.validate_provider_capability_evidence_object()
returns trigger language plpgsql security definer
set search_path = public, private, storage, pg_temp as $$
declare
  v_user uuid;
  v_slug text;
  v_owner text;
  v_size bigint;
  v_mime text;
begin
  select pc.user_id, pc.capability_slug into v_user, v_slug
  from public.provider_capabilities pc
  where pc.id = new.provider_capability_id;
  if not found then raise exception 'Provider capability not found.' using errcode = 'P0212'; end if;
  if new.file_url not like 'evidence/' || v_user::text || '/' || v_slug || '/%' then
    raise exception 'Evidence must use the provider capability folder.' using errcode = 'P0205';
  end if;
  select o.owner_id, (o.metadata->>'size')::bigint,
         lower(coalesce(o.metadata->>'mimetype', ''))
    into v_owner, v_size, v_mime
  from storage.objects o
  where o.bucket_id = 'provider-evidence' and o.name = new.file_url;
  if not found or v_owner is distinct from v_user::text then
    raise exception 'Evidence file is not owned by the capability provider.' using errcode = 'P0205';
  end if;
  if v_size is null or v_size < 1 or v_size > 5242880
     or v_mime not in ('image/jpeg', 'image/png', 'application/pdf') then
    raise exception 'Evidence must be JPG, PNG, or PDF and no larger than 5 MB.' using errcode = 'P0205';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_validate_provider_capability_evidence_object
  on public.provider_capability_evidence;
create trigger trg_validate_provider_capability_evidence_object
  before insert or update of file_url, provider_capability_id
  on public.provider_capability_evidence
  for each row execute function private.validate_provider_capability_evidence_object();

-- Keep the initial matrix limited to individual capabilities where proof is
-- legally or operationally significant. Administrators may tune it later.
update public.need_capabilities
set verification_policy = 'required_proof'
where slug in (
  'legal_services', 'company_registration', 'accounting_tax',
  'architecture_services', 'architecture', 'engineering_consulting',
  'engineering', 'surveying', 'electrical_works', 'electrical_installation',
  'solar_systems', 'building_contractors', 'heavy_haulage', 'cargo_transport',
  'truck_hire', 'event_transport', 'driving_school_driver_training',
  'excavator_hire', 'loader_hire', 'grader_hire', 'crane_hire',
  'visa_assistance', 'hajj_umrah', 'seeds_inputs', 'catering'
) and verification_policy = 'open';
update public.need_capabilities
set verification_policy = 'optional_proof'
where slug in ('cybersecurity_services', 'cybersecurity')
  and verification_policy = 'open';

-- Ensure every configured policy has an upload key for the canonical catalog
-- slug, even where older verification rows use an alias.
insert into public.verification_requirements (
  scope_type, scope_id, provider_type, identity_required, phone_required,
  provider_verification_required, evidence_requirements, required_evidence,
  expires_after_days, is_active
)
select 'capability', nc.slug, 'both', true, false, true,
       jsonb_build_array(nc.slug || '_authorization'),
       array[nc.slug || '_authorization'], 365, true
from public.need_capabilities nc
where nc.verification_policy = 'required_proof'
  and not exists (
    select 1 from public.verification_requirements r
    where r.scope_type = 'capability' and r.scope_id = nc.slug and r.is_active
      and r.provider_type in ('both', 'individual', 'company')
  )
on conflict (scope_type, scope_id, provider_type) do nothing;

insert into public.verification_requirements (
  scope_type, scope_id, provider_type, identity_required, phone_required,
  provider_verification_required, evidence_requirements, required_evidence,
  expires_after_days, is_active
)
select 'capability', nc.slug, 'both', false, false, false,
       jsonb_build_array('security_certification_or_portfolio'),
       array[]::text[], null, true
from public.need_capabilities nc
where nc.verification_policy = 'optional_proof'
  and not exists (
    select 1 from public.verification_requirements r
    where r.scope_type = 'capability' and r.scope_id = nc.slug and r.is_active
      and r.provider_type in ('both', 'individual', 'company')
  )
on conflict (scope_type, scope_id, provider_type) do nothing;

-- Existing declarations in newly restricted capabilities remain saved, but
-- cannot be used until their per-capability evidence is approved.
update public.provider_capabilities pc
set is_active = false
from public.need_capabilities nc
where nc.slug = pc.capability_slug
  and nc.verification_policy = 'required_proof'
  and pc.verification_level <> 'provider_verified';

create table if not exists public.provider_company_verification_submissions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_slug text not null references public.need_categories(slug) on delete cascade,
  document_type text not null check (document_type in ('business_registration', 'business_licence')),
  file_path text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reject_reason text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, category_slug, document_type)
);
alter table public.provider_company_verification_submissions enable row level security;
revoke all on public.provider_company_verification_submissions from public, anon, authenticated;
grant select on public.provider_company_verification_submissions to authenticated;
drop policy if exists provider_company_verification_owner_select
  on public.provider_company_verification_submissions;
create policy provider_company_verification_owner_select
  on public.provider_company_verification_submissions for select to authenticated
  using (user_id = auth.uid());
drop policy if exists provider_company_verification_admin_select
  on public.provider_company_verification_submissions;
create policy provider_company_verification_admin_select
  on public.provider_company_verification_submissions for select to authenticated
  using (private.is_admin());

create or replace function private.enforce_provider_capability_policy()
returns trigger language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_category text;
  v_type text;
  v_policy text;
  v_admin boolean := private.is_admin();
begin
  select nc.category_slug, nc.verification_policy, nc.capability_type
    into v_category, v_policy, v_type
    from public.need_capabilities nc where nc.slug = new.capability_slug;
  if not found then
    raise exception 'Provider capability is unavailable.' using errcode = 'P0203';
  end if;
  if v_type = 'service' and exists (
    select 1 from public.provider_category_profiles pcp
    where pcp.user_id = new.user_id and pcp.category_slug = v_category
      and pcp.provider_type = 'individual'
  ) then
    raise exception 'Individual profiles cannot offer company services.' using errcode = 'P0214';
  end if;
  if v_policy = 'required_proof' then
    new.is_active := new.verification_level = 'provider_verified'
      and (v_admin or exists (
        select 1 from public.provider_capability_evidence e
        where e.provider_capability_id = new.id and e.status = 'approved'
          and (e.expires_at is null or e.expires_at > now())
      ));
  else
    new.is_active := true;
  end if;
  if not v_admin and new.verification_level = 'provider_verified' then
    if tg_op = 'UPDATE' and old.verification_level = 'provider_verified' then
      new.verified_by := old.verified_by;
      new.verified_at := old.verified_at;
    else
      new.verification_level := 'self_declared';
      new.verified_by := null;
      new.verified_at := null;
      if v_policy = 'required_proof' then new.is_active := false; end if;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_enforce_provider_capability_policy on public.provider_capabilities;
create trigger trg_enforce_provider_capability_policy
  before insert or update on public.provider_capabilities
  for each row execute function private.enforce_provider_capability_policy();

-- Preserve an existing admin grant when an owner edits capability metadata;
-- still reject any attempt to elevate an unverified row themselves.
create or replace function private.trg_enforce_provider_capability_verification()
returns trigger language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_is_admin boolean := private.is_admin();
begin
  if not v_is_admin then
    if tg_op = 'UPDATE'
       and old.verification_level = 'provider_verified'
       and new.verification_level = 'provider_verified' then
      new.verification_level := old.verification_level;
      new.verified_by := old.verified_by;
      new.verified_at := old.verified_at;
    else
      new.verification_level := 'self_declared';
      new.verified_by := null;
      new.verified_at := null;
    end if;
  elsif new.verification_level = 'provider_verified'
        and (tg_op = 'INSERT' or old.verification_level <> 'provider_verified') then
    new.verified_by := auth.uid();
    new.verified_at := coalesce(new.verified_at, now());
  end if;
  return new;
end;
$$;

-- An approved, current capability evidence decision is the only event that can
-- activate a required-proof capability. A company document never touches this.
create or replace function private.refresh_provider_capability_policy_state()
returns trigger language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_policy text;
  v_capability_type text;
  v_provider_type text := 'both';
  v_rule_provider_type text := 'both';
  v_required text[];
  v_approved text[];
begin
  select nc.verification_policy, nc.capability_type
    into v_policy, v_capability_type
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  where pc.id = new.provider_capability_id;
  if not found then return new; end if;

  select coalesce(pcp.provider_type, 'both') into v_provider_type
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  left join public.provider_category_profiles pcp
    on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
  where pc.id = new.provider_capability_id;
  if exists (
    select 1 from public.verification_requirements r
    join public.provider_capabilities pc on pc.id = new.provider_capability_id
    where r.scope_type = 'capability' and r.scope_id = pc.capability_slug
      and r.provider_type = v_provider_type and r.is_active
  ) then v_rule_provider_type := v_provider_type;
  else v_rule_provider_type := 'both'; end if;

  select coalesce(array_agg(distinct k), array[]::text[]) into v_required
  from (
    select unnest(coalesce(r.required_evidence, array[]::text[])) as k
    from public.verification_requirements r
    join public.provider_capabilities pc on pc.id = new.provider_capability_id
    join public.need_capabilities nc on nc.slug = pc.capability_slug
    where r.is_active and r.scope_type = 'capability' and r.scope_id = pc.capability_slug
      and r.provider_type = v_rule_provider_type
    union
    select jsonb_array_elements_text(case when jsonb_typeof(r.evidence_requirements) = 'array'
      then r.evidence_requirements else '[]'::jsonb end)
    from public.verification_requirements r
    join public.provider_capabilities pc on pc.id = new.provider_capability_id
    where r.is_active and r.scope_type = 'capability' and r.scope_id = pc.capability_slug
      and r.provider_type = v_rule_provider_type
  ) keys;
  select coalesce(array_agg(distinct e.requirement_key), array[]::text[]) into v_approved
  from public.provider_capability_evidence e
  where e.provider_capability_id = new.provider_capability_id
    and e.status = 'approved' and (e.expires_at is null or e.expires_at > now());

  if v_policy = 'required_proof' then
    if v_capability_type = 'work' and cardinality(v_required) > 0
       and v_approved @> v_required then
      update public.provider_capabilities pc set
        verification_level = 'provider_verified',
        verified_by = auth.uid(), verified_at = now(), is_active = true
      where pc.id = new.provider_capability_id;
    elsif new.status in ('pending', 'rejected', 'expired') then
      update public.provider_capabilities pc set
        verification_level = case when v_capability_type = 'work'
          then 'self_declared' else pc.verification_level end,
        verified_by = case when v_capability_type = 'work' then null else pc.verified_by end,
        verified_at = case when v_capability_type = 'work' then null else pc.verified_at end,
        is_active = false
      where pc.id = new.provider_capability_id;
    else
      update public.provider_capabilities pc set is_active = false
      where pc.id = new.provider_capability_id;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_refresh_provider_capability_policy_state
  on public.provider_capability_evidence;
create trigger trg_refresh_provider_capability_policy_state
  after insert or update of status, expires_at on public.provider_capability_evidence
  for each row execute function private.refresh_provider_capability_policy_state();

-- Qualification uploads in Individual F are mirrored to the common evidence
-- table so capability policy, status, and admin reporting share one source.
create or replace function private.sync_role_claim_to_capability_evidence()
returns trigger language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_key text := new.qualification_slug;
  v_status text;
  v_provider_type text := 'both';
  v_category text;
begin
  if new.evidence_object_path is null or new.status not in
      ('pending_review', 'verified', 'rejected', 'expired') then
    return new;
  end if;
  v_status := case new.status
    when 'pending_review' then 'pending'
    when 'verified' then 'approved'
    when 'rejected' then 'rejected'
    else 'expired' end;
  select nc.category_slug, coalesce(pcp.provider_type, 'both')
    into v_category, v_provider_type
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  left join public.provider_category_profiles pcp
    on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
  where pc.id = new.provider_capability_id;

  update public.provider_capability_evidence set
    status = v_status, reject_reason = new.reject_reason,
    reviewed_by = new.reviewed_by, reviewed_at = new.reviewed_at,
    expires_at = new.expires_at, updated_at = now()
  where provider_capability_id = new.provider_capability_id
    and requirement_key = v_key and file_url = new.evidence_object_path;
  if not found then
    insert into public.provider_capability_evidence(
      provider_capability_id, requirement_key, file_url, status,
      reject_reason, expires_at, reviewed_by, reviewed_at, provider_type
    ) values (
      new.provider_capability_id, v_key, new.evidence_object_path, v_status,
      new.reject_reason, new.expires_at, new.reviewed_by, new.reviewed_at,
      v_provider_type
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_sync_role_claim_to_capability_evidence
  on public.provider_role_qualification_claims;
create trigger trg_sync_role_claim_to_capability_evidence
  after insert or update of status, evidence_object_path
  on public.provider_role_qualification_claims
  for each row execute function private.sync_role_claim_to_capability_evidence();

create or replace function private.provider_capability_is_eligible(p_capability_id uuid)
returns boolean language plpgsql security definer stable
set search_path = public, private, pg_temp as $$
declare
  v_slug text;
  v_policy text;
  v_type text := 'both';
  v_rule_type text := 'both';
  v_active boolean;
  v_has_requirements boolean := false;
  v_key text;
begin
  select pc.capability_slug, nc.verification_policy, pc.is_active
    into v_slug, v_policy, v_active
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  where pc.id = p_capability_id;
  if not found or not v_active then return false; end if;
  if v_policy <> 'required_proof' then return true; end if;

  select coalesce(pcp.provider_type, 'both') into v_type
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  left join public.provider_category_profiles pcp
    on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
  where pc.id = p_capability_id;
  if exists (select 1 from public.verification_requirements r
    where r.scope_type = 'capability' and r.scope_id = v_slug
      and r.provider_type = v_type and r.is_active) then
    v_rule_type := v_type;
  end if;

  for v_key in
    select distinct keys.value from (
      select unnest(coalesce(r.required_evidence, array[]::text[])) as value
      from public.verification_requirements r
      where r.scope_type = 'capability' and r.scope_id = v_slug
        and r.provider_type = v_rule_type and r.is_active
      union
      select jsonb_array_elements_text(case when jsonb_typeof(r.evidence_requirements) = 'array'
        then r.evidence_requirements else '[]'::jsonb end)
      from public.verification_requirements r
      where r.scope_type = 'capability' and r.scope_id = v_slug
        and r.provider_type = v_rule_type and r.is_active
    ) keys
  loop
    v_has_requirements := true;
    if not exists (select 1 from public.provider_capability_evidence e
      where e.provider_capability_id = p_capability_id
        and e.requirement_key = v_key and e.status = 'approved'
        and (e.expires_at is null or e.expires_at > now())) then
      return false;
    end if;
  end loop;
  return v_has_requirements and exists (
    select 1 from public.provider_capabilities pc
    where pc.id = p_capability_id and pc.verification_level = 'provider_verified'
  );
end;
$$;
revoke all on function private.provider_capability_is_eligible(uuid) from public;
grant execute on function private.provider_capability_is_eligible(uuid)
  to authenticated, anon;

create or replace function public.submit_provider_company_verification(
  p_category_slug text, p_document_type text, p_file_path text
) returns void language plpgsql security definer
set search_path = public, private, storage, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_size bigint;
  v_mime text;
  v_country text;
  v_enabled text;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_document_type not in ('business_registration', 'business_licence') then
    raise exception 'Company verification document type is invalid.' using errcode = 'P0204';
  end if;
  if not exists (select 1 from public.provider_category_profiles pcp
    where pcp.user_id = v_user and pcp.category_slug = p_category_slug
      and pcp.provider_type = 'company') then
    raise exception 'Choose Company / Organization for this category first.' using errcode = 'P0202';
  end if;
  if not exists (select 1 from public.need_categories c
      where c.slug = p_category_slug and c.is_active) then
    raise exception 'This provider category is not active.' using errcode = 'P0201';
  end if;
  select country into v_country from public.profiles where id = v_user;
  select setting_value into v_enabled from public.system_settings
    where setting_key = 'capability_profiles_enabled' and is_public
      and (country = v_country or country is null)
    order by (country = v_country) desc nulls last limit 1;
  if lower(coalesce(v_enabled, 'false')) not in ('true', '1') then
    raise exception 'Provider services are not enabled in your market.' using errcode = 'P0202';
  end if;
  if p_file_path not like 'evidence/' || v_user::text || '/' || p_category_slug || '/company/%' then
    raise exception 'Company verification file path is invalid.' using errcode = 'P0205';
  end if;
  select (o.metadata->>'size')::bigint, lower(coalesce(o.metadata->>'mimetype', ''))
    into v_size, v_mime from storage.objects o
    where o.bucket_id = 'provider-evidence' and o.name = p_file_path
      and o.owner_id = v_user::text;
  if not found or v_size is null or v_size > 5242880
     or v_mime not in ('image/jpeg', 'image/png', 'application/pdf') then
    raise exception 'Company evidence must be an owned JPG, PNG, or PDF up to 5 MB.' using errcode = 'P0205';
  end if;
  insert into public.provider_company_verification_submissions(
    user_id, category_slug, document_type, file_path, status,
    reject_reason, reviewed_by, reviewed_at, created_at, updated_at
  ) values (v_user, p_category_slug, p_document_type, p_file_path, 'pending',
    null, null, null, now(), now())
  on conflict (user_id, category_slug, document_type) do update set
    file_path = excluded.file_path, status = 'pending', reject_reason = null,
    reviewed_by = null, reviewed_at = null, created_at = now(), updated_at = now();
  insert into public.audit_logs(user_id, event_type, entity_type, action, new_values)
  values (v_user, 'admin_action', 'provider_company_verification', 'submit_company_document',
    jsonb_build_object('category_slug', p_category_slug, 'document_type', p_document_type));
end;
$$;
revoke all on function public.submit_provider_company_verification(text, text, text)
  from public, anon;
grant execute on function public.submit_provider_company_verification(text, text, text)
  to authenticated;

create or replace function public.admin_review_provider_company_verification(
  p_user_id uuid, p_category_slug text, p_document_type text,
  p_action text, p_reject_reason text default null
) returns boolean language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_admin uuid := auth.uid();
  v_row public.provider_company_verification_submissions%rowtype;
begin
  if not private.is_admin() then raise exception 'Admin access required.' using errcode = '42501'; end if;
  if p_action not in ('approve', 'reject') then
    raise exception 'Invalid company verification action.' using errcode = 'P0204';
  end if;
  if p_action = 'reject' and nullif(btrim(p_reject_reason), '') is null then
    raise exception 'A rejection reason is required.' using errcode = 'P0204';
  end if;
  update public.provider_company_verification_submissions set
    status = case when p_action = 'approve' then 'approved' else 'rejected' end,
    reject_reason = case when p_action = 'reject' then left(btrim(p_reject_reason), 300) else null end,
    reviewed_by = v_admin, reviewed_at = now(), updated_at = now()
  where user_id = p_user_id and category_slug = p_category_slug
    and document_type = p_document_type
  returning * into v_row;
  if not found then raise exception 'Company verification submission not found.' using errcode = 'P0212'; end if;
  insert into public.audit_logs(user_id, event_type, entity_type, action, old_values, new_values)
  values (v_admin, 'admin_action', 'provider_company_verification',
    'review_company_document', null,
    jsonb_build_object('provider_user_id', p_user_id, 'category_slug', p_category_slug,
      'document_type', p_document_type, 'action', p_action,
      'reject_reason', p_reject_reason, 'reviewed_at', now()));
  return true;
end;
$$;
revoke all on function public.admin_review_provider_company_verification(uuid, text, text, text, text)
  from public, anon;
grant execute on function public.admin_review_provider_company_verification(uuid, text, text, text, text)
  to authenticated;

-- Private provider-facing status view: append policy and activity fields while
-- preserving all existing columns and their order for current clients.
create or replace view public.v_my_capability_policy_status
with (security_invoker = true) as
select v.*, nc.verification_policy,
       pc.is_active and private.provider_capability_is_eligible(pc.id) as is_active
from public.v_my_capability_status v
join public.provider_capabilities pc on pc.id = v.provider_capability_id
join public.need_capabilities nc on nc.slug = pc.capability_slug;
grant select on public.v_my_capability_policy_status to authenticated;

-- Filter private matching results without changing RPC columns or grants.
create or replace function public.get_provider_opportunities(p_user_id uuid default null, p_limit int default 20)
returns table(capability_slug text, capability_name text, category_slug text, category_name text,
 category_icon text, open_needs_count bigint, latest_need_id uuid, latest_need_title text,
 latest_need_budget bigint, latest_need_currency text, latest_need_location text,
 latest_need_created_at timestamptz)
language plpgsql security definer set search_path = public, private, pg_temp as $$
declare v_caller uuid := coalesce(p_user_id, auth.uid());
begin
 if v_caller is null or (v_caller <> auth.uid() and not private.is_admin()) then return; end if;
 return query
 with user_caps as (
  select pc.capability_slug, nc.name capability_name, nc.category_slug,
         cat.name category_name, cat.icon category_icon
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  join public.need_categories cat on cat.slug = nc.category_slug
  left join public.provider_category_profiles pcp
    on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
  where pc.user_id = v_caller and private.provider_capability_is_eligible(pc.id)
    and (nc.capability_type = 'work' or coalesce(pcp.provider_type, 'company') <> 'individual')
 ), matching_needs as (
  select uc.capability_slug, nr.request_id, nr.title, nr.budget, nr.currency, nr.location, nr.listed_at
  from user_caps uc join public.needs_requests nr
   on nr.capability_slug = uc.capability_slug or (nr.capability_slug is null and nr.category_slug = uc.category_slug)
  where nr.status = 'active' and nr.requester_id is distinct from v_caller
   and (nr.expires_at is null or nr.expires_at > now())
   and not exists(select 1 from public.need_offers nof where nof.need_id = nr.request_id and nof.offer_maker_id = v_caller)
 ), capability_counts as (
  select mn.capability_slug, count(*) cnt, max(mn.listed_at) max_listed
  from matching_needs mn group by mn.capability_slug
 )
 select uc.capability_slug, uc.capability_name, uc.category_slug, uc.category_name, uc.category_icon,
   cc.cnt, latest.request_id, latest.title, latest.budget, latest.currency, latest.location, latest.listed_at
 from capability_counts cc join user_caps uc on uc.capability_slug = cc.capability_slug
 cross join lateral(select mn.request_id,mn.title,mn.budget,mn.currency,mn.location,mn.listed_at
   from matching_needs mn where mn.capability_slug = cc.capability_slug
   order by mn.listed_at desc limit 1) latest
 order by cc.cnt desc, latest.listed_at desc limit p_limit;
end; $$;
revoke all on function public.get_provider_opportunities(uuid, int) from public, anon;
grant execute on function public.get_provider_opportunities(uuid, int) to authenticated;

-- The existing need-offer validator remains intact; this additive gate keeps
-- inactive restricted capabilities from being used even via direct RPC calls.
create or replace function private.require_active_provider_capability_for_offer()
returns trigger language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare v_need public.needs_requests%rowtype;
begin
  select * into v_need from public.needs_requests where request_id = new.need_id;
  if not found then return new; end if;
  if not exists (
    select 1 from public.provider_capabilities pc
    join public.need_capabilities nc on nc.slug = pc.capability_slug
    where pc.user_id = new.offer_maker_id
      and private.provider_capability_is_eligible(pc.id)
      and (pc.capability_slug = v_need.capability_slug
        or (v_need.capability_slug is null and nc.category_slug = v_need.category_slug))
      and (nc.capability_type = 'work' or not exists (
        select 1 from public.provider_category_profiles pcp
        where pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
          and pcp.provider_type = 'individual'
      ))
  ) then
    raise exception 'An active provider capability is required to make this offer.' using errcode = 'P0215';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_need_offer_requires_active_provider_capability on public.need_offers;
create trigger trg_need_offer_requires_active_provider_capability
  before insert on public.need_offers
  for each row execute function private.require_active_provider_capability_for_offer();

create or replace view public.v_provider_badges as
select pc.user_id, pc.capability_slug, nc.name as capability_name,
       nc.category_slug, cat.name as category_name, cat.icon as category_icon,
       pc.verification_level, coalesce(k.status = 'approved', false) as kyc_verified,
       p.phone_verified_at is not null as phone_verified
from public.provider_capabilities pc
join public.need_capabilities nc on nc.slug = pc.capability_slug
join public.need_categories cat on cat.slug = nc.category_slug
join public.profiles p on p.id = pc.user_id
left join public.kyc_verifications k on k.user_id = pc.user_id
left join public.provider_category_profiles pcp
  on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
where private.provider_capability_is_eligible(pc.id)
  and (nc.capability_type = 'work' or coalesce(pcp.provider_type, 'company') <> 'individual');

-- Company documents are submitted and reviewed separately from service
-- capability evidence. Ignore any legacy fan-out payload on the older RPC.
create or replace function public.save_company_category(
  p_category_slug text,
  p_services text[] default array[]::text[],
  p_roles text[] default array[]::text[],
  p_profile jsonb default '{}'::jsonb,
  p_evidence jsonb default '[]'::jsonb
) returns void language plpgsql security invoker
set search_path = public, private, pg_temp as $$
begin
  perform private.save_company_category_internal(
    p_category_slug, p_services, p_roles, p_profile, '[]'::jsonb
  );
end;
$$;
revoke all on function public.save_company_category(text, text[], text[], jsonb, jsonb)
  from public, anon;
grant execute on function public.save_company_category(text, text[], text[], jsonb, jsonb)
  to authenticated;

commit;

-- Staging checks: table RLS, RPC grants, trigger execution, policy transitions,
-- offer rejection for inactive service, and owner/admin/other user document access.
