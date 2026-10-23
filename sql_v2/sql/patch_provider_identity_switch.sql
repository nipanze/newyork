-- Category-specific provider identity switching. Additive and safe to rerun.
-- Apply only after patch_provider_category_type.sql,
-- patch_company_provider_path.sql and patch_provider_verification_policies.sql.
begin;

alter table public.provider_category_profiles
  add column if not exists identity_changed_at timestamptz;

alter table public.provider_capabilities
  add column if not exists identity_type text;
alter table public.provider_capabilities
  drop constraint if exists provider_capabilities_identity_type_check;
alter table public.provider_capabilities
  add constraint provider_capabilities_identity_type_check
  check (identity_type is null or identity_type in ('individual','company'));

-- Keep the verification policy calculation, but let the identity guard below
-- retain legacy Individual service rows as inactive instead of aborting every
-- update to them. The previous policy trigger rejected the row before it
-- could be made inactive, which also blocked Company -> Individual switches.
create or replace function private.enforce_provider_capability_policy()
returns trigger language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_category text;
  v_policy text;
  v_type text;
  v_admin boolean := private.is_admin();
begin
  select nc.category_slug, nc.verification_policy, nc.capability_type
    into v_category, v_policy, v_type
    from public.need_capabilities nc where nc.slug = new.capability_slug;
  if not found then
    raise exception 'Provider capability is unavailable.' using errcode = 'P0203';
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

-- Apply identity ownership and inactive-state enforcement before the backfill,
-- so migration updates are evaluated under the same identity rules as writes.
create or replace function private.enforce_provider_identity_capability()
returns trigger language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare v_category text; v_kind text; v_current text;
begin
  select category_slug,capability_type into v_category,v_kind
    from public.need_capabilities where slug=new.capability_slug;
  if v_kind='service' then
    if tg_op='UPDATE' and old.identity_type is not null
       and new.identity_type is distinct from old.identity_type
       and not private.is_admin() then
      raise exception 'A service identity cannot be changed directly.' using errcode='P0216';
    end if;
    select provider_type into v_current from public.provider_category_profiles
      where user_id=new.user_id and category_slug=v_category;
    if new.identity_type is null then new.identity_type:=coalesce(v_current,'company'); end if;
    if new.identity_type not in ('individual','company') then
      raise exception 'Invalid capability identity.' using errcode='P0216';
    end if;
    -- Individual providers offer personal roles, not company service tiles.
    if new.is_active and (v_current='individual' or new.identity_type is distinct from v_current) then
      new.is_active:=false;
    end if;
  else
    new.identity_type:=null;
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_provider_identity_capability() from public,anon,authenticated;
drop trigger if exists trg_z_enforce_provider_identity_capability on public.provider_capabilities;
create trigger trg_z_enforce_provider_identity_capability
  before insert or update on public.provider_capabilities
  for each row execute function private.enforce_provider_identity_capability();

-- Work-role capabilities belong to the person's own profile. Service rows are
-- identity-bound; legacy rows inherit the category's saved identity.
update public.provider_capabilities pc
set identity_type = coalesce((select pcp.provider_type from public.provider_category_profiles pcp
  where pcp.user_id=pc.user_id and pcp.category_slug=nc.category_slug limit 1),'company')
from public.need_capabilities nc
where nc.slug = pc.capability_slug and nc.capability_type = 'service'
  and pc.identity_type is null;
create index if not exists provider_capabilities_identity_scope_idx
  on public.provider_capabilities(user_id, identity_type, capability_slug)
  where identity_type is not null;

create table if not exists public.provider_identity_presentations (
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_slug text not null references public.need_categories(slug) on delete cascade,
  identity_type text not null check (identity_type in ('individual','company')),
  display_mode text not null check (display_mode in ('personal','company','company_with_representative')),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  representative_name text check (representative_name is null or char_length(representative_name) <= 80),
  representative_authorized boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, category_slug, identity_type),
  check ((identity_type = 'individual' and display_mode = 'personal') or
         (identity_type = 'company' and display_mode in ('company','company_with_representative'))),
  check (display_mode <> 'company_with_representative' or
         (representative_authorized and nullif(btrim(representative_name), '') is not null))
);
alter table public.provider_identity_presentations enable row level security;
revoke all on public.provider_identity_presentations from public, anon, authenticated;
grant select on public.provider_identity_presentations to authenticated;
drop policy if exists provider_identity_presentation_owner_select
  on public.provider_identity_presentations;
create policy provider_identity_presentation_owner_select
  on public.provider_identity_presentations for select to authenticated
  using (user_id = auth.uid());
drop policy if exists provider_identity_presentation_admin_select
  on public.provider_identity_presentations;
create policy provider_identity_presentation_admin_select
  on public.provider_identity_presentations for select to authenticated
  using (private.is_admin());

alter table public.need_offers
  add column if not exists provider_identity_type text,
  add column if not exists provider_display_name text;
alter table public.need_contact_reveals
  add column if not exists provider_identity_type text,
  add column if not exists provider_display_name text;
alter table public.need_offers drop constraint if exists need_offers_provider_identity_type_check;
alter table public.need_offers add constraint need_offers_provider_identity_type_check
  check (provider_identity_type is null or provider_identity_type in ('individual','company'));
alter table public.need_contact_reveals drop constraint if exists need_contact_reveals_provider_identity_type_check;
alter table public.need_contact_reveals add constraint need_contact_reveals_provider_identity_type_check
  check (provider_identity_type is null or provider_identity_type in ('individual','company'));

-- Existing profile type changes must go through the atomic switch RPC below.
create or replace function private.set_provider_category_type_internal(
  p_category_slug text, p_provider_type text
) returns void language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_old text;
  v_enabled text;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_provider_type is null or p_provider_type not in ('individual','company') then
    raise exception 'Invalid provider type.' using errcode = 'P0216';
  end if;
  if not exists (select 1 from public.need_categories c
    where c.slug = p_category_slug and c.is_active and c.slug <> 'financial_services') then
    raise exception 'Unknown or retired provider category.' using errcode = 'P0216';
  end if;
  select setting_value into v_enabled from public.system_settings
    where setting_key = 'capability_profiles_enabled' and is_public
      and (country is null or country = (select p.country from public.profiles p where p.id = v_user))
    order by (country = (select p.country from public.profiles p where p.id = v_user)) desc nulls last
    limit 1;
  if lower(coalesce(v_enabled,'false')) not in ('true','1') then
    raise exception 'Provider capability profiles are disabled.' using errcode = 'P0216';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':' || p_category_slug, 0));
  select provider_type into v_old from public.provider_category_profiles
    where user_id = v_user and category_slug = p_category_slug for update;
  if v_old is not null and v_old <> p_provider_type then
    raise exception 'Use the identity switch review to change this category.' using errcode = 'P0216';
  end if;
  if v_old = p_provider_type then return; end if;
  insert into public.provider_category_profiles(user_id, category_slug, provider_type)
    values (v_user, p_category_slug, p_provider_type)
    on conflict (user_id, category_slug) do nothing;
  insert into public.audit_logs(user_id,event_type,entity_type,action,new_values)
    values (v_user,'admin_action','provider_category_profile','set_initial_provider_identity',
      jsonb_build_object('category_slug',p_category_slug,'provider_type',p_provider_type));
end;
$$;
revoke all on function private.set_provider_category_type_internal(text,text) from public, anon;
grant execute on function private.set_provider_category_type_internal(text,text) to authenticated;

create or replace function private.save_provider_identity_presentation_internal(
  p_category_slug text, p_identity_type text, p_presentation jsonb
) returns void language plpgsql security definer
set search_path = public, private, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_mode text := coalesce(p_presentation->>'display_mode',
    case when p_identity_type = 'individual' then 'personal' else 'company' end);
  v_name text := btrim(coalesce(p_presentation->>'display_name',''));
  v_rep text := nullif(btrim(coalesce(p_presentation->>'representative_name','')), '');
  v_authorized boolean := coalesce((p_presentation->>'representative_authorized')::boolean,false);
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  if p_identity_type is null or p_identity_type not in ('individual','company') or jsonb_typeof(coalesce(p_presentation,'{}'::jsonb)) <> 'object' then
    raise exception 'Invalid identity presentation.' using errcode='P0216';
  end if;
  if not exists (select 1 from public.provider_category_profiles p
      where p.user_id=v_user and p.category_slug=p_category_slug and p.provider_type=p_identity_type) then
    raise exception 'Choose this identity for the category first.' using errcode='P0216';
  end if;
  if p_identity_type='company' then
    if v_name='' then
      select nullif(btrim(cp.company_name),'') into v_name from public.provider_company_profiles cp
        where cp.user_id=v_user and cp.category_slug=p_category_slug;
    end if;
    if v_name='' or v_name is null then
      raise exception 'Company name is required.' using errcode='P0216';
    end if;
    if v_mode not in ('company','company_with_representative') or
       (v_mode='company_with_representative' and (not v_authorized or v_rep is null)) then
      raise exception 'Representative details and authorization are required.' using errcode='P0216';
    end if;
  else
    v_mode := 'personal';
    if v_name='' then
      select nullif(btrim(p.full_name),'') into v_name from public.profiles p where p.id=v_user;
    end if;
    if v_name='' or v_name is null then raise exception 'A display name is required.' using errcode='P0216'; end if;
    v_rep := null; v_authorized := false;
  end if;
  insert into public.provider_identity_presentations(
    user_id,category_slug,identity_type,display_mode,display_name,representative_name,representative_authorized
  ) values (v_user,p_category_slug,p_identity_type,v_mode,left(v_name,80),left(v_rep,80),v_authorized)
  on conflict(user_id,category_slug,identity_type) do update set
    display_mode=excluded.display_mode, display_name=excluded.display_name,
    representative_name=excluded.representative_name,
    representative_authorized=excluded.representative_authorized, updated_at=now();
end;
$$;
revoke all on function private.save_provider_identity_presentation_internal(text,text,jsonb) from public,anon;
grant execute on function private.save_provider_identity_presentation_internal(text,text,jsonb) to authenticated;

create or replace function public.save_provider_identity_presentation(
  p_category_slug text, p_identity_type text, p_presentation jsonb
) returns void language plpgsql security invoker
set search_path=public,private,pg_temp as $$ begin
  perform private.save_provider_identity_presentation_internal(p_category_slug,p_identity_type,p_presentation);
end; $$;
revoke all on function public.save_provider_identity_presentation(text,text,jsonb) from public,anon;
grant execute on function public.save_provider_identity_presentation(text,text,jsonb) to authenticated;

create or replace function public.get_my_provider_identity(
  p_category_slug text
) returns jsonb language plpgsql stable security invoker
set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_type text; v_presentation jsonb; v_company jsonb;
begin
  select provider_type into v_type from public.provider_category_profiles
    where user_id=v_user and category_slug=p_category_slug;
  select to_jsonb(p) into v_presentation from public.provider_identity_presentations p
    where p.user_id=v_user and p.category_slug=p_category_slug and p.identity_type=v_type;
  select to_jsonb(cp) into v_company from public.provider_company_profiles cp
    where cp.user_id=v_user and cp.category_slug=p_category_slug;
  return jsonb_build_object('provider_type',v_type,'presentation',coalesce(v_presentation,'{}'::jsonb),
    'company_profile',coalesce(v_company,'{}'::jsonb),
    'pending_offers',(select count(*) from public.need_offers o join public.needs_requests n on n.request_id=o.need_id
      where o.offer_maker_id=v_user and n.category_slug=$1 and o.status='pending'),
    'active_capabilities',(select count(*) from public.provider_capabilities pc
      join public.need_capabilities nc on nc.slug=pc.capability_slug where pc.user_id=v_user
      and nc.category_slug=$1 and nc.capability_type='service' and pc.is_active),
    'individual_active_capabilities',(select count(*) from public.provider_capabilities pc
      join public.need_capabilities nc on nc.slug=pc.capability_slug where pc.user_id=v_user
      and nc.category_slug=$1 and nc.capability_type='service' and pc.identity_type='individual' and pc.is_active),
    'company_active_capabilities',(select count(*) from public.provider_capabilities pc
      join public.need_capabilities nc on nc.slug=pc.capability_slug where pc.user_id=v_user
      and nc.category_slug=$1 and nc.capability_type='service' and pc.identity_type='company' and pc.is_active));
end; $$;
revoke all on function public.get_my_provider_identity(text) from public,anon;
grant execute on function public.get_my_provider_identity(text) to authenticated;

create or replace function private.switch_provider_identity_internal(
  p_category_slug text, p_to_identity text, p_presentation jsonb
) returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_user uuid:=auth.uid(); v_from text; v_enabled text; v_deactivated int:=0; v_reactivated int:=0;
  v_pending int:=0; v_active int:=0;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  if p_to_identity is null or p_to_identity not in ('individual','company') then raise exception 'Invalid target identity.' using errcode='P0216'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':' || p_category_slug,0));
  select provider_type into v_from from public.provider_category_profiles
    where user_id=v_user and category_slug=p_category_slug for update;
  if not found or v_from=p_to_identity then raise exception 'Identity switch is unavailable.' using errcode='P0216'; end if;
  select setting_value into v_enabled from public.system_settings
    where setting_key='capability_profiles_enabled' and is_public
    order by (country=(select country from public.profiles where id=v_user)) desc nulls last limit 1;
  if lower(coalesce(v_enabled,'false')) not in ('true','1') then raise exception 'Provider profiles are disabled.' using errcode='P0216'; end if;
  if (select count(*) from public.audit_logs a where a.user_id=v_user and a.entity_type='provider_identity'
      and a.action='switch' and a.new_values->>'category_slug'=p_category_slug
      and a.created_at>now()-interval '24 hours')>=5 then
    raise exception 'You have reached the identity switch limit for this category.' using errcode='P0216';
  end if;
  if not exists(select 1 from public.need_categories where slug=p_category_slug and is_active) then
    raise exception 'Provider category is unavailable.' using errcode='P0216';
  end if;
  update public.provider_category_profiles set provider_type=p_to_identity, identity_changed_at=now(), updated_at=now()
    where user_id=v_user and category_slug=p_category_slug;
  -- The presentation helper verifies the category's selected identity. Set it
  -- first; the transaction still rolls back both changes together on error.
  perform private.save_provider_identity_presentation_internal(p_category_slug,p_to_identity,p_presentation);
  update public.provider_capabilities pc set is_active=false
    from public.need_capabilities nc where nc.slug=pc.capability_slug and pc.user_id=v_user
      and nc.category_slug=p_category_slug and nc.capability_type='service'
      and pc.identity_type=v_from and pc.is_active;
  get diagnostics v_deactivated=row_count;
  update public.provider_capabilities pc set is_active=true
    from public.need_capabilities nc where nc.slug=pc.capability_slug and pc.user_id=v_user
      and nc.category_slug=p_category_slug and nc.capability_type='service'
      and pc.identity_type=p_to_identity;
  select count(*) into v_reactivated from public.provider_capabilities pc
    join public.need_capabilities nc on nc.slug=pc.capability_slug
    where pc.user_id=v_user and nc.category_slug=p_category_slug
      and nc.capability_type='service' and pc.identity_type=p_to_identity and pc.is_active;

  select count(*) into v_pending from public.need_offers o
    join public.needs_requests n on n.request_id=o.need_id
    where o.offer_maker_id=v_user and n.category_slug=p_category_slug and o.status='pending';
  select count(*) into v_active from public.provider_capabilities pc
    join public.need_capabilities nc on nc.slug=pc.capability_slug
    where pc.user_id=v_user and nc.category_slug=p_category_slug and nc.capability_type='service' and pc.is_active;
  insert into public.audit_logs(user_id,event_type,entity_type,action,old_values,new_values)
    values(v_user,'admin_action','provider_identity','switch',
      jsonb_build_object('category_slug',p_category_slug,'from',v_from),
      jsonb_build_object('category_slug',p_category_slug,'to',p_to_identity,
        'deactivated',v_deactivated,'reactivated',v_reactivated,'pending_offers',v_pending,
        'representative_authorized',coalesce((p_presentation->>'representative_authorized')::boolean,false)));
  return jsonb_build_object('provider_type',p_to_identity,'deactivated',v_deactivated,
    'reactivated',v_reactivated,'pending_offers',v_pending,'active_capabilities',v_active);
end; $$;
revoke all on function private.switch_provider_identity_internal(text,text,jsonb) from public,anon;
grant execute on function private.switch_provider_identity_internal(text,text,jsonb) to authenticated;
create or replace function public.switch_provider_identity(
  p_category_slug text,p_to_identity text,p_presentation jsonb
) returns jsonb language plpgsql security invoker
set search_path=public,private,pg_temp as $$ begin
  return private.switch_provider_identity_internal(p_category_slug,p_to_identity,p_presentation);
end; $$;
revoke all on function public.switch_provider_identity(text,text,jsonb) from public,anon;
grant execute on function public.switch_provider_identity(text,text,jsonb) to authenticated;

create or replace function private.snapshot_need_offer_provider_identity()
returns trigger language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare v_need record; v_type text; v_slug text; v_display text; v_kind text;
begin
  if tg_op='UPDATE' then
    new.provider_identity_type:=old.provider_identity_type;
    new.provider_display_name:=old.provider_display_name;
    return new;
  end if;
  -- Serialize offer creation with category identity switches. An offer is
  -- either included in the pending count before the switch or uses the new
  -- identity after it commits.
  perform pg_advisory_xact_lock(hashtextextended(new.offer_maker_id::text || ':' ||
    (select n.category_slug from public.needs_requests n where n.request_id=new.need_id),0));
  select request_id,category_slug,capability_slug into v_need from public.needs_requests where request_id=new.need_id;
  if not found then return new; end if;
  select provider_type into v_type from public.provider_category_profiles
    where user_id=new.offer_maker_id and category_slug=v_need.category_slug;
  if v_need.capability_slug is not null then
    v_slug:=v_need.capability_slug;
    select capability_type into v_kind from public.need_capabilities where slug=v_slug;
    if v_kind='service' and not exists(select 1 from public.provider_capabilities pc
      where pc.user_id=new.offer_maker_id and pc.capability_slug=v_slug and pc.is_active
        and pc.identity_type=v_type) then
      raise exception 'An active service under your current identity is required to make this offer.' using errcode='P0216';
    end if;
  else
    if not exists(select 1 from public.provider_capabilities pc join public.need_capabilities nc on nc.slug=pc.capability_slug
      where pc.user_id=new.offer_maker_id and nc.category_slug=v_need.category_slug and pc.is_active
        and (nc.capability_type='work' or pc.identity_type=v_type)) then
      raise exception 'An active capability under your current identity is required to make this offer.' using errcode='P0216';
    end if;
  end if;
  if v_kind='work' then
    v_type:='individual';
  end if;
  new.provider_identity_type:=v_type;
  select case when p.display_mode='company_with_representative'
    then p.display_name || ' · Represented by ' || p.representative_name
    else p.display_name end
    into v_display from public.provider_identity_presentations p
    where p.user_id=new.offer_maker_id and p.category_slug=v_need.category_slug and p.identity_type=v_type;
  if v_display is null then
    select case when v_type='company' then cp.company_name else pr.full_name end into v_display
    from public.profiles pr
    left join public.provider_company_profiles cp
      on cp.user_id=pr.id and cp.category_slug=v_need.category_slug
    where pr.id=new.offer_maker_id;
  end if;
  new.provider_display_name:=nullif(v_display,'');
  return new;
end; $$;
revoke all on function private.snapshot_need_offer_provider_identity() from public,anon,authenticated;
drop trigger if exists trg_provider_identity_offer_snapshot on public.need_offers;
create trigger trg_provider_identity_offer_snapshot before insert or update on public.need_offers
  for each row execute function private.snapshot_need_offer_provider_identity();

create or replace function private.snapshot_need_reveal_provider_identity()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if tg_op='UPDATE' then
    new.provider_identity_type:=old.provider_identity_type;
    new.provider_display_name:=old.provider_display_name;
    return new;
  end if;
  select o.provider_identity_type,o.provider_display_name into new.provider_identity_type,new.provider_display_name
    from public.need_offers o where o.id=new.offer_id;
  return new;
end; $$;
revoke all on function private.snapshot_need_reveal_provider_identity() from public,anon,authenticated;
drop trigger if exists trg_snapshot_need_reveal_provider_identity on public.need_contact_reveals;
create trigger trg_snapshot_need_reveal_provider_identity before insert or update on public.need_contact_reveals
  for each row execute function private.snapshot_need_reveal_provider_identity();

create or replace function public.get_public_need_offer_identities(p_need_id uuid)
returns table(offer_id uuid,provider_identity_type text,provider_display_name text)
language sql stable security definer set search_path=public,pg_temp as $$
  select o.id,o.provider_identity_type,o.provider_display_name from public.need_offers o
  where o.need_id=p_need_id and o.status in ('pending','accepted')
    and exists(select 1 from public.needs_requests n where n.request_id=o.need_id
      and n.status in ('active','matched','contracted','completed')
      and (n.requester_id=auth.uid() or o.offer_maker_id=auth.uid()));
$$;
revoke all on function public.get_public_need_offer_identities(uuid) from public,anon;
grant execute on function public.get_public_need_offer_identities(uuid) to authenticated;

-- Public presentation lookup for existing provider/listing clients. The input
-- provider ID is already available to authenticated listing clients; the result
-- contains only the approved name and identity label, never private profile data.
create or replace function public.get_public_provider_identity(
  p_provider_user_id uuid,p_category_slug text
) returns table(identity_type text,display_name text)
language sql stable security definer set search_path=public,private,pg_temp as $$
  select pcp.provider_type,
    coalesce(
      case when ip.display_mode='company_with_representative'
        then ip.display_name || ' · Represented by ' || ip.representative_name
        else ip.display_name end,
      case when pcp.provider_type='company' then cp.company_name else pr.full_name end
    )
  from public.provider_category_profiles pcp
  join public.profiles pr on pr.id=pcp.user_id
  left join public.provider_identity_presentations ip
    on ip.user_id=pcp.user_id and ip.category_slug=pcp.category_slug and ip.identity_type=pcp.provider_type
  left join public.provider_company_profiles cp
    on cp.user_id=pcp.user_id and cp.category_slug=pcp.category_slug
  where pcp.user_id=p_provider_user_id and pcp.category_slug=p_category_slug
    and exists(select 1 from public.provider_capabilities pc
      join public.need_capabilities nc on nc.slug=pc.capability_slug
      where pc.user_id=pcp.user_id and nc.category_slug=pcp.category_slug
        and nc.capability_type='service' and pc.identity_type=pcp.provider_type and pc.is_active)
  limit 1;
$$;
revoke all on function public.get_public_provider_identity(uuid,text) from public,anon;
grant execute on function public.get_public_provider_identity(uuid,text) to authenticated;

commit;

-- Historical offer/reveal snapshots remain null unless already captured.
-- Rollback: drop the new functions/triggers/view-like RPC, columns and table;
-- restore the previous provider type setter, then remove identity_type.
