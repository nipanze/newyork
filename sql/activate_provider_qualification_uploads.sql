-- Repair qualification evidence submissions for work profiles.
--
-- The app stores one role per provider_capabilities row using root-level
-- role_id and qualification_ids fields. Older rows may store a `roles` array.
-- This function supports both shapes, refreshes the trigger, and backfills
-- both formats so submitted evidence can find its qualification claim.
-- Safe to rerun. Run in the Supabase SQL Editor for the same project as the app.

begin;

create or replace function private.sync_provider_role_qualification_claims()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_category_slug text;
  v_roles jsonb;
  v_role jsonb;
  v_role_slug text;
  v_qualifications jsonb;
  v_qualification_slug text;
begin
  select nc.category_slug
  into v_category_slug
  from public.need_capabilities nc
  where nc.slug = new.capability_slug;

  v_roles := case
    when jsonb_typeof(coalesce(new.metadata, '{}'::jsonb)->'roles') = 'array'
      then coalesce(new.metadata, '{}'::jsonb)->'roles'
    when jsonb_typeof(coalesce(new.metadata, '{}'::jsonb)->'role_id') = 'string'
      then jsonb_build_array(coalesce(new.metadata, '{}'::jsonb))
    else '[]'::jsonb
  end;

  update public.provider_role_qualification_claims
  set is_claimed = false,
      updated_at = now()
  where provider_capability_id = new.id
    and is_claimed;

  for v_role in select value from jsonb_array_elements(v_roles)
  loop
    v_role_slug := nullif(btrim(v_role->>'role_id'), '');
    if v_role_slug is null or not exists (
      select 1
      from public.capability_roles cr
      where cr.slug = v_role_slug
        and cr.is_active
        and (
          cr.capability_slug = new.capability_slug
          or (cr.capability_slug is null and cr.category_slug = v_category_slug)
        )
    ) then
      continue;
    end if;

    v_qualifications := case
      when jsonb_typeof(v_role->'qualification_ids') = 'array'
        then v_role->'qualification_ids'
      else '[]'::jsonb
    end;

    for v_qualification_slug in
      select jsonb_array_elements_text(v_qualifications)
    loop
      if exists (
        select 1
        from public.role_qualifications rq
        where rq.role_slug = v_role_slug
          and rq.slug = v_qualification_slug
      ) then
        insert into public.provider_role_qualification_claims
          (provider_capability_id, role_slug, qualification_slug, is_claimed)
        values (new.id, v_role_slug, v_qualification_slug, true)
        on conflict (provider_capability_id, role_slug, qualification_slug)
        do update set
          is_claimed = true,
          updated_at = now();
      end if;
    end loop;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_sync_provider_role_qualification_claims
  on public.provider_capabilities;
create trigger trg_sync_provider_role_qualification_claims
  after insert or update of metadata, capability_slug
  on public.provider_capabilities
  for each row
  execute function private.sync_provider_role_qualification_claims();

-- Re-fire the trigger for existing profiles in either metadata shape.
update public.provider_capabilities
set metadata = metadata
where metadata ? 'roles'
   or metadata ? 'role_id';

commit;
