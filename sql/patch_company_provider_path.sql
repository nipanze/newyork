-- Company provider category path: private profile, atomic service-only save,
-- and capability-specific evidence fan-out. Safe to rerun; this patch is additive.
begin;

alter table public.verification_requirements
  add column if not exists provider_type text not null default 'both';
alter table public.provider_capability_evidence
  add column if not exists provider_type text not null default 'both';

create table if not exists public.provider_company_profiles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_slug text not null references public.need_categories(slug) on delete cascade,
  company_name text check (char_length(company_name) <= 80),
  registration_number text check (char_length(registration_number) <= 40),
  team_size text check (team_size is null or team_size in ('1-5','6-20','21-50','50+')),
  years_in_business text check (years_in_business is null or years_in_business in ('<1','1-2','3-5','6-10','10+')),
  service_areas text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, category_slug)
);

alter table public.provider_company_profiles enable row level security;
revoke all on public.provider_company_profiles from public, anon, authenticated;
grant select on public.provider_company_profiles to authenticated;
drop policy if exists provider_company_profile_owner_select on public.provider_company_profiles;
create policy provider_company_profile_owner_select
  on public.provider_company_profiles for select to authenticated
  using (user_id = auth.uid());
drop policy if exists provider_company_profile_admin_select on public.provider_company_profiles;
create policy provider_company_profile_admin_select
  on public.provider_company_profiles for select to authenticated
  using (private.is_admin());

-- Move details from the previous Company review form into the private table,
-- then remove those values from capability metadata where summaries/views may
-- expose them. Re-running is safe because the profile insert is conflict-safe
-- and the metadata cleanup is idempotent.
with legacy_company_details as (
  select distinct on (pc.user_id, nc.category_slug)
    pc.user_id,
    nc.category_slug,
    nullif(btrim(pc.metadata->>'organization_name'), '') as company_name,
    nullif(btrim(pc.metadata->>'business_registration'), '') as registration_number
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  join public.provider_category_profiles pcp
    on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
  where pcp.provider_type = 'company'
    and (pc.metadata ? 'organization_name' or pc.metadata ? 'business_registration')
  order by pc.user_id, nc.category_slug, pc.created_at desc
), migrated as (
  insert into public.provider_company_profiles(
    user_id, category_slug, company_name, registration_number
  )
  select user_id, category_slug, company_name, registration_number
    from legacy_company_details
  on conflict (user_id, category_slug) do update set
    company_name = coalesce(provider_company_profiles.company_name, excluded.company_name),
    registration_number = coalesce(provider_company_profiles.registration_number, excluded.registration_number)
  returning user_id, category_slug
)
insert into public.audit_logs(user_id, event_type, entity_type, action, new_values)
select user_id, 'admin_action', 'provider_company_profile',
  'migrate_legacy_company_details',
  jsonb_build_object('category_slug', category_slug, 'source', 'capability_metadata')
from migrated;

update public.provider_capabilities pc
set metadata = coalesce(pc.metadata, '{}'::jsonb)
  - array['organization_name', 'business_registration', 'portfolio_url']::text[]
where coalesce(pc.metadata, '{}'::jsonb) ?| array[
  'organization_name', 'business_registration', 'portfolio_url'
];

create or replace function private.touch_provider_company_profile_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_provider_company_profile_updated_at
  on public.provider_company_profiles;
create trigger trg_provider_company_profile_updated_at
  before update on public.provider_company_profiles
  for each row execute function private.touch_provider_company_profile_updated_at();

create or replace function private.save_company_category_internal(
  p_category_slug text,
  p_services text[],
  p_roles text[],
  p_profile jsonb,
  p_evidence jsonb
) returns void
language plpgsql security definer
set search_path = public, private, storage, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_country text;
  v_type text;
  v_enabled text;
  v_limit integer := 30;
  v_count integer;
  v_services text[] := coalesce(p_services, array[]::text[]);
  v_roles text[] := coalesce(p_roles, array[]::text[]);
  v_service text;
  v_item jsonb;
  v_key text;
  v_path text;
  v_size bigint;
  v_mime text;
  v_recent_uploads integer := 0;
  v_profile jsonb := coalesce(p_profile, '{}'::jsonb);
  v_areas text[] := array[]::text[];
  v_old_profile jsonb;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_category_slug is null or btrim(p_category_slug) = '' then
    raise exception 'A provider category is required.' using errcode = 'P0201';
  end if;
  if jsonb_typeof(v_profile) <> 'object'
     or jsonb_typeof(coalesce(p_evidence, '[]'::jsonb)) <> 'array' then
    raise exception 'Company profile or evidence payload is invalid.' using errcode = 'P0201';
  end if;
  if cardinality(v_services) <> cardinality(array(select distinct x from unnest(v_services) x))
     or cardinality(v_roles) <> cardinality(array(select distinct x from unnest(v_roles) x))
     or v_services && v_roles then
    raise exception 'Duplicate or conflicting provider selections.' using errcode = 'P0201';
  end if;
  if cardinality(v_roles) > 0 then
    raise exception 'Company providers can select services only.' using errcode = 'P0201';
  end if;
  if cardinality(v_services) = 0 then
    raise exception 'Select at least one service.' using errcode = 'P0201';
  end if;
  if not exists (select 1 from public.need_categories c
    where c.slug = p_category_slug and c.is_active) then
    raise exception 'This provider category is not active.' using errcode = 'P0201';
  end if;
  select country into v_country from public.profiles where id = v_user;
  if not found then raise exception 'Provider profile is unavailable.' using errcode = 'P0201'; end if;
  select provider_type into v_type from public.provider_category_profiles
    where user_id = v_user and category_slug = p_category_slug;
  if v_type is distinct from 'company' then
    raise exception 'Choose Company / Organization for this category first.' using errcode = 'P0202';
  end if;

  select setting_value into v_enabled from public.system_settings
    where setting_key = 'capability_profiles_enabled' and is_public
      and (country = v_country or country is null)
    order by (country = v_country) desc nulls last limit 1;
  if lower(coalesce(v_enabled, 'false')) not in ('true', '1') then
    raise exception 'Provider services are not enabled in your market.' using errcode = 'P0202';
  end if;
  select setting_value into v_enabled from public.system_settings
    where setting_key = 'capability_profiles_enabled_' || p_category_slug and is_public
      and (country = v_country or country is null)
    order by (country = v_country) desc nulls last limit 1;
  if lower(coalesce(v_enabled, 'true')) in ('false', '0') then
    raise exception 'This provider category is not enabled in your market.' using errcode = 'P0202';
  end if;

  foreach v_service in array v_services loop
    if not exists (select 1 from public.need_capabilities nc
      where nc.slug = v_service and nc.category_slug = p_category_slug
        and nc.is_active and nc.capability_type = 'service') then
      raise exception 'A selected service is invalid for this category.' using errcode = 'P0203';
    end if;
  end loop;
  if length(coalesce(v_profile->>'company_name', '')) > 80
     or length(coalesce(v_profile->>'registration_number', '')) > 40
     or (v_profile ? 'team_size' and v_profile->>'team_size' not in ('1-5','6-20','21-50','50+'))
     or (v_profile ? 'years_in_business' and v_profile->>'years_in_business' not in ('<1','1-2','3-5','6-10','10+'))
     or (v_profile ? 'service_areas' and jsonb_typeof(v_profile->'service_areas') <> 'array') then
    raise exception 'Company profile details are invalid.' using errcode = 'P0204';
  end if;
  select coalesce(array_agg(distinct btrim(value)), array[]::text[]) into v_areas
    from jsonb_array_elements_text(coalesce(v_profile->'service_areas', '[]'::jsonb)) x(value)
    where btrim(value) <> '';
  if exists (select 1 from unnest(v_areas) area where length(area) > 80) then
    raise exception 'Service areas must be district or city names.' using errcode = 'P0204';
  end if;

  select coalesce(nullif(setting_value, '')::integer, 30) into v_limit
    from public.system_settings
    where setting_key = 'max_provider_capabilities'
      and (country = v_country or country is null)
    order by (country = v_country) desc nulls last limit 1;
  v_limit := coalesce(v_limit, 30);
  select count(*) into v_count
    from public.provider_capabilities pc
    join public.need_capabilities nc on nc.slug = pc.capability_slug
    where pc.user_id = v_user
      and (nc.category_slug <> p_category_slug or nc.capability_type = 'work');
  if v_count + cardinality(v_services) > v_limit then
    raise exception 'Maximum limit of % provider capabilities reached.', v_limit using errcode = 'P0206';
  end if;

  if jsonb_array_length(coalesce(p_evidence, '[]'::jsonb)) > 0 then
    select count(distinct e.file_url) into v_recent_uploads
      from public.provider_capability_evidence e
      join public.provider_capabilities pc on pc.id = e.provider_capability_id
      where pc.user_id = v_user and e.created_at > now() - interval '1 hour';
    if v_recent_uploads >= 20 then
      raise exception 'Evidence upload limit reached. Try again later.' using errcode = 'P0213';
    end if;
  end if;

  -- The Company path edits services only. Existing personal work profiles in
  -- this category remain unchanged and are never presented as Company roles.
  delete from public.provider_capabilities pc using public.need_capabilities nc
    where pc.capability_slug = nc.slug and pc.user_id = v_user
      and nc.category_slug = p_category_slug and nc.capability_type = 'service'
      and not (pc.capability_slug = any(v_services));

  foreach v_service in array v_services loop
    insert into public.provider_capabilities(user_id, capability_slug, verification_level, metadata, created_at)
      values (v_user, v_service, 'self_declared', '{}'::jsonb, now())
    on conflict (user_id, capability_slug) do update
      set verification_level = case when provider_capabilities.verification_level = 'provider_verified'
        then provider_capabilities.verification_level else 'self_declared' end;
  end loop;
  select to_jsonb(cp) into v_old_profile from public.provider_company_profiles cp
    where cp.user_id = v_user and cp.category_slug = p_category_slug;
  insert into public.provider_company_profiles(
    user_id, category_slug, company_name, registration_number, team_size,
    years_in_business, service_areas
  ) values (
    v_user, p_category_slug, nullif(btrim(v_profile->>'company_name'), ''),
    nullif(btrim(v_profile->>'registration_number'), ''),
    nullif(v_profile->>'team_size', ''), nullif(v_profile->>'years_in_business', ''), v_areas
  ) on conflict(user_id, category_slug) do update set
    company_name = excluded.company_name,
    registration_number = excluded.registration_number,
    team_size = excluded.team_size,
    years_in_business = excluded.years_in_business,
    service_areas = excluded.service_areas,
    updated_at = now();

  for v_item in select value from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb))
  loop
    v_key := btrim(coalesce(v_item->>'requirement_key', ''));
    v_path := btrim(coalesce(v_item->>'file_path', ''));
    if v_key = '' or v_path = '' or
       v_path not like 'evidence/' || v_user::text || '/' || p_category_slug || '/%' then
      raise exception 'Company evidence path or requirement is invalid.' using errcode = 'P0205';
    end if;
    if not exists (
      select 1 from public.verification_requirements r
      where r.is_active and (
        r.provider_type = 'company' or (r.provider_type = 'both' and not exists (
          select 1 from public.verification_requirements specific
          where specific.scope_type = r.scope_type and specific.scope_id = r.scope_id
            and specific.provider_type = 'company' and specific.is_active
        ))
      ) and (
        (r.scope_type = 'category' and r.scope_id = p_category_slug)
        or (r.scope_type = 'capability' and r.scope_id = any(v_services))
      ) and (
        v_key = any(coalesce(r.required_evidence, array[]::text[]))
        or exists (select 1 from jsonb_array_elements_text(
              case when jsonb_typeof(r.evidence_requirements) = 'array'
                then r.evidence_requirements else '[]'::jsonb end
            ) ev(value)
              where ev.value = v_key))
      ) then
      raise exception 'Evidence type is not required for selected company services.' using errcode = 'P0205';
    end if;
    select (o.metadata->>'size')::bigint, lower(coalesce(o.metadata->>'mimetype', ''))
      into v_size, v_mime from storage.objects o
      where o.bucket_id = 'provider-evidence' and o.name = v_path and o.owner_id = v_user::text;
    if not found then
      raise exception 'Uploaded evidence file is not owned by this provider.' using errcode = 'P0205';
    end if;
    if v_size is null or v_size > 5242880 or v_mime not in ('image/jpeg', 'image/png', 'application/pdf') then
      raise exception 'Evidence must be JPG, PNG, or PDF and no larger than 5 MB.' using errcode = 'P0205';
    end if;
    for v_service in select unnest(v_services) loop
      if exists (
        select 1 from public.verification_requirements r
        where r.is_active and (
          r.provider_type = 'company' or (r.provider_type = 'both' and not exists (
            select 1 from public.verification_requirements specific
            where specific.scope_type = r.scope_type and specific.scope_id = r.scope_id
              and specific.provider_type = 'company' and specific.is_active
          ))
        ) and (
          (r.scope_type = 'category' and r.scope_id = p_category_slug)
          or (r.scope_type = 'capability' and r.scope_id = v_service)
        ) and (
          v_key = any(coalesce(r.required_evidence, array[]::text[]))
          or exists (select 1 from jsonb_array_elements_text(
                case when jsonb_typeof(r.evidence_requirements) = 'array'
                  then r.evidence_requirements else '[]'::jsonb end
              ) ev(value)
                where ev.value = v_key))
        ) then
        insert into public.provider_capability_evidence(
          provider_capability_id, requirement_key, file_url, status, provider_type
        )
        select pc.id, v_key, v_path, 'pending', 'company'
          from public.provider_capabilities pc
          where pc.user_id = v_user and pc.capability_slug = v_service
            and not exists (select 1 from public.provider_capability_evidence e
              where e.provider_capability_id = pc.id and e.requirement_key = v_key
                and e.file_url = v_path);
      end if;
    end loop;
  end loop;

  insert into public.audit_logs(user_id, event_type, entity_type, action, old_values, new_values)
  values (v_user, 'admin_action', 'provider_company_profile', 'save_company_category',
    v_old_profile,
    jsonb_build_object('category_slug', p_category_slug,
      'services', to_jsonb(v_services), 'roles', to_jsonb(v_roles),
      'service_count', cardinality(v_services), 'role_count', cardinality(v_roles)));
end;
$$;
revoke all on function private.save_company_category_internal(text, text[], text[], jsonb, jsonb)
  from public, anon;
grant execute on function private.save_company_category_internal(text, text[], text[], jsonb, jsonb)
  to authenticated;
grant usage on schema private to authenticated;

create or replace function public.save_company_category(
  p_category_slug text,
  p_services text[] default array[]::text[],
  p_roles text[] default array[]::text[],
  p_profile jsonb default '{}'::jsonb,
  p_evidence jsonb default '[]'::jsonb
) returns void
language plpgsql security invoker
set search_path = public, private, pg_temp
as $$
begin
  perform private.save_company_category_internal(
    p_category_slug, p_services, p_roles, p_profile, p_evidence
  );
end;
$$;
revoke all on function public.save_company_category(text, text[], text[], jsonb, jsonb)
  from public, anon;
grant execute on function public.save_company_category(text, text[], text[], jsonb, jsonb)
  to authenticated;

-- Keep shared evidence objects until the final capability-specific reference is removed.
create or replace function private.delete_orphan_provider_evidence_object()
returns trigger language plpgsql security definer
set search_path = public, storage, pg_temp as $$
begin
  if not exists (select 1 from public.provider_capability_evidence e where e.file_url = old.file_url) then
    delete from storage.objects o where o.bucket_id = 'provider-evidence' and o.name = old.file_url;
  end if;
  return old;
end;
$$;
drop trigger if exists trg_delete_orphan_provider_evidence_object
  on public.provider_capability_evidence;
create trigger trg_delete_orphan_provider_evidence_object
  after delete on public.provider_capability_evidence
  for each row execute function private.delete_orphan_provider_evidence_object();

commit;

-- Verification after applying to staging:
-- select relrowsecurity from pg_class where oid = 'public.provider_company_profiles'::regclass;
-- select policyname, cmd, roles from pg_policies where tablename = 'provider_company_profiles';
-- select proname, prosecdef from pg_proc where proname = 'save_company_category';
-- Rollback: drop the RPC and private helper/trigger/functions, then drop
-- provider_company_profiles. Existing company capability rows remain untouched.
