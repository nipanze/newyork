-- Additive catalog expansion. Safe to re-run; existing slugs are preserved.
begin;

alter table public.need_categories
  add column if not exists aliases text[] not null default array[]::text[],
  add column if not exists tagline text,
  add column if not exists description text;
alter table public.need_capabilities
  add column if not exists aliases text[] not null default array[]::text[],
  add column if not exists capability_type text not null default 'service'
    check (capability_type in ('service', 'work')),
  add column if not exists policy text not null default 'open'
    check (policy in ('open', 'optional_proof', 'required_proof'));
alter table public.need_capabilities
  add column if not exists ui_group_slugs text[] not null default array[]::text[];
alter table public.capability_roles
  add column if not exists aliases text[] not null default array[]::text[];
alter table public.role_kinds
  add column if not exists aliases text[] not null default array[]::text[];
alter table public.role_qualifications
  add column if not exists expires_after_days integer;
alter table public.verification_requirements
  add column if not exists provider_type text not null default 'both',
  add column if not exists required_evidence text[] not null default array[]::text[],
  add column if not exists expires_after_days integer;
alter table public.verification_requirements
  drop constraint if exists verification_requirements_scope_type_scope_id_key;
create unique index if not exists verification_requirements_scope_type_scope_id_provider_type_uidx
  on public.verification_requirements(scope_type, scope_id, provider_type);

create table if not exists public.catalog_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  query text not null check (length(btrim(query)) between 1 and 160),
  created_at timestamptz not null default now()
);
alter table public.catalog_requests enable row level security;
drop policy if exists "catalog requests owner insert" on public.catalog_requests;
create policy "catalog requests owner insert" on public.catalog_requests
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "catalog requests admin read" on public.catalog_requests;
create policy "catalog requests admin read" on public.catalog_requests
  for select to authenticated using (private.is_admin());
revoke all on public.catalog_requests from anon, public;
grant insert on public.catalog_requests to authenticated;
grant select on public.catalog_requests to authenticated;

create table if not exists public.provider_content_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_slug text not null references public.need_categories(slug) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.provider_content_reports enable row level security;
drop policy if exists "provider content report owner insert" on public.provider_content_reports;
create policy "provider content report owner insert" on public.provider_content_reports
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "provider content report admin read" on public.provider_content_reports;
create policy "provider content report admin read" on public.provider_content_reports
  for select to authenticated using (private.is_admin());
revoke all on public.provider_content_reports from anon, public;
grant insert on public.provider_content_reports to authenticated;
grant select on public.provider_content_reports to authenticated;

-- Keep new categories disabled until their per-category rollout flag is enabled.
insert into public.need_categories (slug, name, icon, sort_order, description, is_active)
values
  ('domestic_household', 'Domestic & Household', '🏠', 15, 'House help, childcare, home cooking and care at home', false),
  ('health_medical', 'Health & Medical', '⚕️', 16, 'Nurses, doctors, specialists, clinics and care', false),
  ('business_investment', 'Business & Investment', '💼', 17, 'Angel investors, mentors and startup support', false),
  ('traditional_cultural', 'Traditional & Cultural Services', '🪘', 18, 'Traditional ceremonies, prayers, healing and culture', false)
on conflict (slug) do update set name = excluded.name, icon = excluded.icon,
  sort_order = excluded.sort_order, description = excluded.description;
update public.need_categories set
  tagline = 'House help, childcare, home cooking and care at home',
  aliases = array['maid','house help','housegirl','dada','domestic worker']
where slug = 'domestic_household';
update public.need_categories set
  tagline = 'Nurses, doctors, specialists, clinics and care',
  aliases = array['clinic','health centre','dispensary','nurse','doctor','optician','oncologist']
where slug = 'health_medical';
update public.need_categories set
  tagline = 'Angel investors, mentors and startup support',
  aliases = array['angel investor','investor','seed funding','startup funding']
where slug = 'business_investment';
update public.need_categories set
  tagline = 'Traditional ceremonies, prayers, healing and culture',
  aliases = array['duwa','duwah']
where slug = 'traditional_cultural';
update public.need_categories set name = 'Beauty, Fashion, Styling & Wellness'
where slug = 'beauty_fashion_styling';

-- Reflect existing verification configuration in the additive policy field.
-- This is descriptive metadata only and does not change existing activation.
update public.need_capabilities nc set policy = case
  when exists (
    select 1 from public.verification_requirements vr
    where vr.is_active and vr.scope_type = 'capability'
      and vr.scope_id = nc.slug and vr.provider_verification_required
  ) then 'required_proof'
  when exists (
    select 1 from public.verification_requirements vr
    where vr.is_active and vr.scope_type = 'capability'
      and vr.scope_id = nc.slug and (
        coalesce(cardinality(vr.required_evidence), 0) > 0
        or case when jsonb_typeof(vr.evidence_requirements) = 'array'
          then jsonb_array_length(vr.evidence_requirements) > 0 else false end
      )
  ) then 'optional_proof'
  else 'open'
end
where nc.slug not in (
 'house_help_services','housekeeping_services','laundry_services','gardening_services',
 'childcare_nanny_services','home_cooking_services','elderly_home_care','other_domestic',
 'chauffeur_services','personal_driver_hire','boda_taxi_services',
 'massage_therapy','spa_services','salon_barber_services','nails_skincare_services','sauna_steam_services',
 'clinic_services','hospital_services','eye_clinic_optical','dental_clinic','diagnostic_lab',
 'pharmacy_services','physiotherapy_clinic','home_nursing_agency','medical_staffing_agency',
 'other_health','circumcision_services','maternity_care_services','family_planning_services',
 'hiv_testing_services','mobile_health_outreach','orthopaedic_care',
 'angel_investor_network','startup_advisory','investor_introductions','incubator_accelerator','other_investment',
 'duwah_services','traditional_ceremony_services','traditional_dance_drumming',
 'traditional_healing_herbal','traditional_attire_crafts','other_traditional',
 'final_year_project_support','research_dissertation_guidance','data_analysis_help',
 'proofreading_editing','coursework_tutoring'
);
insert into public.system_settings
  (setting_key, setting_value, setting_type, category, description, is_public)
values
 ('capability_profiles_enabled_domestic_household','false','boolean','providers','Domestic & Household provider catalog rollout flag',true),
 ('capability_profiles_enabled_health_medical','false','boolean','providers','Health & Medical provider catalog rollout flag',true),
 ('capability_profiles_enabled_business_investment','false','boolean','providers','Business & Investment provider catalog rollout flag',true),
 ('capability_profiles_enabled_traditional_cultural','false','boolean','providers','Traditional & Cultural provider catalog rollout flag',true)
on conflict (setting_key, coalesce(country, '__global__')) do update
  set setting_value = excluded.setting_value,
  is_public = excluded.is_public;

-- Requested discovery aliases on existing canonical rows.
update public.need_capabilities set aliases = array['driving lessons','learn to drive','instructor']
where slug in ('driving_school','driving_school_driver_training');
update public.need_capabilities set aliases = array['chauffeur','executive driver','personal driver']
where slug in ('chauffeur_services','personal_driver_hire');
update public.need_capabilities set aliases = array['massage','masseuse','masseur','therapeutic body rub']
where slug = 'massage_therapy';
update public.need_capabilities set aliases = array['wellness','sauna','steam']
where slug = 'spa_services';
update public.need_capabilities set aliases = array['clinic','health centre','dispensary']
where slug = 'clinic_services';
update public.need_capabilities set aliases = array['bone doctor','fracture','broken bone','back pain','joint pain','knee','arthritis','x-ray','physio']
where slug = 'orthopaedic_care';

-- Additive service catalog. Health, investment, and traditional categories are
-- inactive above; their rows remain inactive and cannot be offered at launch.
insert into public.need_capabilities
  (slug, category_slug, name, is_active, ui_group_slug, sort_order,
   service_group_slug, service_group_name, service_sort_order,
   capability_type, policy, aliases)
values
 ('house_help_services','domestic_household','Maids & House Help',false,'domestic_household',10,'home_help','Home help',10,'service','optional_proof',array['maid','house help','housegirl','dada','domestic worker']),
 ('housekeeping_services','domestic_household','Housekeeping & Cleaning',false,'domestic_household',20,'home_help','Home help',20,'service','optional_proof',array['cleaner','house cleaner']),
 ('laundry_services','domestic_household','Laundry & Ironing',false,'domestic_household',30,'home_help','Home help',30,'service','open',array['laundry','ironing']),
 ('gardening_services','domestic_household','Gardening & Compound Care',false,'domestic_household',40,'home_help','Home help',40,'service','open',array['gardener','compound care']),
 ('childcare_nanny_services','domestic_household','Nannies & Childcare',false,'domestic_household',50,'family','Family',10,'service','optional_proof',array['nanny','babysitter','childcare']),
 ('home_cooking_services','domestic_household','Home Cooks',false,'domestic_household',60,'family','Family',20,'service','optional_proof',array['home cook','private cook']),
 ('elderly_home_care','domestic_household','Elderly Home Care',false,'domestic_household',70,'family','Family',30,'service','optional_proof',array['home carer','elder care']),
 ('other_domestic','domestic_household','Other Domestic',false,'domestic_household',80,'other','Other',10,'service','open',array[]::text[]),
 ('chauffeur_services','transport_logistics','Chauffeur Services',true,'transport_logistics',410,'passenger','Passenger transport',10,'service','optional_proof',array['chauffeur','executive driver']),
 ('personal_driver_hire','transport_logistics','Personal Driver Hire',true,'transport_logistics',420,'passenger','Passenger transport',20,'service','optional_proof',array['personal driver','private driver']),
 ('boda_taxi_services','transport_logistics','Boda Boda / Motorcycle Taxi',true,'transport_logistics',430,'passenger','Passenger transport',30,'service','optional_proof',array['boda','boda boda','motorcycle taxi']),
 ('massage_therapy','beauty_fashion_styling','Massage Therapy',true,'beauty_fashion_styling',710,'wellness_spa','Wellness & Spa',10,'service','optional_proof',array['massage','masseuse','masseur','therapeutic body rub']),
 ('spa_services','beauty_fashion_styling','Spa Services',true,'beauty_fashion_styling',720,'wellness_spa','Wellness & Spa',20,'service','optional_proof',array['wellness','sauna','steam']),
 ('salon_barber_services','beauty_fashion_styling','Salons & Barber Shops',true,'beauty_fashion_styling',730,'wellness_spa','Wellness & Spa',30,'service','optional_proof',array['salon','barber','barbershop']),
 ('nails_skincare_services','beauty_fashion_styling','Nails & Skincare',true,'beauty_fashion_styling',740,'wellness_spa','Wellness & Spa',40,'service','optional_proof',array['manicure','pedicure','skincare']),
 ('sauna_steam_services','beauty_fashion_styling','Sauna & Steam',true,'beauty_fashion_styling',750,'wellness_spa','Wellness & Spa',50,'service','optional_proof',array['sauna','steam room']),
 ('clinic_services','health_medical','Clinics & Health Centres',false,'health_medical',10,'facilities','Facilities',10,'service','required_proof',array['clinic','health centre','dispensary']),
 ('hospital_services','health_medical','Hospitals',false,'health_medical',20,'facilities','Facilities',20,'service','required_proof',array['hospital']),
 ('eye_clinic_optical','health_medical','Eye Clinics & Opticals',false,'health_medical',30,'facilities','Facilities',30,'service','required_proof',array['optician','optometrist','eye doctor','glasses']),
 ('dental_clinic','health_medical','Dental Clinics',false,'health_medical',40,'facilities','Facilities',40,'service','required_proof',array['dentist']),
 ('diagnostic_lab','health_medical','Diagnostic Labs & Imaging',false,'health_medical',50,'facilities','Facilities',50,'service','required_proof',array['lab','x-ray','imaging']),
 ('pharmacy_services','health_medical','Pharmacies',false,'health_medical',60,'facilities','Facilities',60,'service','required_proof',array['chemist','drug shop']),
 ('physiotherapy_clinic','health_medical','Physiotherapy Clinics',false,'health_medical',70,'facilities','Facilities',70,'service','required_proof',array['physio']),
 ('home_nursing_agency','health_medical','Home Nursing Agencies',false,'health_medical',80,'staffing','Staffing & home care',10,'service','required_proof',array['home nurse']),
 ('medical_staffing_agency','health_medical','Medical Staffing Agencies',false,'health_medical',90,'staffing','Staffing & home care',20,'service','required_proof',array[]::text[]),
 ('other_health','health_medical','Other Health Services',false,'health_medical',100,'other','Other',10,'service','required_proof',array[]::text[]),
 ('circumcision_services','health_medical','Circumcision Services',false,'health_medical',110,'procedures','Procedures',10,'service','required_proof',array['male circumcision','VMMC','mobile circumcision']),
 ('maternity_care_services','health_medical','Antenatal & Maternity Care',false,'health_medical',120,'reproductive','Reproductive health',10,'service','required_proof',array['pregnancy','antenatal','ANC','maternity','midwife','prenatal','delivery','post-abortion care']),
 ('family_planning_services','health_medical','Family Planning & Reproductive Health',false,'health_medical',130,'reproductive','Reproductive health',20,'service','required_proof',array['contraception','family planning']),
 ('hiv_testing_services','health_medical','HIV Testing & Counselling',false,'health_medical',140,'reproductive','Reproductive health',30,'service','required_proof',array['HIV test','HCT','VCT','PrEP','PEP','STI test','sexual health']),
 ('mobile_health_outreach','health_medical','Mobile Health Outreach',false,'health_medical',150,'staffing','Staffing & home care',30,'service','required_proof',array['home visit']),
 ('orthopaedic_care','health_medical','Orthopaedic & Bone Care',false,'health_medical',160,'facilities','Facilities',80,'service','required_proof',array['bone doctor','fracture','broken bone','back pain','joint pain','knee','arthritis','x-ray','physio']),
 ('angel_investor_network','business_investment','Angel Investor Networks',false,'business_investment',10,'funding','Investor support',10,'service','required_proof',array['angel investor','investor','seed funding','startup funding']),
 ('startup_advisory','business_investment','Startup Advisory',false,'business_investment',20,'funding','Investor support',20,'service','optional_proof',array['startup mentor']),
 ('investor_introductions','business_investment','Investor Introductions',false,'business_investment',30,'funding','Investor support',30,'service','required_proof',array['investor introduction']),
 ('incubator_accelerator','business_investment','Incubators & Accelerators',false,'business_investment',40,'funding','Investor support',40,'service','required_proof',array['startup incubator','accelerator']),
 ('other_investment','business_investment','Other Investment Support',false,'business_investment',50,'other','Other',10,'service','open',array[]::text[]),
 ('duwah_services','traditional_cultural','Duwah Services',false,'traditional_cultural',10,'culture','Culture',10,'service','optional_proof',array['duwa','duwah']),
 ('traditional_ceremony_services','traditional_cultural','Traditional Ceremonies',false,'traditional_cultural',20,'culture','Culture',20,'service','optional_proof',array[]::text[]),
 ('traditional_dance_drumming','traditional_cultural','Traditional Dance & Drumming',false,'traditional_cultural',30,'culture','Culture',30,'service','open',array[]::text[]),
 ('traditional_healing_herbal','traditional_cultural','Herbal & Traditional Healing',false,'traditional_cultural',40,'healing','Healing',10,'service','required_proof',array['traditional healer','herbalist']),
 ('traditional_attire_crafts','traditional_cultural','Traditional Attire & Crafts',false,'traditional_cultural',50,'culture','Culture',40,'service','open',array[]::text[]),
 ('other_traditional','traditional_cultural','Other Traditional',false,'traditional_cultural',60,'other','Other',10,'service','open',array[]::text[]),
 ('final_year_project_support','education_training','Final Year Project Support',true,'education_training',810,'coursework','Coursework & projects',10,'service','optional_proof',array['FYP','capstone','project defence']),
 ('research_dissertation_guidance','education_training','Research Proposal & Dissertation Guidance',true,'education_training',820,'coursework','Coursework & projects',20,'service','optional_proof',array['thesis','research paper','proposal']),
 ('data_analysis_help','education_training','Data Analysis & Statistics Help',true,'education_training',830,'coursework','Coursework & projects',30,'service','open',array['SPSS','statistics','STATA']),
 ('proofreading_editing','education_training','Proofreading & Editing',true,'education_training',840,'coursework','Coursework & projects',40,'service','open',array['editing']),
 ('coursework_tutoring','education_training','Coursework Tutoring',true,'education_training',850,'coursework','Coursework & projects',50,'service','open',array['course work','coursework','assignment help','homework'])
on conflict (slug) do update set
  name = excluded.name, ui_group_slug = excluded.ui_group_slug,
  sort_order = excluded.sort_order, service_group_slug = excluded.service_group_slug,
  service_group_name = excluded.service_group_name,
  service_sort_order = excluded.service_sort_order,
  aliases = excluded.aliases, policy = excluded.policy;

-- Personal work profiles. Categories stay inactive until their rollout flag
-- and country review are complete; role rows are seeded for discovery indexing.
insert into public.need_capabilities
  (slug, category_slug, name, is_active, ui_group_slug, sort_order,
   service_group_slug, service_group_name, service_sort_order,
   capability_type, policy, aliases)
values
 ('work_house_help','domestic_household','House Help / Maid',false,'domestic_household',110,'work_roles','Work roles',10,'work','optional_proof',array['maid','housegirl','dada','domestic worker']),
 ('work_nanny','domestic_household','Nanny / Childcare',false,'domestic_household',120,'work_roles','Work roles',20,'work','required_proof',array['nanny','babysitter']),
 ('work_home_cook','domestic_household','Home Cook',false,'domestic_household',130,'work_roles','Work roles',30,'work','optional_proof',array['cook']),
 ('work_gardener','domestic_household','Gardener / Groundskeeper',false,'domestic_household',140,'work_roles','Work roles',40,'work','open',array['gardener']),
 ('work_home_carer','domestic_household','Home Carer',false,'domestic_household',150,'work_roles','Work roles',50,'work','optional_proof',array['caregiver','home care']),
 ('work_driving_instructor','transport_logistics','Driving Instructor',true,'transport_logistics',440,'work_roles','Work roles',60,'work','required_proof',array['driving lessons','instructor']),
 ('work_massage_therapist','beauty_fashion_styling','Massage Therapist',true,'beauty_fashion_styling',760,'work_roles','Work roles',60,'work','optional_proof',array['masseuse','masseur']),
 ('work_spa_therapist','beauty_fashion_styling','Spa Therapist',true,'beauty_fashion_styling',770,'work_roles','Work roles',70,'work','optional_proof',array[]::text[]),
 ('work_spa_manager','beauty_fashion_styling','Spa / Wellness Manager',true,'beauty_fashion_styling',780,'work_roles','Work roles',80,'work','optional_proof',array[]::text[]),
 ('work_nurse','health_medical','Nurse / Midwife',false,'health_medical',210,'work_roles','Work roles',10,'work','required_proof',array['sister','RN','enrolled nurse']),
 ('work_doctor','health_medical','Doctor',false,'health_medical',220,'work_roles','Work roles',20,'work','required_proof',array['physician','MD','medical officer']),
 ('work_clinician','health_medical','Clinical Officer / Clinician',false,'health_medical',230,'work_roles','Work roles',30,'work','required_proof',array[]::text[]),
 ('work_medical_specialist','health_medical','Medical Specialist',false,'health_medical',240,'work_roles','Work roles',40,'work','required_proof',array['oncologist','cancer specialist']),
 ('work_optometrist','health_medical','Optician / Optometrist',false,'health_medical',250,'work_roles','Work roles',50,'work','required_proof',array['optician','eye doctor','glasses']),
 ('work_dentist','health_medical','Dentist',false,'health_medical',260,'work_roles','Work roles',60,'work','required_proof',array[]::text[]),
 ('work_pharmacist','health_medical','Pharmacist',false,'health_medical',270,'work_roles','Work roles',70,'work','required_proof',array[]::text[]),
 ('work_lab_technician','health_medical','Lab Technician',false,'health_medical',280,'work_roles','Work roles',80,'work','required_proof',array[]::text[]),
 ('work_physiotherapist','health_medical','Physiotherapist',false,'health_medical',290,'work_roles','Work roles',90,'work','required_proof',array[]::text[]),
 ('work_counsellor','health_medical','Counsellor / Psychologist',false,'health_medical',300,'work_roles','Work roles',100,'work','required_proof',array[]::text[]),
 ('work_nursing_assistant','health_medical','Nursing Assistant / Caregiver',false,'health_medical',310,'work_roles','Work roles',110,'work','required_proof',array[]::text[]),
 ('work_hiv_counsellor','health_medical','HIV Counsellor / Testing Officer',false,'health_medical',320,'work_roles','Work roles',120,'work','required_proof',array['HIV testing counsellor','HCT']),
 ('work_angel_investor','business_investment','Angel Investor',false,'business_investment',110,'work_roles','Work roles',10,'work','required_proof',array['investor','seed funding']),
 ('work_business_mentor','business_investment','Business Mentor',false,'business_investment',120,'work_roles','Work roles',20,'work','optional_proof',array['startup mentor']),
 ('work_duwah_practitioner','traditional_cultural','Duwah Practitioner',false,'traditional_cultural',110,'work_roles','Work roles',10,'work','optional_proof',array['duwa','duwah']),
 ('work_ceremony_officiant','traditional_cultural','Ceremony Officiant / Elder',false,'traditional_cultural',120,'work_roles','Work roles',20,'work','optional_proof',array[]::text[]),
 ('work_traditional_performer','traditional_cultural','Traditional Performer',false,'traditional_cultural',130,'work_roles','Work roles',30,'work','open',array[]::text[]),
 ('work_traditional_healer','traditional_cultural','Traditional Healer / Herbalist',false,'traditional_cultural',140,'work_roles','Work roles',40,'work','required_proof',array['traditional healer','herbalist']),
 ('work_research_mentor','education_training','Project / Research Mentor',true,'education_training',860,'work_roles','Work roles',90,'work','optional_proof',array['FYP','capstone','thesis','research paper','proposal'])
on conflict (slug) do update set
  name = excluded.name, ui_group_slug = excluded.ui_group_slug,
  sort_order = excluded.sort_order, policy = excluded.policy,
  aliases = excluded.aliases;

insert into public.capability_roles
  (slug, category_slug, capability_slug, name, kind_question, is_active, aliases)
select substring(slug from 6), category_slug, slug, name, question, true, array[]::text[]
from (values
 ('work_house_help','domestic_household','House Help / Maid','What kind of help?'),
 ('work_nanny','domestic_household','Nanny / Childcare','Which ages?'),
 ('work_home_cook','domestic_household','Home Cook','What do you cook?'),
 ('work_gardener','domestic_household','Gardener / Groundskeeper','What work?'),
 ('work_home_carer','domestic_household','Home Carer','Whom do you care for?'),
 ('work_driving_instructor','transport_logistics','Driving Instructor','What do you teach?'),
 ('work_massage_therapist','beauty_fashion_styling','Massage Therapist','Which massage?'),
 ('work_spa_therapist','beauty_fashion_styling','Spa Therapist','What treatments?'),
 ('work_spa_manager','beauty_fashion_styling','Spa / Wellness Manager','What do you manage?'),
 ('work_nurse','health_medical','Nurse / Midwife','What nursing?'),
 ('work_doctor','health_medical','Doctor','What do you practise?'),
 ('work_clinician','health_medical','Clinical Officer / Clinician','What area?'),
 ('work_medical_specialist','health_medical','Medical Specialist','Which specialty?'),
 ('work_optometrist','health_medical','Optician / Optometrist','What do you do?'),
 ('work_dentist','health_medical','Dentist','What dentistry?'),
 ('work_pharmacist','health_medical','Pharmacist','Where do you work?'),
 ('work_lab_technician','health_medical','Lab Technician','What lab work?'),
 ('work_physiotherapist','health_medical','Physiotherapist','What therapy?'),
 ('work_counsellor','health_medical','Counsellor / Psychologist','What support?'),
 ('work_nursing_assistant','health_medical','Nursing Assistant / Caregiver','What care?'),
 ('work_hiv_counsellor','health_medical','HIV Counsellor / Testing Officer','What do you do?'),
 ('work_angel_investor','business_investment','Angel Investor','Which sectors?'),
 ('work_business_mentor','business_investment','Business Mentor','What do you help with?'),
 ('work_duwah_practitioner','traditional_cultural','Duwah Practitioner','What is your practice?'),
 ('work_ceremony_officiant','traditional_cultural','Ceremony Officiant / Elder','Which ceremonies?'),
 ('work_traditional_performer','traditional_cultural','Traditional Performer','What do you perform?'),
 ('work_traditional_healer','traditional_cultural','Traditional Healer / Herbalist','What is your practice?'),
 ('work_research_mentor','education_training','Project / Research Mentor','What do you help with?')
) as roles(slug, category_slug, name, question)
on conflict (slug) do update set category_slug = excluded.category_slug,
  capability_slug = excluded.capability_slug, name = excluded.name,
  kind_question = excluded.kind_question, is_active = excluded.is_active;
update public.capability_roles set aliases = array['foreman','supervisor','ganger']
where slug = 'foreman_supervisor';
update public.capability_roles set aliases = array['physician','MD','medical officer']
where slug = 'doctor';
update public.capability_roles set aliases = array['sister','RN','enrolled nurse']
where slug = 'nurse';
update public.capability_roles set aliases = array['oncologist','cancer specialist']
where slug = 'medical_specialist';
update public.need_capabilities set ui_group_slugs = array[
  'transport_logistics','education_training','professional_services'
], aliases = array['driving lessons','learn to drive','instructor']
where slug in ('driving_school','driving_school_driver_training');

insert into public.role_kinds (role_slug, slug, name, sort_order) values
 ('house_help','live_in','Live-in',10),('house_help','live_out','Live-out',20),('house_help','day_work','Day work',30),('house_help','part_time','Part-time',40),('house_help','cleaning_only','Cleaning only',50),
 ('nanny','newborn','Newborn',10),('nanny','toddler','Toddler',20),('nanny','school_age','School age',30),('nanny','special_needs','Special needs',40),
 ('home_cook','family_meals','Family meals',10),('home_cook','special_diets','Special diets',20),('home_cook','event_cooking','Event cooking',30),('home_cook','baking','Baking',40),
 ('gardener','lawn_garden','Lawn & garden',10),('gardener','landscaping','Landscaping',20),('gardener','compound_upkeep','Compound upkeep',30),
 ('home_carer','elderly','Elderly',10),('home_carer','disabled','Disabled',20),('home_carer','post_surgery','Post-surgery',30),
 ('driving_instructor','cars','Cars',10),('driving_instructor','motorcycles','Motorcycles',20),('driving_instructor','trucks','Trucks',30),('driving_instructor','defensive_driving','Defensive driving',40),
 ('massage_therapist','relaxation','Relaxation',10),('massage_therapist','deep_tissue','Deep tissue',20),('massage_therapist','sports','Sports',30),('massage_therapist','prenatal','Prenatal',40),('massage_therapist','mobile','Mobile / at-home',50),
 ('spa_therapist','facials','Facials',10),('spa_therapist','body_treatments','Body treatments',20),('spa_therapist','nails','Nails',30),('spa_therapist','waxing','Waxing',40),
 ('spa_manager','spa','Spa',10),('spa_manager','salon','Salon',20),('spa_manager','wellness_centre','Wellness centre',30),
 ('nurse','general','General',10),('nurse','theatre','Theatre',20),('nurse','paediatric','Paediatric',30),('nurse','icu','ICU / critical care',40),('nurse','midwifery','Midwifery',50),('nurse','community_health','Community health',60),
 ('doctor','general_practitioner','General practitioner',10),('doctor','surgeon','Surgeon',20),('doctor','emergency','Emergency',30),('doctor','locum','Locum',40),
 ('clinician','general_clinical','General clinical',10),('clinician','anaesthesia','Anaesthesia',20),('clinician','orthopaedic','Orthopaedic',30),('clinician','ophthalmic','Ophthalmic',40),('clinician','community','Community',50),('clinician','circumcision','Circumcision (adult and infant)',60),
 ('medical_specialist','oncologist','Oncologist',10),('medical_specialist','cardiologist','Cardiologist',20),('medical_specialist','paediatrician','Paediatrician',30),('medical_specialist','gynaecologist','Gynaecologist',40),('medical_specialist','dermatologist','Dermatologist',50),('medical_specialist','ent','ENT',60),('medical_specialist','neurologist','Neurologist',70),('medical_specialist','orthopaedic_surgeon','Orthopaedic surgeon',80),('medical_specialist','urologist','Urologist',90),('medical_specialist','psychiatrist','Psychiatrist',100),('medical_specialist','radiologist','Radiologist',110),('medical_specialist','other_specialist','Other specialist',120),
 ('optometrist','eye_tests','Eye tests',10),('optometrist','contact_lenses','Contact lenses',20),('optometrist','dispensing_optician','Dispensing optician',30),('optometrist','low_vision','Low vision',40),
 ('dentist','general','General',10),('dentist','orthodontics','Orthodontics',20),('dentist','oral_surgery','Oral surgery',30),('dentist','paediatric','Paediatric',40),
 ('pharmacist','retail','Retail',10),('pharmacist','hospital','Hospital',20),('pharmacist','dispensing','Dispensing',30),('pharmacist','locum','Locum',40),
 ('lab_technician','medical_lab','Medical lab',10),('lab_technician','radiography','Radiography',20),('lab_technician','ultrasound','Ultrasound',30),
 ('physiotherapist','sports','Sports',10),('physiotherapist','neuro','Neuro',20),('physiotherapist','paediatric','Paediatric',30),('physiotherapist','geriatric','Geriatric',40),('physiotherapist','home_visits','Home visits',50),
 ('counsellor','individual','Individual',10),('counsellor','couples_family','Couples & family',20),('counsellor','trauma','Trauma',30),('counsellor','child_adolescent','Child & adolescent',40),
 ('nursing_assistant','bedside','Bedside',10),('nursing_assistant','home_care','Home care',20),('nursing_assistant','elderly','Elderly',30),('nursing_assistant','post_surgery','Post-surgery',40),
 ('hiv_counsellor','testing_counselling','Testing & counselling',10),('hiv_counsellor','peer_educator','Peer educator',20),('hiv_counsellor','community_outreach','Community outreach',30),
 ('angel_investor','technology','Technology',10),('angel_investor','agriculture','Agriculture',20),('angel_investor','retail_trade','Retail & trade',30),('angel_investor','health','Health',40),('angel_investor','energy','Energy',50),('angel_investor','real_estate','Real estate',60),('angel_investor','creative','Creative',70),('angel_investor','general','General',80),
 ('business_mentor','startup','Startup',10),('business_mentor','sme_growth','SME growth',20),('business_mentor','export','Export',30),('business_mentor','agribusiness','Agribusiness',40),
 ('ceremony_officiant','introduction_marriage','Introduction & marriage',10),('ceremony_officiant','naming','Naming',20),('ceremony_officiant','funeral_memorial','Funeral & memorial',30),('ceremony_officiant','cultural_rites','Cultural rites',40),
 ('traditional_performer','dancer','Dancer',10),('traditional_performer','drummer','Drummer',20),('traditional_performer','singer','Singer',30),('traditional_performer','storyteller','Storyteller',40),
 ('traditional_healer','herbalist','Herbalist',10),('traditional_healer','bone_setter','Bone setter',20),('traditional_healer','birth_attendant','Birth attendant',30),
 ('research_mentor','final_year_project','Final year project',10),('research_mentor','dissertation','Dissertation or thesis',20),('research_mentor','research_proposal','Research proposal',30),('research_mentor','data_analysis','Data analysis (SPSS, R, Excel, Stata)',40),('research_mentor','proofreading','Proofreading & editing',50),('research_mentor','presentation_defence','Presentation & defence coaching',60),('research_mentor','software_it_project','Software/IT project guidance',70)
on conflict (role_slug, slug) do update set name = excluded.name, sort_order = excluded.sort_order;

insert into public.role_qualifications (role_slug, slug, name, is_evidence, sort_order) values
 ('house_help','national_id','National ID',true,10),('house_help','references','References',false,20),('house_help','experience_one_year','Experience 1+ year',false,30),('house_help','languages','Languages',false,40),
 ('nanny','national_id','National ID',true,10),('nanny','police_clearance','Police clearance',true,20),('nanny','first_aid','First aid',true,30),('nanny','childcare_certificate','Childcare certificate',false,40),('nanny','references','References',false,50),
 ('home_cook','food_handler_certificate','Food handler certificate',true,10),('home_cook','references','References',false,20),('home_cook','experience_two_years','Experience 2+ years',false,30),
 ('gardener','experience','Experience',false,10),('gardener','references','References',false,20),('gardener','own_tools','Own tools',false,30),
 ('home_carer','caregiving_certificate','Caregiving certificate',true,10),('home_carer','first_aid','First aid',true,20),('home_carer','national_id','National ID',true,30),('home_carer','references','References',false,40),
 ('driving_instructor','instructor_licence','Instructor licence',true,10),('driving_instructor','valid_driving_licence','Valid driving licence',true,20),('driving_instructor','teaching_experience','2+ years teaching',false,30),
 ('massage_therapist','massage_therapy_certificate','Massage therapy certificate',true,10),('massage_therapist','hygiene_certification','Hygiene certification',true,20),('massage_therapist','own_equipment','Own equipment',false,30),('massage_therapist','experience_one_year','Experience 1+ year',false,40),
 ('spa_therapist','cosmetology_spa_certificate','Cosmetology or spa certificate',true,10),('spa_therapist','hygiene_certification','Hygiene certification',true,20),('spa_therapist','portfolio','Portfolio',false,30),
 ('spa_manager','business_licence','Business licence',true,10),('spa_manager','managed_three_staff','Managed 3+ staff',false,20),
 ('nurse','council_registration','Nursing council registration',true,10),('nurse','diploma_degree','Diploma / degree',true,20),('nurse','practising_certificate','Current practising certificate',true,30),('nurse','experience_two_years','2+ years',false,40),
 ('doctor','council_registration','Medical council registration',true,10),('doctor','medical_degree','MBChB / MD',true,20),('doctor','practising_certificate','Practising certificate',true,30),('doctor','internship_completed','Internship completed',false,40),
 ('clinician','council_registration','Clinical officers council registration',true,10),('clinician','diploma','Diploma',true,20),('clinician','practising_licence','Practising licence',true,30),
 ('medical_specialist','specialist_registration','Specialist registration',true,10),('medical_specialist','postgraduate_degree','Postgraduate degree or fellowship',true,20),('medical_specialist','medical_council_registration','Medical council registration',true,30),('medical_specialist','years_specialty','Years in specialty',false,40),
 ('optometrist','optometry_registration','Optometry registration',true,10),('optometrist','diploma_degree','Diploma / degree',true,20),('optometrist','practising_certificate','Practising certificate',true,30),
 ('dentist','dental_council_registration','Dental council registration',true,10),('dentist','bds','BDS',true,20),('dentist','practising_certificate','Practising certificate',true,30),
 ('pharmacist','pharmacy_board_registration','Pharmacy board registration',true,10),('pharmacist','degree','Degree',true,20),('pharmacist','practising_certificate','Practising certificate',true,30),
 ('lab_technician','lab_council_registration','Lab council registration',true,10),('lab_technician','diploma','Diploma',true,20),
 ('physiotherapist','physiotherapy_registration','Physiotherapy registration',true,10),('physiotherapist','degree','Degree',true,20),('physiotherapist','practising_certificate','Practising certificate',true,30),
 ('counsellor','professional_registration','Counselling or psychology registration',true,10),('counsellor','degree','Degree',true,20),('counsellor','supervised_hours','Supervised hours',false,30),
 ('nursing_assistant','assistant_certificate','Nursing assistant certificate',true,10),('nursing_assistant','first_aid','First aid',true,20),('nursing_assistant','national_id','National ID',true,30),
 ('hiv_counsellor','counselling_certificate','Counselling certificate',true,10),('hiv_counsellor','hiv_training','HIV testing and counselling training',true,20),('hiv_counsellor','facility_authorisation','Ministry of Health or facility authorisation',true,30),('hiv_counsellor','national_id','National ID',true,40),
 ('angel_investor','identity_verification','Identity verification',true,10),('angel_investor','investment_track_record','Proof of investment track record or portfolio',true,20),('angel_investor','ticket_size_range','Ticket size range',false,30),('angel_investor','stage_focus','Stage focus',false,40),
 ('business_mentor','experience_five_years','Experience 5+ years',false,10),('business_mentor','case_studies','Case studies',false,20),('business_mentor','referees','Referees',false,30),
 ('duwah_practitioner','endorsement','Community or religious endorsement letter',true,10),('duwah_practitioner','references','References',false,20),('duwah_practitioner','experience','Experience years',false,30),
 ('ceremony_officiant','endorsement','Endorsement',true,10),('ceremony_officiant','references','References',false,20),
 ('traditional_performer','showreel','Showreel',false,10),('traditional_performer','group_membership','Group membership',false,20),
 ('traditional_healer','association_registration','Registration with relevant association or local authority',true,10),('traditional_healer','referees','Referees',false,20),
 ('research_mentor','degree_in_field','Degree in the field',true,10),('research_mentor','masters_phd','Master’s or PhD',true,20),('research_mentor','published_work','Published work or portfolio',false,30),('research_mentor','subject_specialisation','Subject specialisation',false,40),('research_mentor','references','References',false,50)
on conflict (role_slug, slug) do update set name = excluded.name,
  is_evidence = excluded.is_evidence, sort_order = excluded.sort_order;

update public.role_kinds set name = name where role_slug = 'driver';
insert into public.role_kinds (role_slug, slug, name, sort_order) values
 ('driver','personal_driver','Personal driver',60),
 ('driver','chauffeur_executive','Chauffeur (executive)',70),
 ('driver','boda_rider','Boda rider',80),
 ('driver','airport_school_runs','Airport / school runs',90),
 ('doctor','circumcision_adult_infant','Circumcision (adult and infant)',90),
 ('nurse','antenatal_postnatal','Antenatal & postnatal care',70),
 ('nurse','family_planning','Family planning',80),
 ('nurse','hiv_testing_counselling','HIV testing & counselling',90)
on conflict (role_slug, slug) do update set name = excluded.name,
  sort_order = excluded.sort_order;
insert into public.role_qualifications (role_slug, slug, name, is_evidence, sort_order)
values
 ('driver','chauffeur_executive_experience','Chauffeur or executive driving experience',false,60),
 ('driver','certificate_good_conduct','Certificate of good conduct',true,70)
on conflict (role_slug, slug) do update set name = excluded.name,
  is_evidence = excluded.is_evidence, sort_order = excluded.sort_order;
update public.role_qualifications set expires_after_days = 365
where slug in ('council_registration','practising_certificate',
  'clinical_officers_council_registration','practising_licence',
  'specialist_registration','medical_council_registration',
  'optometry_registration','dental_council_registration',
  'pharmacy_board_registration','lab_council_registration',
  'physiotherapy_registration','professional_registration',
  'facility_authorisation','association_registration');

-- Licensing evidence is independent of company registration and expires yearly.
insert into public.verification_requirements
  (scope_type, scope_id, provider_type, identity_required, phone_required,
   provider_verification_required, evidence_requirements, required_evidence,
   expires_after_days, is_active)
values
 ('capability','driving_school','company',false,false,true,
  '["school_licence"]'::jsonb,array['school_licence'],365,true),
 ('capability','driving_school_driver_training','company',false,false,true,
  '["school_licence"]'::jsonb,array['school_licence'],365,true)
on conflict (scope_type, scope_id, provider_type) do update set
  provider_verification_required = true,
  evidence_requirements = excluded.evidence_requirements,
  required_evidence = excluded.required_evidence,
  expires_after_days = 365, is_active = true;

-- Keep the trust gate private: a proof policy is metadata and the verification
-- RPC remains the only path to a verified badge.
update public.need_capabilities set policy = 'required_proof'
where slug in ('driving_school','driving_school_driver_training');

-- Cross-category search data is exposed as one read-only catalog view.
create or replace view public.v_catalog_search as
select 'category'::text as result_type, c.slug, c.slug as category_slug,
       c.name as label, c.aliases, c.name as parent_category,
       c.sort_order, null::text as capability_type
from public.need_categories c where c.is_active
union all
select case when n.capability_type = 'work' then 'role' else 'service' end,
       n.slug, n.category_slug, n.name, n.aliases, c.name,
       n.sort_order, n.capability_type
from public.need_capabilities n
join public.need_categories c on c.slug = n.category_slug
where n.is_active and c.is_active
union all
select 'role', cr.capability_slug, cr.category_slug, cr.name, cr.aliases,
       c.name, n.sort_order, 'work'
from public.capability_roles cr
join public.need_capabilities n on n.slug = cr.capability_slug and n.is_active
join public.need_categories c on c.slug = cr.category_slug and c.is_active
where cr.is_active
union all
select 'kind', rk.role_slug || ':' || rk.slug, cr.category_slug, rk.name,
       rk.aliases || array[rk.slug], c.name, rk.sort_order, 'work'
from public.role_kinds rk
join public.capability_roles cr on cr.slug = rk.role_slug and cr.is_active
join public.need_categories c on c.slug = cr.category_slug and c.is_active;
grant select on public.v_catalog_search to authenticated;
revoke all on public.v_catalog_search from anon, public;

-- Fallback search aliases for existing catalog items called out in the plan.
update public.need_categories set aliases = array['angel investor','investor','seed funding','startup funding']
where slug = 'business_investment';
update public.need_categories set aliases = array['clinic','health centre','dispensary']
where slug = 'health_medical';
update public.need_capabilities set aliases = array['course work','coursework','assignment help','homework']
where slug = 'coursework_tutoring';
update public.need_capabilities set aliases = array['FYP','capstone','project defence']
where slug = 'final_year_project_support';
update public.need_capabilities set aliases = array['thesis','research paper','proposal']
where slug = 'research_dissertation_guidance';
update public.need_capabilities set aliases = array['SPSS','statistics','STATA']
where slug = 'data_analysis_help';
-- Preserve the stable driving-school slug and category; route it into all three
-- discovery groups without relocating its canonical category.
-- Foreman acceptance case: the seed previously marked its trade certificate as
-- non-evidence, so Screen F had no proof-enabled qualification to upload.
update public.role_qualifications set is_evidence = true
where role_slug = 'foreman_supervisor' and slug = 'trade_test_certificate';

-- The production upload component enforces 5 MB; make the storage bucket agree.
insert into storage.buckets (id, name, public, file_size_limit)
values ('provider-evidence', 'provider-evidence', false, 5242880)
on conflict (id) do update set public = false, file_size_limit = 5242880;

drop policy if exists "provider evidence storage owner upload"
  on storage.objects;
create policy "provider evidence storage owner upload" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'provider-evidence'
    and (storage.foldername(name))[1] = 'evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
drop policy if exists "provider evidence storage owner read"
  on storage.objects;
create policy "provider evidence storage owner read" on storage.objects
  for select to authenticated using (
    bucket_id = 'provider-evidence'
    and (((storage.foldername(name))[1] = 'evidence'
      and (storage.foldername(name))[2] = auth.uid()::text)
      or private.is_admin())
  );

create or replace function public.cleanup_unrecorded_provider_evidence(
  p_object_path text
) returns boolean
language plpgsql security definer
set search_path = public, private, storage, pg_temp
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or p_object_path not like 'evidence/' || v_user::text || '/%' then
    raise exception 'Evidence object does not belong to current user.'
      using errcode = '42501';
  end if;
  if exists (select 1 from public.provider_capability_evidence
      where file_url = p_object_path)
     or exists (select 1 from public.job_profile_qualification_answers
      where evidence_object_path = p_object_path)
     or exists (select 1 from public.provider_role_qualification_claims
      where evidence_object_path = p_object_path)
     or exists (select 1 from public.provider_company_verification_submissions
      where file_path = p_object_path) then
    return false;
  end if;
  delete from storage.objects
  where bucket_id = 'provider-evidence' and name = p_object_path
    and owner_id = v_user::text;
  return found;
end;
$$;
revoke all on function public.cleanup_unrecorded_provider_evidence(text)
  from public, anon;
grant execute on function public.cleanup_unrecorded_provider_evidence(text)
  to authenticated;

create or replace function public.admin_review_provider_role_qualification(
  p_claim_id uuid,
  p_action text,
  p_reject_reason text default null,
  p_expires_at timestamptz default null
) returns boolean
language plpgsql security definer
set search_path = public, private, pg_temp
as $$
declare
  v_admin uuid := auth.uid();
  v_claim record;
  v_effective_expiry timestamptz := p_expires_at;
begin
  if not private.is_admin() then
    raise exception 'Unauthorized: Admin access required.' using errcode = '42501';
  end if;
  if p_action not in ('approve', 'reject', 'expire') then
    raise exception 'Action must be approve, reject, or expire.' using errcode = '22023';
  end if;
  select claim.*, pc.capability_slug, pc.user_id, rq.expires_after_days
  into v_claim
  from public.provider_role_qualification_claims claim
  join public.provider_capabilities pc on pc.id = claim.provider_capability_id
  join public.role_qualifications rq
    on rq.role_slug = claim.role_slug and rq.slug = claim.qualification_slug
  where claim.id = p_claim_id
  for update of claim;
  if not found then
    raise exception 'Provider role qualification claim not found.' using errcode = 'P0212';
  end if;
  if p_action = 'approve' and v_claim.status <> 'pending_review' then
    raise exception 'Only submitted qualification evidence can be approved.' using errcode = '22023';
  end if;
  if p_action = 'approve' and v_effective_expiry is null
     and v_claim.expires_after_days is not null then
    v_effective_expiry := now() + make_interval(days => v_claim.expires_after_days);
  end if;
  if p_action = 'approve' and v_effective_expiry is not null
     and v_effective_expiry <= now() then
    raise exception 'Evidence expiry must be in the future.' using errcode = '22023';
  end if;
  update public.provider_role_qualification_claims
  set status = case when p_action = 'approve' then 'verified'
                    when p_action = 'reject' then 'rejected' else 'expired' end,
      reject_reason = case when p_action = 'reject' then coalesce(p_reject_reason, '') else null end,
      expires_at = case when p_action = 'approve' then v_effective_expiry else expires_at end,
      reviewed_by = v_admin, reviewed_at = now(), updated_at = now()
  where id = p_claim_id;
  insert into public.audit_logs
    (user_id, event_type, entity_type, entity_id, action, new_values)
  values
    (v_admin, 'admin_action', 'provider_role_qualification_claim', p_claim_id,
     'review_provider_role_qualification', jsonb_build_object(
       'action', p_action, 'provider_capability_id', v_claim.provider_capability_id,
       'capability_slug', v_claim.capability_slug, 'role_slug', v_claim.role_slug,
       'qualification_slug', v_claim.qualification_slug,
       'reject_reason', p_reject_reason, 'expires_at', v_effective_expiry));
  return true;
end;
$$;
revoke all on function public.admin_review_provider_role_qualification(uuid, text, text, timestamptz)
  from public, anon;
grant execute on function public.admin_review_provider_role_qualification(uuid, text, text, timestamptz)
  to authenticated;

commit;
