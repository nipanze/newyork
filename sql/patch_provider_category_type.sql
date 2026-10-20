-- Provider type preference, scoped privately to the owner and category.
-- Rollback: drop the RPCs and provider_category_profiles table.

create table if not exists public.provider_category_profiles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_slug text not null references public.need_categories(slug),
  provider_type text not null check (provider_type in ('individual', 'company')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, category_slug)
);

alter table public.provider_category_profiles enable row level security;
revoke all on public.provider_category_profiles from anon, authenticated;
grant select on public.provider_category_profiles to authenticated;
drop policy if exists pcp_owner_select on public.provider_category_profiles;
create policy pcp_owner_select on public.provider_category_profiles
  for select to authenticated using (user_id = auth.uid());
drop policy if exists pcp_admin_select on public.provider_category_profiles;
create policy pcp_admin_select on public.provider_category_profiles
  for select to authenticated using (private.is_admin());

create or replace function private.set_provider_category_type_internal(
  p_category_slug text, p_provider_type text
) returns void
language plpgsql security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_old text;
  v_enabled text;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_provider_type is null or p_provider_type not in ('individual', 'company') then
    raise exception 'Invalid provider type' using errcode = 'P0214';
  end if;
  if p_category_slug is null or p_category_slug = 'financial_services'
    or not exists (select 1 from public.need_categories where slug = p_category_slug) then
    raise exception 'Unknown or retired provider category' using errcode = 'P0214';
  end if;
  select setting_value into v_enabled from public.system_settings
   where setting_key = 'capability_profiles_enabled' and is_public = true limit 1;
  if coalesce(lower(v_enabled), 'false') not in ('true', '1') then
    raise exception 'Provider capability profiles are disabled' using errcode = 'P0214';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 0));
  select provider_type into v_old from public.provider_category_profiles
   where user_id = v_user and category_slug = p_category_slug for update;
  if v_old is not distinct from p_provider_type then return; end if;

  -- Per-user limit: reuse the audit trail to throttle changed preference writes.
  if (select count(*) from public.audit_logs
       where user_id = v_user and entity_type = 'provider_category_profile'
         and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'Please wait before changing provider type again' using errcode = 'P0214';
  end if;
  insert into public.provider_category_profiles(user_id, category_slug, provider_type)
    values (v_user, p_category_slug, p_provider_type)
  on conflict (user_id, category_slug) do update
    set provider_type = excluded.provider_type, updated_at = now();
  insert into public.audit_logs(user_id, event_type, entity_type, action, old_values, new_values)
    values (v_user, 'admin_action', 'provider_category_profile', 'set_provider_category_type',
      case when v_old is null then null else jsonb_build_object('category_slug', p_category_slug, 'provider_type', v_old) end,
      jsonb_build_object('category_slug', p_category_slug, 'provider_type', p_provider_type));
end;
$$;
revoke all on function private.set_provider_category_type_internal(text, text) from public, anon;
grant execute on function private.set_provider_category_type_internal(text, text) to authenticated;

create or replace function public.set_provider_category_type(
  p_category_slug text, p_provider_type text
) returns void language plpgsql security invoker
set search_path = public, private, pg_temp
as $$ begin
  perform private.set_provider_category_type_internal(p_category_slug, p_provider_type);
end; $$;
revoke all on function public.set_provider_category_type(text, text) from public, anon;
grant execute on function public.set_provider_category_type(text, text) to authenticated;

create or replace function public.get_my_provider_category_types()
returns table(category_slug text, provider_type text)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  select p.category_slug, p.provider_type
  from public.provider_category_profiles p
  where p.user_id = auth.uid()
  order by p.category_slug;
$$;
revoke all on function public.get_my_provider_category_types() from public, anon;
grant execute on function public.get_my_provider_category_types() to authenticated;

-- Provider type eligibility. Individual profiles may keep old service rows, but
-- those rows cannot be newly saved, shown publicly, matched, or offered against.
create or replace function public.save_provider_capabilities(
  p_items jsonb default '[]'::jsonb,
  p_category_slug text default null,
  p_remove_slugs text[] default array[]::text[]
) returns setof public.provider_capabilities
language plpgsql security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_type text;
  v_is_work boolean;
  v_max int := 30;
  v_count int;
  v_item record;
  v_incoming text[] := array[]::text[];
begin
  if v_user is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Invalid capability selection' using errcode = 'P0215';
  end if;
  if p_category_slug is not null then
    select provider_type into v_type from public.provider_category_profiles
     where user_id = v_user and category_slug = p_category_slug;
  end if;
  for v_item in select * from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as x(capability_slug text, metadata jsonb)
  loop
    if v_item.capability_slug is null then
      raise exception 'Invalid capability for category' using errcode = 'P0215';
    end if;
    select pcp.provider_type, nc.capability_type = 'work' into v_type, v_is_work
      from public.need_capabilities nc left join public.provider_category_profiles pcp
        on pcp.user_id = v_user and pcp.category_slug = nc.category_slug
      where nc.slug = v_item.capability_slug
        and (p_category_slug is null or nc.category_slug = p_category_slug);
    if not found then raise exception 'Invalid capability for category' using errcode = 'P0215'; end if;
    if not coalesce(v_is_work, false) and coalesce(v_type, 'company') = 'individual' then
      raise exception 'Individual providers cannot save company services' using errcode = 'P0215';
    end if;
    v_incoming := array_append(v_incoming, v_item.capability_slug);
  end loop;
  select coalesce(nullif(setting_value, '')::int, 30) into v_max
    from public.system_settings where setting_key = 'max_provider_capabilities'
      and (country is null or country = '__global__') limit 1;
  select count(*) into v_count from public.provider_capabilities pc
    join public.need_capabilities nc on nc.slug = pc.capability_slug
    where pc.user_id = v_user and (
      (p_category_slug is not null and nc.category_slug <> p_category_slug)
      or (p_category_slug is null and not (pc.capability_slug = any(coalesce(p_remove_slugs, array[]::text[]))))
      or (p_category_slug is not null and coalesce(v_type, 'company') = 'individual'
          and nc.capability_type = 'service' and nc.category_slug = p_category_slug)
    );
  if v_count + cardinality(v_incoming) > coalesce(v_max, 30) then
    raise exception 'Maximum limit of % provider capabilities reached.', coalesce(v_max, 30) using errcode = 'P0206';
  end if;
  if coalesce(cardinality(p_remove_slugs), 0) > 0 then
    delete from public.provider_capabilities where user_id = v_user and capability_slug = any(p_remove_slugs);
  end if;
  if p_category_slug is not null then
    delete from public.provider_capabilities pc using public.need_capabilities nc
     where pc.capability_slug = nc.slug and pc.user_id = v_user and nc.category_slug = p_category_slug
       and not (pc.capability_slug = any(v_incoming))
       and (coalesce(v_type, 'company') <> 'individual' or nc.capability_type = 'work');
  end if;
  for v_item in select * from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as x(capability_slug text, metadata jsonb)
  loop
    insert into public.provider_capabilities(user_id, capability_slug, verification_level, metadata, created_at)
      values (v_user, v_item.capability_slug, 'self_declared', coalesce(v_item.metadata, '{}'::jsonb), now())
    on conflict (user_id, capability_slug) do update set metadata = case
      when excluded.metadata is not null and excluded.metadata <> '{}'::jsonb then excluded.metadata
      else public.provider_capabilities.metadata end;
  end loop;
  return query select * from public.provider_capabilities where user_id = v_user;
end;
$$;
grant execute on function public.save_provider_capabilities(jsonb, text, text[]) to authenticated;

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
left join public.provider_category_profiles pcp on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
where nc.capability_type = 'work' or coalesce(pcp.provider_type, 'company') <> 'individual';

create or replace function public.get_provider_opportunities(p_user_id uuid default null, p_limit int default 20)
returns table(capability_slug text, capability_name text, category_slug text, category_name text,
 category_icon text, open_needs_count bigint, latest_need_id uuid, latest_need_title text,
 latest_need_budget bigint, latest_need_currency text, latest_need_location text,
 latest_need_created_at timestamptz)
language plpgsql security definer set search_path = public, private, pg_temp as $$
declare v_caller uuid := coalesce(p_user_id, auth.uid());
begin
 if v_caller is null then return; end if;
 return query
 with user_caps as (
  select pc.capability_slug, nc.name capability_name, nc.category_slug,
         cat.name category_name, cat.icon category_icon
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  join public.need_categories cat on cat.slug = nc.category_slug
  left join public.provider_category_profiles pcp on pcp.user_id = pc.user_id and pcp.category_slug = nc.category_slug
  where pc.user_id = v_caller
    and (nc.capability_type = 'work' or coalesce(pcp.provider_type, 'company') <> 'individual')
 ), matching_needs as (
  select uc.capability_slug, nr.request_id, nr.title, nr.budget, nr.currency, nr.location, nr.listed_at
  from user_caps uc join public.needs_requests nr
   on nr.capability_slug = uc.capability_slug or (nr.capability_slug is null and nr.category_slug = uc.category_slug)
  where nr.status = 'active' and nr.requester_id is distinct from v_caller
   and (nr.expires_at is null or nr.expires_at > now())
   and not exists(select 1 from public.need_offers nof where nof.need_id = nr.request_id and nof.offer_maker_id = v_caller)
 ), capability_counts as (
  select mn.capability_slug, count(*) cnt, max(mn.listed_at) max_listed from matching_needs mn group by mn.capability_slug
 )
 select uc.capability_slug, uc.capability_name, uc.category_slug, uc.category_name, uc.category_icon,
   cc.cnt, latest.request_id, latest.title, latest.budget, latest.currency, latest.location, latest.listed_at
 from capability_counts cc join user_caps uc on uc.capability_slug = cc.capability_slug
 cross join lateral(select mn.request_id,mn.title,mn.budget,mn.currency,mn.location,mn.listed_at from matching_needs mn
   where mn.capability_slug = cc.capability_slug order by mn.listed_at desc limit 1) latest
 order by cc.cnt desc, latest.listed_at desc limit p_limit;
end; $$;
grant execute on function public.get_provider_opportunities(uuid, int) to authenticated;

-- Keep the existing offer-validation checks while excluding retained hidden services.
create or replace function private.trg_validate_need_offer()
returns trigger language plpgsql security definer set search_path = public, private, pg_temp as $$
declare
 v_need record; v_plan text; v_offer_count_month int; v_free_offer_cap int := 3;
 v_has_capability boolean := false; v_capability public.provider_capabilities%rowtype;
 v_check jsonb; v_match_score int;
begin
 perform private.require_identity_verified(new.offer_maker_id);
 select * into v_need from public.needs_requests where request_id = new.need_id;
 if not found then raise exception 'Need request not found' using errcode = 'P0201'; end if;
 if v_need.status <> 'active' or (v_need.expires_at is not null and v_need.expires_at <= now()) then
  raise exception 'Cannot offer on inactive or expired need request' using errcode = 'P0202'; end if;
 if v_need.requester_id = new.offer_maker_id then raise exception 'Cannot make an offer on your own need request' using errcode = 'P0205'; end if;
 v_check := private.check_verification_requirement(new.offer_maker_id,'need_offer',v_need.category_slug,v_need.capability_slug);
 if not coalesce((v_check->>'allowed')::boolean,false) then raise exception 'Cannot make offer: %',v_check->>'reason' using errcode = 'P0203'; end if;
 if v_need.capability_slug is not null then
  select pc.* into v_capability from public.provider_capabilities pc join public.need_capabilities nc on nc.slug=pc.capability_slug
  left join public.provider_category_profiles pcp on pcp.user_id=pc.user_id and pcp.category_slug=nc.category_slug
  where pc.user_id=new.offer_maker_id and pc.capability_slug=v_need.capability_slug
   and (nc.capability_type = 'work' or coalesce(pcp.provider_type,'company') <> 'individual') limit 1;
 else
  select pc.* into v_capability from public.provider_capabilities pc join public.need_capabilities nc on nc.slug=pc.capability_slug
  left join public.provider_category_profiles pcp on pcp.user_id=pc.user_id and pcp.category_slug=nc.category_slug
  where pc.user_id=new.offer_maker_id and nc.category_slug=v_need.category_slug
   and (nc.capability_type = 'work' or coalesce(pcp.provider_type,'company') <> 'individual')
  order by pc.created_at desc limit 1;
 end if;
 v_has_capability := found;
 if not v_has_capability then raise exception 'You must declare an eligible capability in this category before making offers' using errcode='P0203'; end if;
 if coalesce(v_need.details->>'engagement','')='hire_person' then
  v_match_score := private.capability_match_score(coalesce(v_need.details,'{}'::jsonb),coalesce(v_capability.metadata,'{}'::jsonb));
  if v_match_score <= 0 then raise exception 'Your service profile does not match the requested role or kind' using errcode='P0203'; end if;
 end if;
 select subscription_plan into v_plan from public.profiles where id=new.offer_maker_id;
 if coalesce(v_plan,'free')='free' then
  select coalesce(nullif(setting_value,'')::int,3) into v_free_offer_cap from public.system_settings where setting_key='needs_free_offers_per_month' and country is null;
  select count(*) into v_offer_count_month from public.need_offers where offer_maker_id=new.offer_maker_id and created_at >= date_trunc('month',now());
  if v_offer_count_month >= v_free_offer_cap then raise exception 'Free plan limit of % offers/month reached. Upgrade to make unlimited offers.',v_free_offer_cap using errcode='P0204'; end if;
 end if;
 new.terms_locked_at := coalesce(new.terms_locked_at,now()); return new;
end; $$;
