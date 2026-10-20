-- Capability-level provider proof rules by provider type.
-- Apply after patch_provider_services_work_profiles.sql and
-- patch_provider_category_type.sql. Safe to rerun.
begin;

alter table public.verification_requirements
  add column if not exists provider_type text not null default 'both';

alter table public.provider_capability_evidence
  add column if not exists provider_type text not null default 'both';
alter table public.provider_capability_evidence
  drop constraint if exists provider_capability_evidence_provider_type_check;
alter table public.provider_capability_evidence
  add constraint provider_capability_evidence_provider_type_check
    check (provider_type in ('both', 'individual', 'company'));

alter table public.verification_requirements
  drop constraint if exists verification_requirements_provider_type_check;
alter table public.verification_requirements
  add constraint verification_requirements_provider_type_check
    check (provider_type in ('both', 'individual', 'company'));

-- Replace legacy uniqueness so a capability may have separate company and
-- individual requirements while preserving all existing rows as `both`.
alter table public.verification_requirements
  drop constraint if exists verification_requirements_scope_type_scope_id_key;
create unique index if not exists verification_requirements_scope_type_scope_id_provider_type_uidx
  on public.verification_requirements(scope_type, scope_id, provider_type);

comment on column public.verification_requirements.provider_type is
  'Provider type this evidence rule applies to: both, individual, or company.';

-- Do not make every listing require a licence. These are service-specific
-- gates. General categories continue to use self-declared status and optional
-- portfolio/references. Company rules require organization evidence and (when
-- relevant) proof of named qualified staff; individual rules require the
-- provider''s own credential. Expiring licences are reviewed annually.
insert into public.verification_requirements (
  scope_type, scope_id, provider_type, identity_required, phone_required,
  provider_verification_required, evidence_requirements, required_evidence,
  expires_after_days, is_active
) values
  ('capability','legal_services','individual',true,false,true,
   '["practising_certificate"]'::jsonb,array['practising_certificate'],365,true),
  ('capability','legal_services','company',true,false,true,
   '["law_firm_approval","named_advocate_practising_certificate"]'::jsonb,
   array['law_firm_approval','named_advocate_practising_certificate'],365,true),
  ('capability','company_registration','individual',true,false,true,
   '["company_secretarial_or_legal_practice_credential"]'::jsonb,
   array['company_secretarial_or_legal_practice_credential'],365,true),
  ('capability','company_registration','company',true,false,true,
   '["business_registration","named_qualified_company_secretary_or_advocate"]'::jsonb,
   array['business_registration','named_qualified_company_secretary_or_advocate'],365,true),
  ('capability','accounting_tax','individual',true,false,true,
   '["icpau_practising_certificate"]'::jsonb,array['icpau_practising_certificate'],365,true),
  ('capability','accounting_tax','company',true,false,true,
   '["icpau_firm_licence","named_accountant_practising_certificate"]'::jsonb,
   array['icpau_firm_licence','named_accountant_practising_certificate'],365,true),
  ('capability','architecture','individual',true,false,true,
   '["architect_registration_and_current_practising_certificate"]'::jsonb,
   array['architect_registration_and_current_practising_certificate'],365,true),
  ('capability','architecture','company',true,false,true,
   '["architecture_firm_registration","named_architect_practising_certificate"]'::jsonb,
   array['architecture_firm_registration','named_architect_practising_certificate'],365,true),
  ('capability','engineering','individual',true,false,true,
   '["engineer_registration_and_current_practising_certificate"]'::jsonb,
   array['engineer_registration_and_current_practising_certificate'],365,true),
  ('capability','engineering','company',true,false,true,
   '["engineering_firm_registration","named_engineer_practising_certificate"]'::jsonb,
   array['engineering_firm_registration','named_engineer_practising_certificate'],365,true),
  ('capability','surveying','individual',true,false,true,
   '["surveyor_registration_and_practising_certificate"]'::jsonb,
   array['surveyor_registration_and_practising_certificate'],365,true),
  ('capability','surveying','company',true,false,true,
   '["surveying_firm_registration","named_surveyor_practising_certificate"]'::jsonb,
   array['surveying_firm_registration','named_surveyor_practising_certificate'],365,true),
  ('capability','electrical_works','individual',true,false,true,
   '["era_installation_permit"]'::jsonb,array['era_installation_permit'],365,true),
  ('capability','electrical_works','company',true,false,true,
   '["era_company_installation_permit","named_installer_era_permit"]'::jsonb,
   array['era_company_installation_permit','named_installer_era_permit'],365,true),
  ('capability','electrical_installation','individual',true,false,true,
   '["era_installation_permit"]'::jsonb,array['era_installation_permit'],365,true),
  ('capability','electrical_installation','company',true,false,true,
   '["era_company_installation_permit","named_installer_era_permit"]'::jsonb,
   array['era_company_installation_permit','named_installer_era_permit'],365,true),
  ('capability','solar_systems','individual',true,false,true,
   '["era_solar_installation_permit_or_recognized_installer_certificate"]'::jsonb,
   array['era_solar_installation_permit_or_recognized_installer_certificate'],365,true),
  ('capability','solar_systems','company',true,false,true,
   '["era_company_permit_or_solar_business_authorization","named_solar_installer_credentials"]'::jsonb,
   array['era_company_permit_or_solar_business_authorization','named_solar_installer_credentials'],365,true),
  ('capability','building_contractors','individual',true,false,true,
   '["contractor_registration_or_trade_competency"]'::jsonb,
   array['contractor_registration_or_trade_competency'],365,true),
  ('capability','building_contractors','company',true,false,true,
   '["nbrb_contractor_registration","business_trading_licence","named_registered_professional_if_required"]'::jsonb,
   array['nbrb_contractor_registration','business_trading_licence','named_registered_professional_if_required'],365,true),
  ('capability','roofing','individual',true,false,true,
   '["roofing_trade_competency","work_at_height_safety_training"]'::jsonb,
   array['roofing_trade_competency','work_at_height_safety_training'],365,true),
  ('capability','roofing','company',true,false,true,
   '["contractor_registration_or_business_trading_licence","worker_safety_procedure"]'::jsonb,
   array['contractor_registration_or_business_trading_licence','worker_safety_procedure'],365,true),
  ('capability','concrete','individual',true,false,true,
   '["concrete_or_structural_trade_competency"]'::jsonb,
   array['concrete_or_structural_trade_competency'],365,true),
  ('capability','concrete','company',true,false,true,
   '["contractor_registration","named_registered_structural_professional_if_required"]'::jsonb,
   array['contractor_registration','named_registered_structural_professional_if_required'],365,true),
  ('capability','plumbing','individual',true,false,true,
   '["plumbing_trade_competency"]'::jsonb,array['plumbing_trade_competency'],365,true),
  ('capability','plumbing','company',true,false,true,
   '["plumbing_business_or_contractor_registration","named_qualified_plumber"]'::jsonb,
   array['plumbing_business_or_contractor_registration','named_qualified_plumber'],365,true),
  ('capability','excavation','individual',true,false,true,
   '["excavation_equipment_operator_competency"]'::jsonb,
   array['excavation_equipment_operator_competency'],365,true),
  ('capability','excavation','company',true,false,true,
   '["contractor_registration_or_trade_competency","equipment_ownership_or_hire_authority"]'::jsonb,
   array['contractor_registration_or_trade_competency','equipment_ownership_or_hire_authority'],365,true),
  ('capability','heavy_haulage','individual',true,false,true,
   '["correct_class_driving_licence","psv_or_operator_authorization_if_applicable"]'::jsonb,
   array['correct_class_driving_licence','psv_or_operator_authorization_if_applicable'],365,true),
  ('capability','heavy_haulage','company',true,false,true,
   '["transport_operator_licence","vehicle_registration_and_insurance"]'::jsonb,
   array['transport_operator_licence','vehicle_registration_and_insurance'],365,true),
  ('capability','driving_school_driver_training','individual',true,false,true,
   '["authorized_driving_instructor_credential"]'::jsonb,
   array['authorized_driving_instructor_credential'],365,true),
  ('capability','driving_school_driver_training','company',true,false,true,
   '["driving_school_licence","authorized_instructor_credentials","training_vehicle_documents"]'::jsonb,
   array['driving_school_licence','authorized_instructor_credentials','training_vehicle_documents'],365,true),
  ('capability','cargo_transport','individual',true,false,true,
   '["correct_class_driving_licence"]'::jsonb,array['correct_class_driving_licence'],365,true),
  ('capability','cargo_transport','company',true,false,true,
   '["transport_operator_licence","vehicle_registration_and_insurance"]'::jsonb,
   array['transport_operator_licence','vehicle_registration_and_insurance'],365,true),
  ('capability','truck_hire','individual',true,false,true,
   '["correct_class_driving_licence"]'::jsonb,array['correct_class_driving_licence'],365,true),
  ('capability','truck_hire','company',true,false,true,
   '["vehicle_registration_and_insurance","transport_operator_licence_if_applicable"]'::jsonb,
   array['vehicle_registration_and_insurance','transport_operator_licence_if_applicable'],365,true),
  ('capability','event_transport','individual',true,false,true,
   '["correct_class_driving_licence","psv_authorization_if_applicable"]'::jsonb,
   array['correct_class_driving_licence','psv_authorization_if_applicable'],365,true),
  ('capability','event_transport','company',true,false,true,
   '["vehicle_registration_and_insurance","transport_operator_licence_if_applicable"]'::jsonb,
   array['vehicle_registration_and_insurance','transport_operator_licence_if_applicable'],365,true),
  ('capability','excavator_hire','individual',true,false,true,
   '["excavator_operator_competency","equipment_ownership_or_hire_authority"]'::jsonb,
   array['excavator_operator_competency','equipment_ownership_or_hire_authority'],365,true),
  ('capability','excavator_hire','company',true,false,true,
   '["fleet_photos","ownership_or_logbook","operator_competency_if_operator_supplied"]'::jsonb,
   array['fleet_photos','ownership_or_logbook','operator_competency_if_operator_supplied'],365,true),
  ('capability','loader_hire','individual',true,false,true,
   '["loader_operator_competency","equipment_ownership_or_hire_authority"]'::jsonb,
   array['loader_operator_competency','equipment_ownership_or_hire_authority'],365,true),
  ('capability','loader_hire','company',true,false,true,
   '["fleet_photos","ownership_or_logbook","operator_competency_if_operator_supplied"]'::jsonb,
   array['fleet_photos','ownership_or_logbook','operator_competency_if_operator_supplied'],365,true),
  ('capability','grader_hire','individual',true,false,true,
   '["grader_operator_competency","equipment_ownership_or_hire_authority"]'::jsonb,
   array['grader_operator_competency','equipment_ownership_or_hire_authority'],365,true),
  ('capability','grader_hire','company',true,false,true,
   '["fleet_photos","ownership_or_logbook","operator_competency_if_operator_supplied"]'::jsonb,
   array['fleet_photos','ownership_or_logbook','operator_competency_if_operator_supplied'],365,true),
  ('capability','crane_hire','individual',true,false,true,
   '["crane_operator_competency","equipment_ownership_or_hire_authority"]'::jsonb,
   array['crane_operator_competency','equipment_ownership_or_hire_authority'],365,true),
  ('capability','crane_hire','company',true,false,true,
   '["fleet_photos","ownership_or_logbook","operator_competency_if_operator_supplied"]'::jsonb,
   array['fleet_photos','ownership_or_logbook','operator_competency_if_operator_supplied'],365,true),
  ('capability','visa_assistance','individual',true,false,true,
   '["licensed_travel_agency_authorization_or_employment_proof"]'::jsonb,
   array['licensed_travel_agency_authorization_or_employment_proof'],365,true),
  ('capability','visa_assistance','company',true,false,true,
   '["licensed_travel_agency_registration","business_licence"]'::jsonb,
   array['licensed_travel_agency_registration','business_licence'],365,true),
  ('capability','hajj_umrah','individual',true,false,true,
   '["authorized_hajj_operator_affiliation"]'::jsonb,
   array['authorized_hajj_operator_affiliation'],365,true),
  ('capability','hajj_umrah','company',true,false,true,
   '["hajj_operator_accreditation","business_licence"]'::jsonb,
   array['hajj_operator_accreditation','business_licence'],365,true),
  ('capability','seeds_inputs','individual',true,false,true,
   '["agrochemical_dealer_or_handler_authorization_if_applicable"]'::jsonb,
   array['agrochemical_dealer_or_handler_authorization_if_applicable'],365,true),
  ('capability','seeds_inputs','company',true,false,true,
   '["registered_agro_input_dealer_and_premises_if_applicable","product_registration_for_regulated_inputs"]'::jsonb,
   array['registered_agro_input_dealer_and_premises_if_applicable','product_registration_for_regulated_inputs'],365,true),
  ('capability','catering','individual',true,false,true,
   '["food_handler_health_certificate"]'::jsonb,array['food_handler_health_certificate'],365,true),
  ('capability','catering','company',true,false,true,
   '["food_business_health_permit","food_handler_certificates_for_food_staff"]'::jsonb,
   array['food_business_health_permit','food_handler_certificates_for_food_staff'],365,true)
on conflict (scope_type, scope_id, provider_type) do update set
  identity_required = excluded.identity_required,
  phone_required = excluded.phone_required,
  provider_verification_required = excluded.provider_verification_required,
  evidence_requirements = excluded.evidence_requirements,
  required_evidence = excluded.required_evidence,
  expires_after_days = excluded.expires_after_days,
  is_active = excluded.is_active,
  updated_at = now();

-- Specific rows override any older generic rule for the same capability.
update public.verification_requirements generic
set is_active = false, updated_at = now()
where generic.scope_type = 'capability'
  and generic.provider_type = 'both'
  and exists (
    select 1 from public.verification_requirements specific
    where specific.scope_type = generic.scope_type
      and specific.scope_id = generic.scope_id
      and specific.provider_type in ('individual','company')
      and specific.is_active
  );

-- Preserve pending proof ownership under the exact provider type it was
-- submitted for. This prevents a later type change from weakening review.
update public.provider_capability_evidence e
set provider_type = p.provider_type
from public.provider_capabilities pc
join public.need_capabilities nc on nc.slug = pc.capability_slug
join public.provider_category_profiles p
  on p.user_id = pc.user_id and p.category_slug = nc.category_slug
where e.provider_capability_id = pc.id
  and e.provider_type = 'both'
  and exists (
    select 1 from public.verification_requirements r
    where r.scope_type = 'capability'
      and r.scope_id = pc.capability_slug
      and r.provider_type = p.provider_type
      and r.is_active
  );

-- Remove the unsafe legacy travel sentinel and broad category-level proof rule;
-- travel verification is now configured against specific capabilities above.
update public.verification_requirements
set is_active = false, updated_at = now()
where (scope_type = 'category' and scope_id = 'travel_international')
   or (scope_type = 'capability' and scope_id = 'visa_assistance'
       and provider_type = 'both');

commit;

-- Rollback: deactivate the provider_type-specific rows, restore the prior
-- uniqueness constraint, then drop the provider_type column. Do not drop
-- evidence or provider capability records.
