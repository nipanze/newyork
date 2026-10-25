-- Extend existing qualification claims and company verification submissions
-- to support user-managed evidence documents without introducing new tables.
begin;

update public.role_qualifications
set is_evidence = true
where (role_slug, slug) in (
  ('developer', 'cloud_certification_aws_azure_gcp'),
  ('project_manager', 'agile_scrum_certified'),
  ('marketer_specialist', 'google_ads_meta_certified'),
  ('accountant_finance_officer', 'practising_certificate'),
  ('lawyer_legal_officer', 'bar_admission_practising_certificate'),
  ('engineer', 'registered_with_engineers_board'),
  ('architect_designer', 'registered_architect'),
  ('teacher_tutor', 'teaching_certificate_degree'),
  ('teacher_tutor', 'registered_with_teaching_board'),
  ('trainer_instructor', 'trade_certificate'),
  ('placement_coordinator', 'counselling_certificate'),
  ('event_manager_planner', 'event_planning_certificate'),
  ('caterer_chef', 'food_handler_certificate'),
  ('photographer_videographer', 'drone_licence'),
  ('makeup_artist', 'cosmetology_certificate'),
  ('makeup_artist', 'hygiene_certification'),
  ('hair_stylist', 'cosmetology_certificate'),
  ('hair_stylist', 'salon_licence'),
  ('salon_studio_manager', 'business_licence'),
  ('site_manager', 'registered_with_engineers_contractors_board'),
  ('site_manager', 'safety_certification_osha'),
  ('foreman_supervisor', 'trade_test_certificate'),
  ('skilled_tradesperson', 'licence_electrical_plumbing'),
  ('surveyor', 'registered_surveyor'),
  ('solar_electrical_technician', 'electrical_licence'),
  ('solar_electrical_technician', 'solar_installer_certificate'),
  ('borehole_water_technician', 'water_technician_certificate'),
  ('energy_engineer', 'registered_engineer'),
  ('driver', 'valid_driving_licence_class'),
  ('driver', 'defensive_driving_certificate'),
  ('fleet_operations_manager', 'transport_licence'),
  ('dispatcher_coordinator', 'customs_clearing_licence'),
  ('machine_operator', 'operator_licence_certificate'),
  ('machine_operator', 'safety_osha_certificate'),
  ('equipment_mechanic', 'mechanic_trade_certificate'),
  ('site_supervisor', 'safety_certification'),
  ('veterinary_livestock_officer', 'veterinary_licence'),
  ('veterinary_livestock_officer', 'vaccination_certification'),
  ('farm_worker_operator', 'tractor_licence'),
  ('farm_worker_operator', 'pesticide_handling_certificate'),
  ('clearing_customs_agent', 'customs_clearing_licence'),
  ('travel_agent_consultant', 'iata_certification'),
  ('travel_agent_consultant', 'travel_agency_licence'),
  ('tour_guide', 'tourism_board_guide_licence'),
  ('tour_guide', 'first_aid_certificate'),
  ('driver_guide', 'valid_driving_licence_class'),
  ('driver_guide', 'tourism_licence'),
  ('house_help', 'national_id'),
  ('nanny', 'national_id'),
  ('nanny', 'police_clearance'),
  ('nanny', 'first_aid'),
  ('home_cook', 'food_handler_certificate'),
  ('home_carer', 'caregiving_certificate'),
  ('home_carer', 'first_aid'),
  ('home_carer', 'national_id'),
  ('driving_instructor', 'instructor_licence'),
  ('driving_instructor', 'valid_driving_licence'),
  ('massage_therapist', 'massage_therapy_certificate'),
  ('massage_therapist', 'hygiene_certification'),
  ('spa_therapist', 'cosmetology_spa_certificate'),
  ('spa_therapist', 'hygiene_certification'),
  ('spa_manager', 'business_licence'),
  ('nurse', 'council_registration'),
  ('nurse', 'diploma_degree'),
  ('nurse', 'practising_certificate'),
  ('doctor', 'council_registration'),
  ('doctor', 'medical_degree'),
  ('doctor', 'practising_certificate'),
  ('clinician', 'council_registration'),
  ('clinician', 'diploma'),
  ('clinician', 'practising_licence'),
  ('medical_specialist', 'specialist_registration'),
  ('medical_specialist', 'postgraduate_degree'),
  ('medical_specialist', 'medical_council_registration'),
  ('optometrist', 'optometry_registration'),
  ('optometrist', 'diploma_degree'),
  ('optometrist', 'practising_certificate'),
  ('dentist', 'dental_council_registration'),
  ('dentist', 'bds'),
  ('dentist', 'practising_certificate'),
  ('pharmacist', 'pharmacy_board_registration'),
  ('pharmacist', 'degree'),
  ('pharmacist', 'practising_certificate'),
  ('lab_technician', 'lab_council_registration'),
  ('lab_technician', 'diploma'),
  ('physiotherapist', 'physiotherapy_registration'),
  ('physiotherapist', 'degree'),
  ('physiotherapist', 'practising_certificate'),
  ('counsellor', 'professional_registration'),
  ('counsellor', 'degree'),
  ('nursing_assistant', 'assistant_certificate'),
  ('nursing_assistant', 'first_aid'),
  ('nursing_assistant', 'national_id'),
  ('hiv_counsellor', 'counselling_certificate'),
  ('hiv_counsellor', 'hiv_training'),
  ('hiv_counsellor', 'facility_authorisation'),
  ('hiv_counsellor', 'national_id'),
  ('angel_investor', 'identity_verification'),
  ('angel_investor', 'investment_track_record'),
  ('duwah_practitioner', 'endorsement'),
  ('ceremony_officiant', 'endorsement'),
  ('traditional_healer', 'association_registration'),
  ('research_mentor', 'degree_in_field'),
  ('research_mentor', 'masters_phd'),
  ('driver', 'certificate_good_conduct')
);

alter table public.provider_company_verification_submissions
  add column if not exists id uuid,
  add column if not exists file_name text;

update public.provider_company_verification_submissions
set id = gen_random_uuid()
where id is null;

update public.provider_company_verification_submissions
set file_name = regexp_replace(file_path, '^.*/', '')
where file_name is null or btrim(file_name) = '';

alter table public.provider_company_verification_submissions
  alter column id set default gen_random_uuid(),
  alter column id set not null,
  alter column file_name set default '',
  alter column file_name set not null;

do $$
declare
  v_primary_key text;
begin
  select constraint_row.conname
    into v_primary_key
  from pg_constraint constraint_row
  where constraint_row.conrelid =
      'public.provider_company_verification_submissions'::regclass
    and constraint_row.contype = 'p';

  if v_primary_key is not null then
    execute format(
      'alter table public.provider_company_verification_submissions drop constraint %I',
      v_primary_key
    );
  end if;
end;
$$;

alter table public.provider_company_verification_submissions
  add constraint provider_company_verification_submissions_pkey primary key (id);

alter table public.provider_company_verification_submissions
  drop constraint if exists provider_company_verification_submissions_document_type_check;
alter table public.provider_company_verification_submissions
  add constraint provider_company_verification_submissions_document_type_check
  check (document_type in (
    'business_registration',
    'business_licence',
    'certificate',
    'other'
  ));

create or replace function private.cleanup_provider_company_document_object()
returns trigger
language plpgsql
security definer
set search_path = public, private, storage, pg_temp
as $$
begin
  if tg_op = 'DELETE' or old.file_path is distinct from new.file_path then
    delete from storage.objects
    where bucket_id = 'provider-evidence'
      and name = old.file_path
      and owner_id = old.user_id::text;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cleanup_provider_company_document_object
  on public.provider_company_verification_submissions;
create trigger trg_cleanup_provider_company_document_object
  before update of file_path or delete
  on public.provider_company_verification_submissions
  for each row execute function private.cleanup_provider_company_document_object();

create or replace function public.save_provider_company_document(
  p_category_slug text,
  p_document_type text,
  p_file_path text,
  p_file_name text,
  p_submission_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public, private, storage, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_submission_id uuid := p_submission_id;
  v_size bigint;
  v_mime text;
  v_country text;
  v_enabled text;
  v_existing_status text;
  v_is_update boolean := false;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_document_type not in (
    'business_registration', 'business_licence', 'certificate', 'other'
  ) or nullif(btrim(p_file_name), '') is null
     or length(p_file_name) > 255 then
    raise exception 'Company document details are invalid.' using errcode = 'P0204';
  end if;
  if not exists (
    select 1 from public.provider_category_profiles pcp
    where pcp.user_id = v_user
      and pcp.category_slug = p_category_slug
      and pcp.provider_type = 'company'
  ) then
    raise exception 'Choose Company / Organization for this category first.'
      using errcode = 'P0202';
  end if;
  if not exists (
    select 1 from public.need_categories c
    where c.slug = p_category_slug and c.is_active
  ) then
    raise exception 'This provider category is not active.' using errcode = 'P0201';
  end if;
  select country into v_country
  from public.profiles
  where id = v_user;
  select setting_value into v_enabled
  from public.system_settings
  where setting_key = 'capability_profiles_enabled'
    and is_public
    and (country = v_country or country is null)
  order by (country = v_country) desc nulls last
  limit 1;
  if lower(coalesce(v_enabled, 'false')) not in ('true', '1') then
    raise exception 'Provider services are not enabled in your market.'
      using errcode = 'P0202';
  end if;
  if p_file_path is null
     or position('..' in p_file_path) > 0
     or p_file_path not like
       'evidence/' || v_user::text || '/' || p_category_slug ||
       '/company/' || p_document_type || '/%' then
    raise exception 'Company document file path is invalid.' using errcode = 'P0205';
  end if;
  select (o.metadata->>'size')::bigint,
         lower(coalesce(o.metadata->>'mimetype', ''))
    into v_size, v_mime
  from storage.objects o
  where o.bucket_id = 'provider-evidence'
    and o.name = p_file_path
    and o.owner_id = v_user::text;
  if not found or v_size is null or v_size < 1 or v_size > 5242880
     or v_mime not in ('image/jpeg', 'image/png', 'application/pdf') then
    raise exception 'Company evidence must be an owned JPG, PNG, or PDF up to 5 MB.'
      using errcode = 'P0205';
  end if;

  if v_submission_id is null then
    perform 1
    from public.profiles
    where id = v_user
    for update;

    select id into v_submission_id
    from public.provider_company_verification_submissions
    where user_id = v_user
      and category_slug = p_category_slug
      and document_type = p_document_type
    order by updated_at desc, created_at desc, id desc
    limit 1
    for update;
    v_is_update := found;
  else
    v_is_update := true;
  end if;

  if v_submission_id is not null then
    select status into v_existing_status
    from public.provider_company_verification_submissions
    where id = v_submission_id
      and user_id = v_user
      and category_slug = p_category_slug
    for update;
    if not found then
      raise exception 'Company document was not found.' using errcode = 'P0212';
    end if;
    update public.provider_company_verification_submissions
    set document_type = p_document_type,
        file_path = p_file_path,
        file_name = p_file_name,
        status = 'pending',
        reject_reason = null,
        reviewed_by = null,
        reviewed_at = null,
        created_at = now(),
        updated_at = now()
    where id = v_submission_id;
  else
    insert into public.provider_company_verification_submissions(
      user_id, category_slug, document_type, file_path, file_name, status,
      reject_reason, reviewed_by, reviewed_at
    ) values (
      v_user, p_category_slug, p_document_type, p_file_path, p_file_name,
      'pending', null, null, null
    )
    returning id into v_submission_id;
  end if;

  insert into public.audit_logs(
    user_id, event_type, entity_type, action, new_values
  ) values (
    v_user, 'admin_action', 'provider_company_verification',
    case when v_is_update then 'replace_company_document'
      else 'submit_company_document' end,
    jsonb_build_object(
      'submission_id', v_submission_id,
      'category_slug', p_category_slug,
      'document_type', p_document_type,
      'file_name', p_file_name
    )
  );
  return v_submission_id;
end;
$$;
revoke all on function public.save_provider_company_document(text, text, text, text, uuid)
  from public, anon;
grant execute on function public.save_provider_company_document(text, text, text, text, uuid)
  to authenticated;

create or replace function public.delete_provider_company_document(
  p_submission_id uuid
) returns void
language plpgsql
security definer
set search_path = public, private, storage, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_row public.provider_company_verification_submissions%rowtype;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select * into v_row
  from public.provider_company_verification_submissions
  where id = p_submission_id and user_id = v_user
  for update;
  if not found then
    raise exception 'Company document was not found.' using errcode = 'P0212';
  end if;
  if v_row.status = 'approved' then
    raise exception 'Approved documents cannot be removed. Replace the document to request a new review.'
      using errcode = 'P0206';
  end if;
  insert into public.audit_logs(
    user_id, event_type, entity_type, action, old_values
  ) values (
    v_user, 'admin_action', 'provider_company_verification',
    'remove_company_document',
    jsonb_build_object(
      'submission_id', v_row.id,
      'category_slug', v_row.category_slug,
      'document_type', v_row.document_type,
      'file_name', v_row.file_name
    )
  );
  delete from public.provider_company_verification_submissions
  where id = v_row.id;
end;
$$;
revoke all on function public.delete_provider_company_document(uuid)
  from public, anon;
grant execute on function public.delete_provider_company_document(uuid)
  to authenticated;

create or replace function public.admin_review_provider_company_document(
  p_submission_id uuid,
  p_action text,
  p_reject_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_admin uuid := auth.uid();
  v_row public.provider_company_verification_submissions%rowtype;
begin
  if not private.is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;
  if p_action not in ('approve', 'reject') then
    raise exception 'Invalid company verification action.' using errcode = 'P0204';
  end if;
  if p_action = 'reject' and nullif(btrim(p_reject_reason), '') is null then
    raise exception 'A rejection reason is required.' using errcode = 'P0204';
  end if;
  update public.provider_company_verification_submissions
  set status = case when p_action = 'approve' then 'approved' else 'rejected' end,
      reject_reason = case when p_action = 'reject'
        then left(btrim(p_reject_reason), 300) else null end,
      reviewed_by = v_admin,
      reviewed_at = now(),
      updated_at = now()
  where id = p_submission_id
  returning * into v_row;
  if not found then
    raise exception 'Company document was not found.' using errcode = 'P0212';
  end if;
  insert into public.audit_logs(
    user_id, event_type, entity_type, action, old_values, new_values
  ) values (
    v_admin, 'admin_action', 'provider_company_verification',
    'review_company_document', null,
    jsonb_build_object(
      'provider_user_id', v_row.user_id,
      'submission_id', v_row.id,
      'category_slug', v_row.category_slug,
      'document_type', v_row.document_type,
      'action', p_action,
      'reject_reason', p_reject_reason,
      'reviewed_at', now()
    )
  );
  return true;
end;
$$;
revoke all on function public.admin_review_provider_company_document(uuid, text, text)
  from public, anon;
grant execute on function public.admin_review_provider_company_document(uuid, text, text)
  to authenticated;

create or replace function public.submit_provider_company_verification(
  p_category_slug text,
  p_document_type text,
  p_file_path text
) returns void
language plpgsql
security definer
set search_path = public, private, storage, pg_temp
as $$
begin
  if p_document_type not in ('business_registration', 'business_licence') then
    raise exception 'Company verification document type is invalid.'
      using errcode = 'P0204';
  end if;
  perform public.save_provider_company_document(
    p_category_slug,
    p_document_type,
    p_file_path,
    regexp_replace(p_file_path, '^.*/', ''),
    null
  );
end;
$$;
revoke all on function public.submit_provider_company_verification(text, text, text)
  from public, anon;
grant execute on function public.submit_provider_company_verification(text, text, text)
  to authenticated;

create or replace function public.admin_review_provider_company_verification(
  p_user_id uuid,
  p_category_slug text,
  p_document_type text,
  p_action text,
  p_reject_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_submission_id uuid;
  v_count integer;
begin
  if not private.is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;
  select count(*), (array_agg(id))[1] into v_count, v_submission_id
  from public.provider_company_verification_submissions
  where user_id = p_user_id
    and category_slug = p_category_slug
    and document_type = p_document_type
    and status = 'pending';
  if v_count <> 1 then
    raise exception 'Review the individual company document by submission id.'
      using errcode = 'P0212';
  end if;
  return public.admin_review_provider_company_document(
    v_submission_id, p_action, p_reject_reason
  );
end;
$$;
revoke all on function public.admin_review_provider_company_verification(uuid, text, text, text, text)
  from public, anon;
grant execute on function public.admin_review_provider_company_verification(uuid, text, text, text, text)
  to authenticated;

create or replace view public.v_my_capability_status
with (security_invoker = true)
as
with latest_rejection as (
  select distinct on (e.provider_capability_id)
    e.provider_capability_id, e.reject_reason, e.reviewed_at
  from public.provider_capability_evidence e
  where e.status = 'rejected'
  order by e.provider_capability_id, e.reviewed_at desc nulls last, e.created_at desc
),
evidence_summary as (
  select
    e.provider_capability_id,
    count(*) filter (where e.status = 'pending') as pending_count,
    count(*) filter (where e.status = 'approved') as approved_count,
    count(*) filter (where e.status = 'rejected') as rejected_count,
    count(*) filter (where e.status = 'expired') as expired_count
  from public.provider_capability_evidence e
  group by e.provider_capability_id
),
qualification_summary as (
  select
    claim.provider_capability_id,
    jsonb_agg(
      jsonb_build_object(
        'role_slug', claim.role_slug,
        'qualification_slug', claim.qualification_slug,
        'qualification_name', rq.name,
        'is_evidence', rq.is_evidence,
        'status', case
          when claim.status = 'verified'
               and claim.expires_at is not null
               and claim.expires_at <= now() then 'expired'
          else claim.status
        end,
        'has_evidence', claim.evidence_object_path is not null,
        'reject_reason', claim.reject_reason,
        'verified_at', claim.reviewed_at
      )
      order by claim.role_slug, claim.qualification_slug
    ) as claims
  from public.provider_role_qualification_claims claim
  join public.role_qualifications rq
    on rq.role_slug = claim.role_slug
   and rq.slug = claim.qualification_slug
  where claim.is_claimed
  group by claim.provider_capability_id
)
select
  pc.id as provider_capability_id,
  pc.user_id,
  pc.capability_slug,
  nc.name as capability_name,
  nc.category_slug,
  cat.name as category_name,
  cat.icon as category_icon,
  pc.verification_level,
  pc.metadata,
  case
    when pc.verification_level = 'provider_verified' then 'provider_verified'
    when coalesce(es.pending_count, 0) > 0 then 'pending_review'
    when coalesce(es.rejected_count, 0) > 0 then 'rejected'
    when coalesce(es.expired_count, 0) > 0 then 'expired'
    else 'self_declared'
  end as capability_status,
  coalesce(es.pending_count, 0)::int as pending_evidence_count,
  coalesce(es.approved_count, 0)::int as approved_evidence_count,
  coalesce(es.rejected_count, 0)::int as rejected_evidence_count,
  coalesce(es.expired_count, 0)::int as expired_evidence_count,
  lr.reject_reason as latest_reject_reason,
  pc.verified_by,
  pc.verified_at,
  pc.created_at,
  nc.capability_type,
  coalesce(qs.claims, '[]'::jsonb) as role_qualification_claims
from public.provider_capabilities pc
join public.need_capabilities nc on nc.slug = pc.capability_slug
join public.need_categories cat on cat.slug = nc.category_slug
left join evidence_summary es on es.provider_capability_id = pc.id
left join latest_rejection lr on lr.provider_capability_id = pc.id
left join qualification_summary qs on qs.provider_capability_id = pc.id
where pc.user_id = auth.uid() or private.is_admin();
grant select on public.v_my_capability_status to authenticated;

create or replace view public.v_my_capability_policy_status
with (security_invoker = true)
as
select
  v.provider_capability_id,
  v.user_id,
  v.capability_slug,
  v.capability_name,
  v.category_slug,
  v.category_name,
  v.category_icon,
  v.verification_level,
  v.metadata,
  v.capability_status,
  v.pending_evidence_count,
  v.approved_evidence_count,
  v.rejected_evidence_count,
  v.expired_evidence_count,
  v.latest_reject_reason,
  v.verified_by,
  v.verified_at,
  v.created_at,
  v.capability_type,
  nc.verification_policy,
  pc.is_active and private.provider_capability_is_eligible(pc.id) as is_active,
  v.role_qualification_claims
from public.v_my_capability_status v
join public.provider_capabilities pc on pc.id = v.provider_capability_id
join public.need_capabilities nc on nc.slug = pc.capability_slug;
grant select on public.v_my_capability_policy_status to authenticated;

create or replace function public.remove_provider_role_qualification_evidence(
  p_provider_capability_id uuid,
  p_role_slug text,
  p_qualification_slug text
) returns void
language plpgsql
security definer
set search_path = public, private, storage, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_claim public.provider_role_qualification_claims%rowtype;
begin
  if v_user is null then
    raise exception 'Not authenticated.' using errcode = '42501';
  end if;
  select claim.* into v_claim
  from public.provider_role_qualification_claims claim
  join public.provider_capabilities pc
    on pc.id = claim.provider_capability_id
  where claim.provider_capability_id = p_provider_capability_id
    and pc.user_id = v_user
    and claim.role_slug = p_role_slug
    and claim.qualification_slug = p_qualification_slug
    and claim.is_claimed
  for update of claim;
  if not found or v_claim.evidence_object_path is null then
    raise exception 'Qualification evidence was not found.' using errcode = 'P0212';
  end if;
  if v_claim.status = 'verified'
     and (v_claim.expires_at is null or v_claim.expires_at > now()) then
    raise exception 'Approved qualification evidence cannot be removed.'
      using errcode = 'P0206';
  end if;
  delete from storage.objects
  where bucket_id = 'provider-evidence'
    and name = v_claim.evidence_object_path;
  update public.provider_role_qualification_claims
  set evidence_object_path = null,
      status = 'self_declared',
      reject_reason = null,
      reviewed_by = null,
      reviewed_at = null,
      expires_at = null,
      updated_at = now()
  where id = v_claim.id;
  insert into public.audit_logs(
    user_id, event_type, entity_type, action, old_values
  ) values (
    v_user, 'admin_action', 'provider_role_qualification_claim',
    'remove_qualification_evidence',
    jsonb_build_object(
      'provider_capability_id', p_provider_capability_id,
      'role_slug', p_role_slug,
      'qualification_slug', p_qualification_slug
    )
  );
end;
$$;
revoke all on function public.remove_provider_role_qualification_evidence(uuid, text, text)
  from public, anon;
grant execute on function public.remove_provider_role_qualification_evidence(uuid, text, text)
  to authenticated;

commit;
