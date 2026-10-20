-- Harden capability evidence submission while retaining the existing review model.
-- Safe to re-run. Evidence stays private and only admins can write review state.
begin;

alter table public.verification_requirements
  add column if not exists provider_type text not null default 'both';
alter table public.provider_capability_evidence
  add column if not exists provider_type text not null default 'both';

drop policy if exists "provider evidence owner insert" on public.provider_capability_evidence;
drop policy if exists "provider evidence owner resubmit" on public.provider_capability_evidence;
drop policy if exists "provider evidence admin all" on public.provider_capability_evidence;
drop policy if exists "provider evidence owner select" on public.provider_capability_evidence;
create policy "provider evidence admin all"
  on public.provider_capability_evidence for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
create policy "provider evidence owner select"
  on public.provider_capability_evidence for select to authenticated
  using (exists (select 1 from public.provider_capabilities pc
    where pc.id = provider_capability_evidence.provider_capability_id
      and (pc.user_id = auth.uid() or private.is_admin())));
revoke all on public.provider_capability_evidence from anon, public;
revoke insert, update, delete on public.provider_capability_evidence from authenticated;
grant select on public.provider_capability_evidence to authenticated;

create or replace function public.submit_provider_capability_evidence(
  p_provider_capability_id uuid,
  p_requirement_key text,
  p_file_url text
) returns uuid
language plpgsql security definer
set search_path = public, private, storage, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_capability_slug text;
  v_category_slug text;
  v_id uuid;
  v_key text := btrim(coalesce(p_requirement_key, ''));
  v_path text := btrim(coalesce(p_file_url, ''));
  v_scope_type text;
  v_scope_id text;
  v_provider_type text := 'both';
  v_rule_provider_type text := 'both';
  v_allowed boolean := false;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select pc.capability_slug, nc.category_slug into v_capability_slug, v_category_slug
    from public.provider_capabilities pc
    join public.need_capabilities nc on nc.slug = pc.capability_slug
    where pc.id = p_provider_capability_id and pc.user_id = v_user;
  if not found then raise exception 'Provider capability not found for current user.' using errcode = '42501'; end if;
  if v_key = '' or v_path = '' then raise exception 'Evidence key and object path are required.' using errcode = '22023'; end if;

  select coalesce(p.provider_type, 'both') into v_provider_type
    from public.provider_category_profiles p
    where p.user_id = v_user and p.category_slug = v_category_slug;
  v_provider_type := coalesce(v_provider_type, 'both');

  select 'capability', v_capability_slug into v_scope_type, v_scope_id
    where exists (select 1 from public.verification_requirements r
      where r.scope_type = 'capability' and r.scope_id = v_capability_slug and r.is_active
        and r.provider_type in (v_provider_type, 'both'));
  if not found then
    select 'category', v_category_slug into v_scope_type, v_scope_id
      where exists (select 1 from public.verification_requirements r
        where r.scope_type = 'category' and r.scope_id = v_category_slug and r.is_active
          and r.provider_type in (v_provider_type, 'both'));
  end if;
  select case when exists (
      select 1 from public.verification_requirements r
      where r.scope_type = v_scope_type and r.scope_id = v_scope_id
        and r.provider_type = v_provider_type and r.is_active
    ) then v_provider_type else 'both' end into v_rule_provider_type;
  select exists (
    select 1 from public.verification_requirements r
    where r.is_active and r.scope_type = v_scope_type and r.scope_id = v_scope_id
      and r.provider_type = v_rule_provider_type and (
      v_key = any(coalesce(r.required_evidence, array[]::text[]))
      or exists (select 1 from jsonb_array_elements_text(
        case when jsonb_typeof(r.evidence_requirements) = 'array' then r.evidence_requirements else '[]'::jsonb end
      ) x(value) where x.value = v_key)
    )
  ) into v_allowed;
  if not v_allowed then raise exception 'Evidence type is not configured for this capability.' using errcode = '22023'; end if;

  if v_path not like 'evidence/' || v_user::text || '/' || v_capability_slug || '/%' then
    raise exception 'Evidence object path must belong to the current user and capability.' using errcode = '42501';
  end if;
  if not exists (select 1 from storage.objects o
    where o.bucket_id = 'provider-evidence' and o.name = v_path and o.owner_id = v_user::text) then
    raise exception 'Private evidence upload not found for current user.' using errcode = '42501';
  end if;

  insert into public.provider_capability_evidence(
    provider_capability_id, requirement_key, file_url, status, provider_type
  ) values (p_provider_capability_id, v_key, v_path, 'pending', v_provider_type)
    returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.submit_provider_capability_evidence(uuid, text, text) from public, anon;
grant execute on function public.submit_provider_capability_evidence(uuid, text, text) to authenticated;

-- Keep the existing admin review flow, but include category-level configured
-- evidence and ensure an explicit admin approval promotes only this capability.
create or replace function public.admin_review_provider_capability_evidence(
  p_evidence_id uuid,
  p_action text,
  p_reject_reason text default null,
  p_expires_at timestamptz default null
) returns boolean
language plpgsql security definer
set search_path = public, private, pg_temp
as $$
declare
  v_admin uuid := auth.uid();
  v_evidence record;
  v_required text[] := array[]::text[];
  v_approved_count int := 0;
  v_scope_type text;
  v_scope_id text;
  v_provider_type text := 'both';
  v_rule_provider_type text := 'both';
  v_expiry_days integer;
  v_review_expiry timestamptz;
begin
  if not private.is_admin() then
    raise exception 'Unauthorized: Admin access required' using errcode = '42501';
  end if;
  if p_action not in ('approve', 'reject', 'expire') then
    raise exception 'Invalid evidence review action.' using errcode = '22023';
  end if;
  select e.*, pc.user_id as provider_user_id, pc.capability_slug, nc.category_slug into v_evidence
    from public.provider_capability_evidence e
    join public.provider_capabilities pc on pc.id = e.provider_capability_id
    join public.need_capabilities nc on nc.slug = pc.capability_slug
    where e.id = p_evidence_id for update of e;
  if not found then raise exception 'Provider capability evidence not found.' using errcode = 'P0212'; end if;

  v_provider_type := coalesce(v_evidence.provider_type, 'both');

  update public.provider_capability_evidence set
    status = case when p_action = 'approve' then 'approved' when p_action = 'reject' then 'rejected' else 'expired' end,
    reject_reason = case when p_action = 'reject' then coalesce(p_reject_reason, '') else null end,
    expires_at = case when p_action = 'approve' then p_expires_at else expires_at end,
    reviewed_by = v_admin, reviewed_at = now(), updated_at = now()
    where id = p_evidence_id;

  select 'capability', v_evidence.capability_slug into v_scope_type, v_scope_id
    where exists (select 1 from public.verification_requirements r
      where r.scope_type = 'capability' and r.scope_id = v_evidence.capability_slug and r.is_active
        and r.provider_type in (v_provider_type, 'both'));
  if not found then
    select 'category', v_evidence.category_slug into v_scope_type, v_scope_id
      where exists (select 1 from public.verification_requirements r
        where r.scope_type = 'category' and r.scope_id = v_evidence.category_slug and r.is_active
          and r.provider_type in (v_provider_type, 'both'));
  end if;
  select case when exists (
      select 1 from public.verification_requirements r
      where r.scope_type = v_scope_type and r.scope_id = v_scope_id
        and r.provider_type = v_provider_type and r.is_active
    ) then v_provider_type else 'both' end into v_rule_provider_type;
  select coalesce(array_agg(distinct x.value), array[]::text[]) into v_required
    from public.verification_requirements r
    cross join lateral unnest(coalesce(r.required_evidence, array[]::text[]) || coalesce(
      (select array_agg(j.value) from jsonb_array_elements_text(
        case when jsonb_typeof(r.evidence_requirements) = 'array' then r.evidence_requirements else '[]'::jsonb end
      ) j(value)), array[]::text[]
    )) x(value)
    where r.scope_type = v_scope_type and r.scope_id = v_scope_id and r.is_active
      and r.provider_type = v_rule_provider_type;
  v_required := coalesce(v_required, array[]::text[]);

  select r.expires_after_days into v_expiry_days
    from public.verification_requirements r
    where r.scope_type = v_scope_type and r.scope_id = v_scope_id and r.is_active
      and r.provider_type = v_rule_provider_type
    order by (r.provider_type = v_provider_type) desc
    limit 1;
  v_review_expiry := coalesce(p_expires_at,
    case when v_expiry_days is not null then now() + make_interval(days => v_expiry_days) end);
  if p_action = 'approve' and p_expires_at is null and v_review_expiry is not null then
    update public.provider_capability_evidence
      set expires_at = v_review_expiry where id = p_evidence_id;
  end if;

  if p_action = 'approve' then
    if cardinality(v_required) = 0 then
      v_approved_count := 1; -- The authorized reviewer approved this capability's submitted evidence.
    else
      select count(distinct e.requirement_key) into v_approved_count
        from public.provider_capability_evidence e
        where e.provider_capability_id = v_evidence.provider_capability_id
          and e.status = 'approved' and e.requirement_key = any(v_required)
          and (e.expires_at is null or e.expires_at > now());
    end if;
    if v_approved_count = cardinality(v_required) or cardinality(v_required) = 0 then
      update public.provider_capabilities set verification_level = 'provider_verified',
        verified_by = v_admin, verified_at = now()
        where id = v_evidence.provider_capability_id;
    end if;
  elsif p_action in ('reject', 'expire') then
    update public.provider_capabilities set verification_level = 'self_declared',
      verified_by = null, verified_at = null where id = v_evidence.provider_capability_id;
  end if;

  insert into public.audit_logs(user_id, event_type, entity_type, entity_id, action, new_values)
  values (v_admin, 'admin_action', 'provider_capability_evidence', p_evidence_id,
    'review_provider_capability_evidence', jsonb_build_object(
      'action', p_action, 'provider_capability_id', v_evidence.provider_capability_id,
      'capability_slug', v_evidence.capability_slug, 'requirement_key', v_evidence.requirement_key,
      'provider_type', v_provider_type, 'reject_reason', p_reject_reason,
      'expires_at', v_review_expiry));
  return true;
end;
$$;
revoke all on function public.admin_review_provider_capability_evidence(uuid, text, text, timestamptz) from public, anon;
grant execute on function public.admin_review_provider_capability_evidence(uuid, text, text, timestamptz) to authenticated;

commit;
