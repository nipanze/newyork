-- =============================================================================
-- Standalone SQL Patch: patch_provider_services_work_profiles.sql
-- Stage 4.14: Provider capability profiles and Work Profiles
-- 
-- Safe to re-run (idempotent).
-- Non-destructive: preserves existing capabilities, evidence, and audit logs.
-- Conforms strictly to .agents/AGENTS.md.
-- =============================================================================

begin;

-- 1. Table schema adjustments for need_capabilities
alter table public.need_capabilities
  add column if not exists capability_type text not null default 'service'
    check (capability_type in ('service', 'work')),
  add column if not exists ui_group_slug text,
  add column if not exists sort_order integer not null default 1000,
  add column if not exists service_group_slug text,
  add column if not exists service_group_name text,
  add column if not exists service_sort_order integer not null default 1000;

comment on column public.need_capabilities.capability_type is
  'Distinguishes offered services (service) from work-seeking profiles (work).';

alter table public.verification_requirements
  add column if not exists required_evidence text[] not null default array[]::text[],
  add column if not exists expires_after_days integer;

alter table public.provider_capabilities
  add column if not exists updated_at timestamptz not null default now();

-- 2. Evidence table
create table if not exists public.provider_capability_evidence (
  id uuid primary key default gen_random_uuid(),
  provider_capability_id uuid not null
    references public.provider_capabilities(id) on delete cascade,
  requirement_key text not null,
  file_url text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'expired')),
  reject_reason text,
  expires_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_provider_capability_evidence_capability
  on public.provider_capability_evidence(provider_capability_id, requirement_key, created_at desc);

create index if not exists idx_provider_capability_evidence_status
  on public.provider_capability_evidence(status, expires_at);

alter table public.provider_capability_evidence enable row level security;

drop policy if exists "provider evidence owner select" on public.provider_capability_evidence;
create policy "provider evidence owner select"
  on public.provider_capability_evidence
  for select to authenticated
  using (
    exists (
      select 1 from public.provider_capabilities pc
      where pc.id = provider_capability_evidence.provider_capability_id
        and (pc.user_id = auth.uid() or private.is_admin())
    )
  );

drop policy if exists "provider evidence owner insert" on public.provider_capability_evidence;
create policy "provider evidence owner insert"
  on public.provider_capability_evidence
  for insert to authenticated
  with check (
    exists (
      select 1 from public.provider_capabilities pc
      where pc.id = provider_capability_evidence.provider_capability_id
        and pc.user_id = auth.uid()
    )
  );

drop policy if exists "provider evidence owner resubmit" on public.provider_capability_evidence;
create policy "provider evidence owner resubmit"
  on public.provider_capability_evidence
  for update to authenticated
  using (
    status in ('pending', 'rejected', 'expired')
    and exists (
      select 1 from public.provider_capabilities pc
      where pc.id = provider_capability_evidence.provider_capability_id
        and pc.user_id = auth.uid()
    )
  )
  with check (
    status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and exists (
      select 1 from public.provider_capabilities pc
      where pc.id = provider_capability_evidence.provider_capability_id
        and pc.user_id = auth.uid()
    )
  );

drop policy if exists "provider evidence admin all" on public.provider_capability_evidence;
create policy "provider evidence admin all"
  on public.provider_capability_evidence
  for all to authenticated
  using (private.is_admin());

grant select, insert, update on public.provider_capability_evidence to authenticated;

-- 3. Seed 14 categories
insert into public.need_categories (slug, name, icon, sort_order, description, is_active)
values
  ('technology_digital', 'Technology & Digital', '💻', 1, 'Software, websites, IT support and security', true),
  ('marketing_promotion', 'Marketing & Promotion', '📣', 2, 'Advertising, content and influencer work', true),
  ('professional_services', 'Business & Professional Services', '💼', 3, 'Consulting, legal, accounting, HR and design', true),
  ('education_training', 'Education & Training', '🎓', 4, 'Learning, admissions and placements', true),
  ('events_production', 'Events & Celebrations', '🎉', 5, 'Weddings, parties, corporate events and the services behind them', true),
  ('photo_video_music_talent', 'Photo, Video, Music & Talent', '🎬', 6, 'Creative production and performers for any occasion', true),
  ('beauty_fashion_styling', 'Beauty, Fashion & Styling', '💄', 7, 'Makeup, hair, styling and clothing', true),
  ('construction_building', 'Construction & Building', '🏗️', 8, 'Contractors, trades and surveying', true),
  ('energy_utilities', 'Energy & Water', '⚡', 9, 'Solar, power backup, boreholes and water systems', true),
  ('transport_logistics', 'Transport & Logistics', '🚚', 10, 'Moving, hauling, delivery and cold chain', true),
  ('machinery_equipment', 'Machinery & Equipment', '🚜', 11, 'Heavy machinery and equipment hire, with or without an operator', true),
  ('agriculture_agribusiness', 'Agriculture & Agribusiness', '🌾', 12, 'Farm services, inputs and produce', true),
  ('specialized_products', 'Procurement & Sourcing', '🔎', 13, 'Buying, importing and finding hard-to-get products', true),
  ('travel_international', 'Travel & International', '✈️', 14, 'Bookings, visas, tours and relocation', true)
on conflict (slug) do update set
  name = excluded.name,
  icon = excluded.icon,
  sort_order = excluded.sort_order,
  description = excluded.description,
  is_active = true;

-- 4. Canonical Services (need_capabilities with capability_type = service)
insert into public.need_capabilities (slug, category_slug, name, is_active, ui_group_slug, sort_order, service_group_slug, service_group_name, service_sort_order, capability_type)
values
  ('software_development', 'technology_digital', 'Software Development', true, 'technology_digital', 110, 'build', 'Build', 10, 'service'),
  ('website_development', 'technology_digital', 'Website Development', true, 'technology_digital', 120, 'build', 'Build', 20, 'service'),
  ('mobile_app_development', 'technology_digital', 'Mobile App Development', true, 'technology_digital', 130, 'build', 'Build', 30, 'service'),
  ('automation_services', 'technology_digital', 'Automation', true, 'technology_digital', 140, 'build', 'Build', 40, 'service'),
  ('it_support', 'technology_digital', 'IT Support', true, 'technology_digital', 210, 'support_infrastructure', 'Support & Infrastructure', 10, 'service'),
  ('networking_services', 'technology_digital', 'Networking', true, 'technology_digital', 220, 'support_infrastructure', 'Support & Infrastructure', 20, 'service'),
  ('cybersecurity_services', 'technology_digital', 'Cybersecurity', true, 'technology_digital', 230, 'support_infrastructure', 'Support & Infrastructure', 30, 'service'),
  ('other_technology', 'technology_digital', 'Other Technology', true, 'technology_digital', 310, 'other', 'Other', 10, 'service'),
  ('digital_marketing', 'marketing_promotion', 'Digital Marketing', true, 'marketing_promotion', 110, 'campaigns', 'Campaigns', 10, 'service'),
  ('social_media_marketing', 'marketing_promotion', 'Social Media Marketing', true, 'marketing_promotion', 120, 'campaigns', 'Campaigns', 20, 'service'),
  ('advertising_campaigns', 'marketing_promotion', 'Advertising Campaigns', true, 'marketing_promotion', 130, 'campaigns', 'Campaigns', 30, 'service'),
  ('brand_promotion', 'marketing_promotion', 'Brand Promotion', true, 'marketing_promotion', 140, 'campaigns', 'Campaigns', 40, 'service'),
  ('event_promotion', 'marketing_promotion', 'Event Promotion', true, 'marketing_promotion', 150, 'campaigns', 'Campaigns', 50, 'service'),
  ('affiliate_marketing', 'marketing_promotion', 'Affiliate Marketing', true, 'marketing_promotion', 160, 'campaigns', 'Campaigns', 60, 'service'),
  ('content_creation', 'marketing_promotion', 'Content Creation', true, 'marketing_promotion', 210, 'content_reach', 'Content & Reach', 10, 'service'),
  ('influencer_marketing', 'marketing_promotion', 'Influencer Marketing', true, 'marketing_promotion', 220, 'content_reach', 'Content & Reach', 20, 'service'),
  ('product_reviews', 'marketing_promotion', 'Product Reviews', true, 'marketing_promotion', 230, 'content_reach', 'Content & Reach', 30, 'service'),
  ('i_have_an_audience', 'marketing_promotion', 'I Have an Audience', true, 'marketing_promotion', 240, 'content_reach', 'Content & Reach', 40, 'service'),
  ('other_marketing_services', 'marketing_promotion', 'Other Marketing Services', true, 'marketing_promotion', 310, 'other', 'Other', 10, 'service'),
  ('accounting_tax', 'professional_services', 'Accounting & Tax', true, 'business_professional_services', 110, 'finance_legal', 'Finance & Legal', 10, 'service'),
  ('legal_services', 'professional_services', 'Legal Services', true, 'business_professional_services', 120, 'finance_legal', 'Finance & Legal', 20, 'service'),
  ('company_registration', 'professional_services', 'Company Registration', true, 'business_professional_services', 130, 'finance_legal', 'Finance & Legal', 30, 'service'),
  ('business_consulting', 'professional_services', 'Business Consulting', true, 'business_professional_services', 210, 'advisory', 'Advisory', 10, 'service'),
  ('hr_services', 'professional_services', 'HR Services', true, 'business_professional_services', 220, 'advisory', 'Advisory', 20, 'service'),
  ('architecture_services', 'professional_services', 'Architecture', true, 'business_professional_services', 310, 'design_engineering', 'Design & Engineering', 10, 'service'),
  ('engineering_consulting', 'professional_services', 'Engineering', true, 'business_professional_services', 320, 'design_engineering', 'Design & Engineering', 20, 'service'),
  ('driving_school_driver_training', 'professional_services', 'Driving School / Driver Training', true, 'business_professional_services', 330, 'design_engineering', 'Design & Engineering', 30, 'service'),
  ('other_professional', 'professional_services', 'Other Professional Services', true, 'business_professional_services', 410, 'other', 'Other', 10, 'service'),
  ('private_tutoring', 'education_training', 'Private Tutoring', true, 'education_training', 110, 'learning', 'Learning', 10, 'service'),
  ('online_classes', 'education_training', 'Online Classes', true, 'education_training', 120, 'learning', 'Learning', 20, 'service'),
  ('exam_preparation', 'education_training', 'Exam Preparation', true, 'education_training', 130, 'learning', 'Learning', 30, 'service'),
  ('language_training', 'education_training', 'Language Training', true, 'education_training', 140, 'learning', 'Learning', 40, 'service'),
  ('computer_training', 'education_training', 'Computer Training', true, 'education_training', 150, 'learning', 'Learning', 50, 'service'),
  ('professional_training', 'education_training', 'Professional Training', true, 'education_training', 160, 'learning', 'Learning', 60, 'service'),
  ('vocational_training', 'education_training', 'Vocational Training', true, 'education_training', 170, 'learning', 'Learning', 70, 'service'),
  ('academic_consulting', 'education_training', 'Academic Consulting', true, 'education_training', 180, 'learning', 'Learning', 80, 'service'),
  ('university_admissions', 'education_training', 'University Admissions', true, 'education_training', 210, 'admissions_placements', 'Admissions & Placements', 10, 'service'),
  ('study_abroad_guidance', 'education_training', 'Study Abroad Guidance', true, 'education_training', 220, 'admissions_placements', 'Admissions & Placements', 20, 'service'),
  ('internship_placement', 'education_training', 'Internship Placement', true, 'education_training', 230, 'admissions_placements', 'Admissions & Placements', 30, 'service'),
  ('health_nursing_placements', 'education_training', 'Health / Nursing Placements', true, 'education_training', 240, 'admissions_placements', 'Admissions & Placements', 40, 'service'),
  ('event_planning', 'events_production', 'Event Planning', true, 'events_celebrations', 110, 'planning_styling', 'Planning & Styling', 10, 'service'),
  ('event_decoration', 'events_production', 'Decoration', true, 'events_celebrations', 120, 'planning_styling', 'Planning & Styling', 20, 'service'),
  ('celebration_cakes', 'events_production', 'Cakes', true, 'events_celebrations', 130, 'planning_styling', 'Planning & Styling', 30, 'service'),
  ('celebration_catering', 'events_production', 'Catering', true, 'events_celebrations', 140, 'planning_styling', 'Planning & Styling', 40, 'service'),
  ('tent_hire', 'events_production', 'Tents', true, 'events_celebrations', 210, 'equipment_venue_setup', 'Equipment & Venue Setup', 10, 'service'),
  ('event_equipment', 'events_production', 'Event Equipment', true, 'events_celebrations', 220, 'equipment_venue_setup', 'Equipment & Venue Setup', 20, 'service'),
  ('sound_systems', 'events_production', 'Sound Systems', true, 'events_celebrations', 230, 'equipment_venue_setup', 'Equipment & Venue Setup', 30, 'service'),
  ('lighting_hire', 'events_production', 'Lighting', true, 'events_celebrations', 240, 'equipment_venue_setup', 'Equipment & Venue Setup', 40, 'service'),
  ('celebration_mc_dj', 'events_production', 'DJs / MCs', true, 'events_celebrations', 310, 'entertainment_hosting', 'Entertainment & Hosting', 10, 'service'),
  ('event_transport', 'events_production', 'Event Transport', true, 'events_celebrations', 320, 'entertainment_hosting', 'Entertainment & Hosting', 20, 'service'),
  ('other_events', 'events_production', 'Other Events', true, 'events_celebrations', 410, 'other', 'Other', 10, 'service'),
  ('photography_services', 'photo_video_music_talent', 'Photography', true, 'photo_video_music_talent', 110, 'photo_video', 'Photo & Video', 10, 'service'),
  ('videography_services', 'photo_video_music_talent', 'Videography', true, 'photo_video_music_talent', 120, 'photo_video', 'Photo & Video', 20, 'service'),
  ('video_editors', 'photo_video_music_talent', 'Video Editors', true, 'photo_video_music_talent', 130, 'photo_video', 'Photo & Video', 30, 'service'),
  ('recording_studios', 'photo_video_music_talent', 'Recording Studios', true, 'photo_video_music_talent', 210, 'music_production', 'Music Production', 10, 'service'),
  ('music_producers', 'photo_video_music_talent', 'Music Producers', true, 'photo_video_music_talent', 220, 'music_production', 'Music Production', 20, 'service'),
  ('mixing_mastering', 'photo_video_music_talent', 'Mixing & Mastering', true, 'photo_video_music_talent', 230, 'music_production', 'Music Production', 30, 'service'),
  ('songwriters', 'photo_video_music_talent', 'Songwriters', true, 'photo_video_music_talent', 240, 'music_production', 'Music Production', 40, 'service'),
  ('singers_vocalists', 'photo_video_music_talent', 'Singers / Vocalists', true, 'photo_video_music_talent', 250, 'music_production', 'Music Production', 50, 'service'),
  ('actors_actresses', 'photo_video_music_talent', 'Actors / Actresses', true, 'photo_video_music_talent', 310, 'on_screen_performers', 'On-screen & Performers', 10, 'service'),
  ('dancers', 'photo_video_music_talent', 'Dancers', true, 'photo_video_music_talent', 320, 'on_screen_performers', 'On-screen & Performers', 20, 'service'),
  ('background_extras', 'photo_video_music_talent', 'Background Extras', true, 'photo_video_music_talent', 330, 'on_screen_performers', 'On-screen & Performers', 30, 'service'),
  ('music_video_models', 'photo_video_music_talent', 'Music Video Models', true, 'photo_video_music_talent', 340, 'on_screen_performers', 'On-screen & Performers', 40, 'service'),
  ('celebration_makeup', 'beauty_fashion_styling', 'Makeup Artists', true, 'beauty_fashion_styling', 110, 'beauty', 'Beauty', 10, 'service'),
  ('hair_styling', 'beauty_fashion_styling', 'Hair Stylists', true, 'beauty_fashion_styling', 120, 'beauty', 'Beauty', 20, 'service'),
  ('bridal_styling', 'beauty_fashion_styling', 'Bridal Styling', true, 'beauty_fashion_styling', 210, 'fashion', 'Fashion', 10, 'service'),
  ('music_video_stylists', 'beauty_fashion_styling', 'Stylists', true, 'beauty_fashion_styling', 220, 'fashion', 'Fashion', 20, 'service'),
  ('dresses_bridesmaid_outfits', 'beauty_fashion_styling', 'Wedding Dresses / Bridesmaid Outfits', true, 'beauty_fashion_styling', 230, 'fashion', 'Fashion', 30, 'service'),
  ('building_contractors', 'construction_building', 'Building Contractors', true, 'construction_building', 110, 'contracting', 'Contracting', 10, 'service'),
  ('roofing_services', 'construction_building', 'Roofing', true, 'construction_building', 120, 'contracting', 'Contracting', 20, 'service'),
  ('excavation_works', 'construction_building', 'Excavation', true, 'construction_building', 130, 'contracting', 'Contracting', 30, 'service'),
  ('concrete_works', 'construction_building', 'Concrete', true, 'construction_building', 140, 'contracting', 'Contracting', 40, 'service'),
  ('plumbing_services', 'construction_building', 'Plumbing', true, 'construction_building', 210, 'trades', 'Trades', 10, 'service'),
  ('electrical_works', 'construction_building', 'Electrical Works', true, 'construction_building', 220, 'trades', 'Trades', 20, 'service'),
  ('construction_materials', 'construction_building', 'Construction Materials', true, 'construction_building', 310, 'materials_survey', 'Materials & Survey', 10, 'service'),
  ('surveying_services', 'construction_building', 'Surveying', true, 'construction_building', 320, 'materials_survey', 'Materials & Survey', 20, 'service'),
  ('other_construction', 'construction_building', 'Other Construction', true, 'construction_building', 410, 'other', 'Other', 10, 'service'),
  ('solar_systems', 'energy_utilities', 'Solar Systems', true, 'energy_water', 110, 'power', 'Power', 10, 'service'),
  ('battery_supply', 'energy_utilities', 'Batteries', true, 'energy_water', 120, 'power', 'Power', 20, 'service'),
  ('backup_power', 'energy_utilities', 'Backup Power', true, 'energy_water', 130, 'power', 'Power', 30, 'service'),
  ('generator_supply', 'energy_utilities', 'Generators', true, 'energy_water', 140, 'power', 'Power', 40, 'service'),
  ('electrical_installation', 'energy_utilities', 'Electrical Installation', true, 'energy_water', 150, 'power', 'Power', 50, 'service'),
  ('borehole_drilling', 'energy_utilities', 'Boreholes', true, 'energy_water', 210, 'water', 'Water', 10, 'service'),
  ('water_systems', 'energy_utilities', 'Water Systems', true, 'energy_water', 220, 'water', 'Water', 20, 'service'),
  ('energy_consulting', 'energy_utilities', 'Energy Consulting', true, 'energy_water', 310, 'advisory', 'Advisory', 10, 'service'),
  ('other_energy_services', 'energy_utilities', 'Other Energy Services', true, 'energy_water', 320, 'advisory', 'Advisory', 20, 'service'),
  ('cargo_transport', 'transport_logistics', 'Cargo Transport', true, 'transport_logistics', 110, 'freight', 'Freight', 10, 'service'),
  ('bulk_delivery', 'transport_logistics', 'Bulk Delivery', true, 'transport_logistics', 120, 'freight', 'Freight', 20, 'service'),
  ('heavy_haulage', 'transport_logistics', 'Heavy Haulage', true, 'transport_logistics', 130, 'freight', 'Freight', 30, 'service'),
  ('agricultural_transport', 'transport_logistics', 'Agricultural Transport', true, 'transport_logistics', 140, 'freight', 'Freight', 40, 'service'),
  ('cold_chain_transport', 'transport_logistics', 'Cold Chain & Refrigerated', true, 'transport_logistics', 150, 'freight', 'Freight', 50, 'service'),
  ('courier_delivery', 'transport_logistics', 'Courier', true, 'transport_logistics', 210, 'delivery_moving', 'Delivery & Moving', 10, 'service'),
  ('moving_services', 'transport_logistics', 'Moving Services', true, 'transport_logistics', 220, 'delivery_moving', 'Delivery & Moving', 20, 'service'),
  ('truck_hire', 'transport_logistics', 'Truck Hire', true, 'transport_logistics', 310, 'vehicles', 'Vehicles', 10, 'service'),
  ('vehicle_transport', 'transport_logistics', 'Vehicle Transport', true, 'transport_logistics', 320, 'vehicles', 'Vehicles', 20, 'service'),
  ('other_logistics', 'transport_logistics', 'Other Logistics', true, 'transport_logistics', 410, 'other', 'Other', 10, 'service'),
  ('excavator_hire', 'machinery_equipment', 'Excavator Hire', true, 'machinery_equipment', 110, 'earthmoving', 'Earthmoving', 10, 'service'),
  ('loader_hire', 'machinery_equipment', 'Loader Hire', true, 'machinery_equipment', 120, 'earthmoving', 'Earthmoving', 20, 'service'),
  ('grader_hire', 'machinery_equipment', 'Grader Hire', true, 'machinery_equipment', 130, 'earthmoving', 'Earthmoving', 30, 'service'),
  ('crane_hire', 'machinery_equipment', 'Crane Hire', true, 'machinery_equipment', 210, 'lifting_power', 'Lifting & Power', 10, 'service'),
  ('generator_hire', 'machinery_equipment', 'Generator Hire', true, 'machinery_equipment', 220, 'lifting_power', 'Lifting & Power', 20, 'service'),
  ('tractor_hire', 'machinery_equipment', 'Tractor Hire', true, 'machinery_equipment', 310, 'farm_industrial', 'Farm & Industrial', 10, 'service'),
  ('industrial_equipment', 'machinery_equipment', 'Industrial Equipment', true, 'machinery_equipment', 320, 'farm_industrial', 'Farm & Industrial', 20, 'service'),
  ('other_machinery', 'machinery_equipment', 'Other Machinery', true, 'machinery_equipment', 410, 'other', 'Other', 10, 'service'),
  ('farm_services', 'agriculture_agribusiness', 'Farm Services', true, 'agriculture_agribusiness', 110, 'farm_operations', 'Farm Operations', 10, 'service'),
  ('irrigation_services', 'agriculture_agribusiness', 'Irrigation', true, 'agriculture_agribusiness', 120, 'farm_operations', 'Farm Operations', 20, 'service'),
  ('seeds_inputs', 'agriculture_agribusiness', 'Seeds & Inputs', true, 'agriculture_agribusiness', 210, 'inputs_livestock', 'Inputs & Livestock', 10, 'service'),
  ('livestock_sourcing', 'agriculture_agribusiness', 'Livestock Sourcing', true, 'agriculture_agribusiness', 220, 'inputs_livestock', 'Inputs & Livestock', 20, 'service'),
  ('produce_buyers', 'agriculture_agribusiness', 'Produce Buyers', true, 'agriculture_agribusiness', 310, 'market', 'Market', 10, 'service'),
  ('other_agriculture', 'agriculture_agribusiness', 'Other Agriculture', true, 'agriculture_agribusiness', 320, 'market', 'Market', 20, 'service'),
  ('bulk_procurement', 'specialized_products', 'Bulk Procurement', true, 'procurement_sourcing', 110, 'sourcing', 'Sourcing', 10, 'service'),
  ('equipment_sourcing', 'specialized_products', 'Equipment Sourcing', true, 'procurement_sourcing', 120, 'sourcing', 'Sourcing', 20, 'service'),
  ('imported_products', 'specialized_products', 'Imported Products', true, 'procurement_sourcing', 130, 'sourcing', 'Sourcing', 30, 'service'),
  ('hard_to_find_products', 'specialized_products', 'Hard-to-Find Products', true, 'procurement_sourcing', 140, 'sourcing', 'Sourcing', 40, 'service'),
  ('electronics_procurement', 'specialized_products', 'Electronics Procurement', true, 'procurement_sourcing', 210, 'parts_supplies', 'Parts & Supplies', 10, 'service'),
  ('industrial_parts', 'specialized_products', 'Industrial Parts', true, 'procurement_sourcing', 220, 'parts_supplies', 'Parts & Supplies', 20, 'service'),
  ('spare_parts', 'specialized_products', 'Spare Parts', true, 'procurement_sourcing', 230, 'parts_supplies', 'Parts & Supplies', 30, 'service'),
  ('medical_lab_supplies', 'specialized_products', 'Medical & Lab Supplies', true, 'procurement_sourcing', 240, 'parts_supplies', 'Parts & Supplies', 40, 'service'),
  ('other_procurement', 'specialized_products', 'Other Procurement', true, 'procurement_sourcing', 310, 'other', 'Other', 10, 'service'),
  ('flight_tickets', 'travel_international', 'Flight Tickets & Bookings', true, 'travel_international', 110, 'bookings', 'Bookings', 10, 'service'),
  ('accommodation', 'travel_international', 'Accommodation', true, 'travel_international', 120, 'bookings', 'Bookings', 20, 'service'),
  ('airport_transfers', 'travel_international', 'Airport Transfers', true, 'travel_international', 130, 'bookings', 'Bookings', 30, 'service'),
  ('tour_packages', 'travel_international', 'Tour Packages', true, 'travel_international', 140, 'bookings', 'Bookings', 40, 'service'),
  ('visa_assistance', 'travel_international', 'Visa Assistance', true, 'travel_international', 210, 'documents_cover', 'Documents & Cover', 10, 'service'),
  ('travel_documentation', 'travel_international', 'Travel Documentation', true, 'travel_international', 220, 'documents_cover', 'Documents & Cover', 20, 'service'),
  ('travel_insurance', 'travel_international', 'Travel Insurance', true, 'travel_international', 230, 'documents_cover', 'Documents & Cover', 30, 'service'),
  ('hajj_umrah', 'travel_international', 'Hajj & Umrah', true, 'travel_international', 310, 'specialised', 'Specialised', 10, 'service'),
  ('international_relocation', 'travel_international', 'International Relocation', true, 'travel_international', 320, 'specialised', 'Specialised', 20, 'service'),
  ('travel_consultation', 'travel_international', 'Travel Consultation', true, 'travel_international', 330, 'specialised', 'Specialised', 30, 'service'),
  ('other_travel_services', 'travel_international', 'Other Travel Services', true, 'travel_international', 340, 'specialised', 'Specialised', 40, 'service')
on conflict (slug) do update set
  category_slug = excluded.category_slug,
  name = excluded.name,
  is_active = true,
  ui_group_slug = excluded.ui_group_slug,
  sort_order = excluded.sort_order,
  service_group_slug = excluded.service_group_slug,
  service_group_name = excluded.service_group_name,
  service_sort_order = excluded.service_sort_order,
  capability_type = 'service';

-- 5. Work Roles (need_capabilities with capability_type = work, and capability_roles)
insert into public.need_capabilities (slug, category_slug, name, is_active, ui_group_slug, sort_order, service_group_slug, service_group_name, service_sort_order, capability_type)
values
  ('work_developer', 'technology_digital', 'Developer', true, 'technology_digital', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_it_technician', 'technology_digital', 'IT Technician', true, 'technology_digital', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_security_specialist', 'technology_digital', 'Security Specialist', true, 'technology_digital', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_project_manager', 'technology_digital', 'Project Manager', true, 'technology_digital', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_team_lead_manager', 'technology_digital', 'Team Lead / Manager', true, 'technology_digital', 50, 'work_roles', 'Work Roles', 50, 'work'),
  ('work_marketer_specialist', 'marketing_promotion', 'Marketer / Specialist', true, 'marketing_promotion', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_content_creator', 'marketing_promotion', 'Content Creator', true, 'marketing_promotion', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_marketing_manager', 'marketing_promotion', 'Marketing Manager', true, 'marketing_promotion', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_campaign_project_manager', 'marketing_promotion', 'Campaign Project Manager', true, 'marketing_promotion', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_accountant_finance_officer', 'professional_services', 'Accountant / Finance Officer', true, 'business_professional_services', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_lawyer_legal_officer', 'professional_services', 'Lawyer / Legal Officer', true, 'business_professional_services', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_engineer', 'professional_services', 'Engineer', true, 'business_professional_services', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_architect_designer', 'professional_services', 'Architect / Designer', true, 'business_professional_services', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_hr_officer_manager', 'professional_services', 'HR Officer / Manager', true, 'business_professional_services', 50, 'work_roles', 'Work Roles', 50, 'work'),
  ('work_business_administrator_office_manager', 'professional_services', 'Business Administrator / Office Manager', true, 'business_professional_services', 60, 'work_roles', 'Work Roles', 60, 'work'),
  ('work_consultant', 'professional_services', 'Consultant', true, 'business_professional_services', 70, 'work_roles', 'Work Roles', 70, 'work'),
  ('work_professional_services_project_manager', 'professional_services', 'Project Manager', true, 'business_professional_services', 80, 'work_roles', 'Work Roles', 80, 'work'),
  ('work_teacher_tutor', 'education_training', 'Teacher / Tutor', true, 'education_training', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_trainer_instructor', 'education_training', 'Trainer / Instructor', true, 'education_training', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_placement_coordinator', 'education_training', 'Placement Coordinator', true, 'education_training', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_programme_manager', 'education_training', 'Programme Manager', true, 'education_training', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_event_manager_planner', 'events_production', 'Event Manager / Planner', true, 'events_celebrations', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_mc_dj', 'events_production', 'MC / DJ', true, 'events_celebrations', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_event_crew_technician', 'events_production', 'Event Crew / Technician', true, 'events_celebrations', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_caterer_chef', 'events_production', 'Caterer / Chef', true, 'events_celebrations', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_event_supervisor', 'events_production', 'Event Supervisor', true, 'events_celebrations', 50, 'work_roles', 'Work Roles', 50, 'work'),
  ('work_photographer_videographer', 'photo_video_music_talent', 'Photographer / Videographer', true, 'photo_video_music_talent', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_audio_engineer_producer', 'photo_video_music_talent', 'Audio Engineer / Producer', true, 'photo_video_music_talent', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_performer_talent', 'photo_video_music_talent', 'Performer / Talent', true, 'photo_video_music_talent', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_production_manager', 'photo_video_music_talent', 'Production Manager', true, 'photo_video_music_talent', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_makeup_artist', 'beauty_fashion_styling', 'Makeup Artist', true, 'beauty_fashion_styling', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_hair_stylist', 'beauty_fashion_styling', 'Hair Stylist', true, 'beauty_fashion_styling', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_stylist_designer', 'beauty_fashion_styling', 'Stylist / Designer', true, 'beauty_fashion_styling', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_salon_studio_manager', 'beauty_fashion_styling', 'Salon / Studio Manager', true, 'beauty_fashion_styling', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_site_manager', 'construction_building', 'Site Manager', true, 'construction_building', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_construction_building_project_manager', 'construction_building', 'Project Manager', true, 'construction_building', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_foreman_supervisor', 'construction_building', 'Foreman / Supervisor', true, 'construction_building', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_skilled_tradesperson', 'construction_building', 'Skilled Tradesperson', true, 'construction_building', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_surveyor', 'construction_building', 'Surveyor', true, 'construction_building', 50, 'work_roles', 'Work Roles', 50, 'work'),
  ('work_solar_electrical_technician', 'energy_utilities', 'Solar / Electrical Technician', true, 'energy_water', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_borehole_water_technician', 'energy_utilities', 'Borehole / Water Technician', true, 'energy_water', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_energy_engineer', 'energy_utilities', 'Energy Engineer', true, 'energy_water', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_energy_utilities_project_manager', 'energy_utilities', 'Project Manager', true, 'energy_water', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_driver', 'transport_logistics', 'Driver', true, 'transport_logistics', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_fleet_operations_manager', 'transport_logistics', 'Fleet / Operations Manager', true, 'transport_logistics', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_dispatcher_coordinator', 'transport_logistics', 'Dispatcher / Coordinator', true, 'transport_logistics', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_loader_mover', 'transport_logistics', 'Loader / Mover', true, 'transport_logistics', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_machine_operator', 'machinery_equipment', 'Machine Operator', true, 'machinery_equipment', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_equipment_mechanic', 'machinery_equipment', 'Equipment Mechanic', true, 'machinery_equipment', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_fleet_equipment_manager', 'machinery_equipment', 'Fleet / Equipment Manager', true, 'machinery_equipment', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_site_supervisor', 'machinery_equipment', 'Site Supervisor', true, 'machinery_equipment', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_farm_manager', 'agriculture_agribusiness', 'Farm Manager', true, 'agriculture_agribusiness', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_agronomist_extension_officer', 'agriculture_agribusiness', 'Agronomist / Extension Officer', true, 'agriculture_agribusiness', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_veterinary_livestock_officer', 'agriculture_agribusiness', 'Veterinary / Livestock Officer', true, 'agriculture_agribusiness', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_farm_worker_operator', 'agriculture_agribusiness', 'Farm Worker / Operator', true, 'agriculture_agribusiness', 40, 'work_roles', 'Work Roles', 40, 'work'),
  ('work_procurement_officer_manager', 'specialized_products', 'Procurement Officer / Manager', true, 'procurement_sourcing', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_sourcing_agent', 'specialized_products', 'Sourcing Agent', true, 'procurement_sourcing', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_clearing_customs_agent', 'specialized_products', 'Clearing & Customs Agent', true, 'procurement_sourcing', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_travel_agent_consultant', 'travel_international', 'Travel Agent / Consultant', true, 'travel_international', 10, 'work_roles', 'Work Roles', 10, 'work'),
  ('work_tour_guide', 'travel_international', 'Tour Guide', true, 'travel_international', 20, 'work_roles', 'Work Roles', 20, 'work'),
  ('work_driver_guide', 'travel_international', 'Driver-Guide', true, 'travel_international', 30, 'work_roles', 'Work Roles', 30, 'work'),
  ('work_operations_manager', 'travel_international', 'Operations Manager', true, 'travel_international', 40, 'work_roles', 'Work Roles', 40, 'work')
on conflict (slug) do update set
  category_slug = excluded.category_slug,
  name = excluded.name,
  is_active = true,
  ui_group_slug = excluded.ui_group_slug,
  sort_order = excluded.sort_order,
  service_group_slug = excluded.service_group_slug,
  service_group_name = excluded.service_group_name,
  service_sort_order = excluded.service_sort_order,
  capability_type = 'work';

insert into public.capability_roles (slug, category_slug, capability_slug, name, kind_question, is_active)
values
  ('developer', 'technology_digital', 'work_developer', 'Developer', 'What do you build?', true),
  ('it_technician', 'technology_digital', 'work_it_technician', 'IT Technician', 'What do you do?', true),
  ('security_specialist', 'technology_digital', 'work_security_specialist', 'Security Specialist', 'Which area?', true),
  ('project_manager', 'technology_digital', 'work_project_manager', 'Project Manager', 'What kind of projects?', true),
  ('team_lead_manager', 'technology_digital', 'work_team_lead_manager', 'Team Lead / Manager', 'What do you lead?', true),
  ('marketer_specialist', 'marketing_promotion', 'work_marketer_specialist', 'Marketer / Specialist', 'Which channel?', true),
  ('content_creator', 'marketing_promotion', 'work_content_creator', 'Content Creator', 'What do you produce?', true),
  ('marketing_manager', 'marketing_promotion', 'work_marketing_manager', 'Marketing Manager', 'What scope?', true),
  ('campaign_project_manager', 'marketing_promotion', 'work_campaign_project_manager', 'Campaign Project Manager', 'Campaign type?', true),
  ('accountant_finance_officer', 'professional_services', 'work_accountant_finance_officer', 'Accountant / Finance Officer', 'What area?', true),
  ('lawyer_legal_officer', 'professional_services', 'work_lawyer_legal_officer', 'Lawyer / Legal Officer', 'What area?', true),
  ('engineer', 'professional_services', 'work_engineer', 'Engineer', 'Which discipline?', true),
  ('architect_designer', 'professional_services', 'work_architect_designer', 'Architect / Designer', 'What do you design?', true),
  ('hr_officer_manager', 'professional_services', 'work_hr_officer_manager', 'HR Officer / Manager', 'What area?', true),
  ('business_administrator_office_manager', 'professional_services', 'work_business_administrator_office_manager', 'Business Administrator / Office Manager', 'What kind of admin work?', true),
  ('consultant', 'professional_services', 'work_consultant', 'Consultant', 'Advisory area?', true),
  ('professional_services_project_manager', 'professional_services', 'work_professional_services_project_manager', 'Project Manager', 'What kind of projects?', true),
  ('teacher_tutor', 'education_training', 'work_teacher_tutor', 'Teacher / Tutor', 'What do you teach?', true),
  ('trainer_instructor', 'education_training', 'work_trainer_instructor', 'Trainer / Instructor', 'Training field?', true),
  ('placement_coordinator', 'education_training', 'work_placement_coordinator', 'Placement Coordinator', 'What placements?', true),
  ('programme_manager', 'education_training', 'work_programme_manager', 'Programme Manager', 'What programmes?', true),
  ('event_manager_planner', 'events_production', 'work_event_manager_planner', 'Event Manager / Planner', 'What events?', true),
  ('mc_dj', 'events_production', 'work_mc_dj', 'MC / DJ', 'Which role?', true),
  ('event_crew_technician', 'events_production', 'work_event_crew_technician', 'Event Crew / Technician', 'What do you operate?', true),
  ('caterer_chef', 'events_production', 'work_caterer_chef', 'Caterer / Chef', 'What kind?', true),
  ('event_supervisor', 'events_production', 'work_event_supervisor', 'Event Supervisor', 'What scope?', true),
  ('photographer_videographer', 'photo_video_music_talent', 'work_photographer_videographer', 'Photographer / Videographer', 'What do you shoot?', true),
  ('audio_engineer_producer', 'photo_video_music_talent', 'work_audio_engineer_producer', 'Audio Engineer / Producer', 'What do you do?', true),
  ('performer_talent', 'photo_video_music_talent', 'work_performer_talent', 'Performer / Talent', 'What kind?', true),
  ('production_manager', 'photo_video_music_talent', 'work_production_manager', 'Production Manager', 'What productions?', true),
  ('makeup_artist', 'beauty_fashion_styling', 'work_makeup_artist', 'Makeup Artist', 'Specialty?', true),
  ('hair_stylist', 'beauty_fashion_styling', 'work_hair_stylist', 'Hair Stylist', 'Specialty?', true),
  ('stylist_designer', 'beauty_fashion_styling', 'work_stylist_designer', 'Stylist / Designer', 'Specialty?', true),
  ('salon_studio_manager', 'beauty_fashion_styling', 'work_salon_studio_manager', 'Salon / Studio Manager', 'What scope?', true),
  ('site_manager', 'construction_building', 'work_site_manager', 'Site Manager', 'What type of sites?', true),
  ('construction_building_project_manager', 'construction_building', 'work_construction_building_project_manager', 'Project Manager', 'What kind of projects?', true),
  ('foreman_supervisor', 'construction_building', 'work_foreman_supervisor', 'Foreman / Supervisor', 'Which trade?', true),
  ('skilled_tradesperson', 'construction_building', 'work_skilled_tradesperson', 'Skilled Tradesperson', 'Which trade?', true),
  ('surveyor', 'construction_building', 'work_surveyor', 'Surveyor', 'What type?', true),
  ('solar_electrical_technician', 'energy_utilities', 'work_solar_electrical_technician', 'Solar / Electrical Technician', 'What do you install?', true),
  ('borehole_water_technician', 'energy_utilities', 'work_borehole_water_technician', 'Borehole / Water Technician', 'What do you do?', true),
  ('energy_engineer', 'energy_utilities', 'work_energy_engineer', 'Energy Engineer', 'Which area?', true),
  ('energy_utilities_project_manager', 'energy_utilities', 'work_energy_utilities_project_manager', 'Project Manager', 'What kind of projects?', true),
  ('driver', 'transport_logistics', 'work_driver', 'Driver', 'What do you drive?', true),
  ('fleet_operations_manager', 'transport_logistics', 'work_fleet_operations_manager', 'Fleet / Operations Manager', 'What fleet?', true),
  ('dispatcher_coordinator', 'transport_logistics', 'work_dispatcher_coordinator', 'Dispatcher / Coordinator', 'What area?', true),
  ('loader_mover', 'transport_logistics', 'work_loader_mover', 'Loader / Mover', 'What work?', true),
  ('machine_operator', 'machinery_equipment', 'work_machine_operator', 'Machine Operator', 'Which machine do you operate?', true),
  ('equipment_mechanic', 'machinery_equipment', 'work_equipment_mechanic', 'Equipment Mechanic', 'What do you service?', true),
  ('fleet_equipment_manager', 'machinery_equipment', 'work_fleet_equipment_manager', 'Fleet / Equipment Manager', 'What fleet?', true),
  ('site_supervisor', 'machinery_equipment', 'work_site_supervisor', 'Site Supervisor', 'Which sites?', true),
  ('farm_manager', 'agriculture_agribusiness', 'work_farm_manager', 'Farm Manager', 'What farm?', true),
  ('agronomist_extension_officer', 'agriculture_agribusiness', 'work_agronomist_extension_officer', 'Agronomist / Extension Officer', 'What focus?', true),
  ('veterinary_livestock_officer', 'agriculture_agribusiness', 'work_veterinary_livestock_officer', 'Veterinary / Livestock Officer', 'What animals?', true),
  ('farm_worker_operator', 'agriculture_agribusiness', 'work_farm_worker_operator', 'Farm Worker / Operator', 'What work?', true),
  ('procurement_officer_manager', 'specialized_products', 'work_procurement_officer_manager', 'Procurement Officer / Manager', 'What do you buy?', true),
  ('sourcing_agent', 'specialized_products', 'work_sourcing_agent', 'Sourcing Agent', 'Where do you source?', true),
  ('clearing_customs_agent', 'specialized_products', 'work_clearing_customs_agent', 'Clearing & Customs Agent', 'What do you handle?', true),
  ('travel_agent_consultant', 'travel_international', 'work_travel_agent_consultant', 'Travel Agent / Consultant', 'What do you handle?', true),
  ('tour_guide', 'travel_international', 'work_tour_guide', 'Tour Guide', 'What tours?', true),
  ('driver_guide', 'travel_international', 'work_driver_guide', 'Driver-Guide', 'What vehicle?', true),
  ('operations_manager', 'travel_international', 'work_operations_manager', 'Operations Manager', 'What scope?', true)
on conflict (slug) do update set
  category_slug = excluded.category_slug,
  capability_slug = excluded.capability_slug,
  name = excluded.name,
  kind_question = excluded.kind_question,
  is_active = true;

insert into public.role_kinds (role_slug, slug, name, sort_order)
values
  ('developer', 'frontend', 'Frontend', 10),
  ('developer', 'backend', 'Backend', 20),
  ('developer', 'full_stack', 'Full-stack', 30),
  ('developer', 'mobile', 'Mobile', 40),
  ('developer', 'qa_tester', 'QA / Tester', 50),
  ('developer', 'devops', 'DevOps', 60),
  ('it_technician', 'helpdesk', 'Helpdesk', 10),
  ('it_technician', 'hardware_repair', 'Hardware repair', 20),
  ('it_technician', 'network_installation', 'Network installation', 30),
  ('it_technician', 'cctv_access_control', 'CCTV & access control', 40),
  ('security_specialist', 'network_security', 'Network security', 10),
  ('security_specialist', 'penetration_testing', 'Penetration testing', 20),
  ('security_specialist', 'security_audits', 'Security audits', 30),
  ('project_manager', 'software', 'Software', 10),
  ('project_manager', 'it_infrastructure', 'IT infrastructure', 20),
  ('project_manager', 'digital_transformation', 'Digital transformation', 30),
  ('team_lead_manager', 'dev_team', 'Dev team', 10),
  ('team_lead_manager', 'it_support_team', 'IT / support team', 20),
  ('team_lead_manager', 'product', 'Product', 30),
  ('marketer_specialist', 'social_media', 'Social media', 10),
  ('marketer_specialist', 'seo_sem', 'SEO / SEM', 20),
  ('marketer_specialist', 'email', 'Email', 30),
  ('marketer_specialist', 'brand', 'Brand', 40),
  ('marketer_specialist', 'community_management', 'Community management', 50),
  ('content_creator', 'video', 'Video', 10),
  ('content_creator', 'photo', 'Photo', 20),
  ('content_creator', 'writing', 'Writing', 30),
  ('content_creator', 'design', 'Design', 40),
  ('content_creator', 'podcast', 'Podcast', 50),
  ('marketing_manager', 'brand', 'Brand', 10),
  ('marketing_manager', 'digital', 'Digital', 20),
  ('marketing_manager', 'events_promotions', 'Events & promotions', 30),
  ('campaign_project_manager', 'digital', 'Digital', 10),
  ('campaign_project_manager', 'field_activation', 'Field / activation', 20),
  ('campaign_project_manager', 'event', 'Event', 30),
  ('accountant_finance_officer', 'bookkeeping', 'Bookkeeping', 10),
  ('accountant_finance_officer', 'tax', 'Tax', 20),
  ('accountant_finance_officer', 'audit', 'Audit', 30),
  ('accountant_finance_officer', 'payroll', 'Payroll', 40),
  ('lawyer_legal_officer', 'corporate', 'Corporate', 10),
  ('lawyer_legal_officer', 'property', 'Property', 20),
  ('lawyer_legal_officer', 'contracts', 'Contracts', 30),
  ('lawyer_legal_officer', 'compliance', 'Compliance', 40),
  ('engineer', 'civil', 'Civil', 10),
  ('engineer', 'electrical', 'Electrical', 20),
  ('engineer', 'mechanical', 'Mechanical', 30),
  ('engineer', 'mining', 'Mining', 40),
  ('architect_designer', 'buildings', 'Buildings', 10),
  ('architect_designer', 'interiors', 'Interiors', 20),
  ('architect_designer', 'landscape', 'Landscape', 30),
  ('hr_officer_manager', 'recruitment', 'Recruitment', 10),
  ('hr_officer_manager', 'payroll_benefits', 'Payroll & benefits', 20),
  ('hr_officer_manager', 'training_compliance', 'Training & compliance', 30),
  ('business_administrator_office_manager', 'office_administration', 'Office administration', 10),
  ('business_administrator_office_manager', 'operations_support', 'Operations support', 20),
  ('business_administrator_office_manager', 'executive_assistant', 'Executive assistant', 30),
  ('business_administrator_office_manager', 'records_documentation', 'Records & documentation', 40),
  ('consultant', 'strategy', 'Strategy', 10),
  ('consultant', 'operations', 'Operations', 20),
  ('consultant', 'finance', 'Finance', 30),
  ('consultant', 'compliance', 'Compliance', 40),
  ('professional_services_project_manager', 'business', 'Business', 10),
  ('professional_services_project_manager', 'compliance', 'Compliance', 20),
  ('professional_services_project_manager', 'operations', 'Operations', 30),
  ('teacher_tutor', 'primary', 'Primary', 10),
  ('teacher_tutor', 'secondary', 'Secondary', 20),
  ('teacher_tutor', 'university', 'University', 30),
  ('teacher_tutor', 'languages', 'Languages', 40),
  ('teacher_tutor', 'exam_prep', 'Exam prep', 50),
  ('trainer_instructor', 'computer_it', 'Computer / IT', 10),
  ('trainer_instructor', 'vocational_technical', 'Vocational / technical', 20),
  ('trainer_instructor', 'professional_corporate', 'Professional / corporate', 30),
  ('trainer_instructor', 'driving', 'Driving', 40),
  ('placement_coordinator', 'internships', 'Internships', 10),
  ('placement_coordinator', 'nursing_health', 'Nursing / health', 20),
  ('placement_coordinator', 'study_abroad', 'Study abroad', 30),
  ('placement_coordinator', 'university', 'University', 40),
  ('programme_manager', 'training_programmes', 'Training programmes', 10),
  ('programme_manager', 'placement_programmes', 'Placement programmes', 20),
  ('event_manager_planner', 'weddings', 'Weddings', 10),
  ('event_manager_planner', 'corporate', 'Corporate', 20),
  ('event_manager_planner', 'birthdays_parties', 'Birthdays & parties', 30),
  ('event_manager_planner', 'graduations', 'Graduations', 40),
  ('event_manager_planner', 'funerals_memorials', 'Funerals & memorials', 50),
  ('mc_dj', 'mc', 'MC', 10),
  ('mc_dj', 'dj', 'DJ', 20),
  ('mc_dj', 'both', 'Both', 30),
  ('event_crew_technician', 'sound', 'Sound', 10),
  ('event_crew_technician', 'lighting', 'Lighting', 20),
  ('event_crew_technician', 'tents_setup', 'Tents & setup', 30),
  ('event_crew_technician', 'stage', 'Stage', 40),
  ('caterer_chef', 'event_catering', 'Event catering', 10),
  ('caterer_chef', 'cakes_baking', 'Cakes & baking', 20),
  ('caterer_chef', 'buffet_plated', 'Buffet / plated', 30),
  ('event_supervisor', 'venue', 'Venue', 10),
  ('event_supervisor', 'logistics', 'Logistics', 20),
  ('event_supervisor', 'guest_management', 'Guest management', 30),
  ('photographer_videographer', 'weddings', 'Weddings', 10),
  ('photographer_videographer', 'corporate', 'Corporate', 20),
  ('photographer_videographer', 'fashion_portraits', 'Fashion & portraits', 30),
  ('photographer_videographer', 'music_videos', 'Music videos', 40),
  ('photographer_videographer', 'real_estate', 'Real estate', 50),
  ('photographer_videographer', 'graduations', 'Graduations', 60),
  ('audio_engineer_producer', 'recording', 'Recording', 10),
  ('audio_engineer_producer', 'mixing_mastering', 'Mixing & mastering', 20),
  ('audio_engineer_producer', 'beat_production', 'Beat production', 30),
  ('audio_engineer_producer', 'live_sound', 'Live sound', 40),
  ('performer_talent', 'singer', 'Singer', 10),
  ('performer_talent', 'dancer', 'Dancer', 20),
  ('performer_talent', 'actor', 'Actor', 30),
  ('performer_talent', 'model', 'Model', 40),
  ('performer_talent', 'extra', 'Extra', 50),
  ('production_manager', 'video_film', 'Video / film', 10),
  ('production_manager', 'music', 'Music', 20),
  ('production_manager', 'live_events', 'Live events', 30),
  ('makeup_artist', 'bridal', 'Bridal', 10),
  ('makeup_artist', 'fashion_editorial', 'Fashion / editorial', 20),
  ('makeup_artist', 'film_stage', 'Film / stage', 30),
  ('makeup_artist', 'everyday', 'Everyday', 40),
  ('hair_stylist', 'braiding', 'Braiding', 10),
  ('hair_stylist', 'salon_styling', 'Salon styling', 20),
  ('hair_stylist', 'bridal_hair', 'Bridal hair', 30),
  ('hair_stylist', 'barbering', 'Barbering', 40),
  ('stylist_designer', 'wardrobe_styling', 'Wardrobe styling', 10),
  ('stylist_designer', 'tailoring', 'Tailoring', 20),
  ('stylist_designer', 'bridal_wear', 'Bridal wear', 30),
  ('salon_studio_manager', 'salon', 'Salon', 10),
  ('salon_studio_manager', 'fashion_studio', 'Fashion studio', 20),
  ('site_manager', 'residential', 'Residential', 10),
  ('site_manager', 'commercial', 'Commercial', 20),
  ('site_manager', 'infrastructure', 'Infrastructure', 30),
  ('construction_building_project_manager', 'residential', 'Residential', 10),
  ('construction_building_project_manager', 'commercial', 'Commercial', 20),
  ('construction_building_project_manager', 'roads_civil', 'Roads & civil', 30),
  ('foreman_supervisor', 'masonry', 'Masonry', 10),
  ('foreman_supervisor', 'roofing', 'Roofing', 20),
  ('foreman_supervisor', 'concrete', 'Concrete', 30),
  ('foreman_supervisor', 'finishing', 'Finishing', 40),
  ('skilled_tradesperson', 'mason', 'Mason', 10),
  ('skilled_tradesperson', 'plumber', 'Plumber', 20),
  ('skilled_tradesperson', 'electrician', 'Electrician', 30),
  ('skilled_tradesperson', 'carpenter', 'Carpenter', 40),
  ('skilled_tradesperson', 'welder', 'Welder', 50),
  ('skilled_tradesperson', 'painter', 'Painter', 60),
  ('skilled_tradesperson', 'roofer', 'Roofer', 70),
  ('surveyor', 'land', 'Land', 10),
  ('surveyor', 'quantity', 'Quantity', 20),
  ('surveyor', 'topographic', 'Topographic', 30),
  ('solar_electrical_technician', 'solar_pv', 'Solar PV', 10),
  ('solar_electrical_technician', 'batteries_inverters', 'Batteries & inverters', 20),
  ('solar_electrical_technician', 'generators', 'Generators', 30),
  ('solar_electrical_technician', 'wiring', 'Wiring', 40),
  ('borehole_water_technician', 'drilling', 'Drilling', 10),
  ('borehole_water_technician', 'pump_installation', 'Pump installation', 20),
  ('borehole_water_technician', 'plumbing_tanks', 'Plumbing & tanks', 30),
  ('borehole_water_technician', 'water_treatment', 'Water treatment', 40),
  ('energy_engineer', 'solar_design', 'Solar design', 10),
  ('energy_engineer', 'energy_audits', 'Energy audits', 20),
  ('energy_engineer', 'grid_mini_grid', 'Grid / mini-grid', 30),
  ('energy_utilities_project_manager', 'solar', 'Solar', 10),
  ('energy_utilities_project_manager', 'water', 'Water', 20),
  ('energy_utilities_project_manager', 'electrification', 'Electrification', 30),
  ('driver', 'truck_heavy', 'Truck / heavy', 10),
  ('driver', 'pickup_van', 'Pickup / van', 20),
  ('driver', 'bus_minibus', 'Bus / minibus', 30),
  ('driver', 'motorcycle_courier', 'Motorcycle courier', 40),
  ('driver', 'tanker', 'Tanker', 50),
  ('fleet_operations_manager', 'trucks', 'Trucks', 10),
  ('fleet_operations_manager', 'vans_couriers', 'Vans & couriers', 20),
  ('fleet_operations_manager', 'mixed', 'Mixed', 30),
  ('dispatcher_coordinator', 'route_planning', 'Route planning', 10),
  ('dispatcher_coordinator', 'customs_clearing', 'Customs & clearing', 20),
  ('dispatcher_coordinator', 'warehouse', 'Warehouse', 30),
  ('loader_mover', 'moving', 'Moving', 10),
  ('loader_mover', 'warehouse', 'Warehouse', 20),
  ('loader_mover', 'loading', 'Loading', 30),
  ('machine_operator', 'excavator', 'Excavator', 10),
  ('machine_operator', 'loader', 'Loader', 20),
  ('machine_operator', 'grader', 'Grader', 30),
  ('machine_operator', 'crane', 'Crane', 40),
  ('machine_operator', 'tractor', 'Tractor', 50),
  ('machine_operator', 'roller', 'Roller', 60),
  ('machine_operator', 'forklift', 'Forklift', 70),
  ('machine_operator', 'bulldozer', 'Bulldozer', 80),
  ('machine_operator', 'concrete_mixer_pump', 'Concrete mixer / pump', 90),
  ('equipment_mechanic', 'heavy_plant', 'Heavy plant', 10),
  ('equipment_mechanic', 'generators', 'Generators', 20),
  ('equipment_mechanic', 'hydraulics', 'Hydraulics', 30),
  ('equipment_mechanic', 'electrical_systems', 'Electrical systems', 40),
  ('fleet_equipment_manager', 'construction_plant', 'Construction plant', 10),
  ('fleet_equipment_manager', 'farm_machinery', 'Farm machinery', 20),
  ('fleet_equipment_manager', 'industrial_equipment', 'Industrial equipment', 30),
  ('site_supervisor', 'earthworks', 'Earthworks', 10),
  ('site_supervisor', 'quarry_mining', 'Quarry / mining', 20),
  ('site_supervisor', 'farm', 'Farm', 30),
  ('farm_manager', 'crops', 'Crops', 10),
  ('farm_manager', 'dairy', 'Dairy', 20),
  ('farm_manager', 'poultry', 'Poultry', 30),
  ('farm_manager', 'mixed', 'Mixed', 40),
  ('agronomist_extension_officer', 'crops', 'Crops', 10),
  ('agronomist_extension_officer', 'soil_irrigation', 'Soil & irrigation', 20),
  ('agronomist_extension_officer', 'pest_management', 'Pest management', 30),
  ('veterinary_livestock_officer', 'cattle', 'Cattle', 10),
  ('veterinary_livestock_officer', 'poultry', 'Poultry', 20),
  ('veterinary_livestock_officer', 'small_ruminants', 'Small ruminants', 30),
  ('farm_worker_operator', 'tractor_operation', 'Tractor operation', 10),
  ('farm_worker_operator', 'irrigation', 'Irrigation', 20),
  ('farm_worker_operator', 'harvesting', 'Harvesting', 30),
  ('farm_worker_operator', 'spraying', 'Spraying', 40),
  ('procurement_officer_manager', 'industrial', 'Industrial', 10),
  ('procurement_officer_manager', 'electronics', 'Electronics', 20),
  ('procurement_officer_manager', 'medical_lab', 'Medical & lab', 30),
  ('procurement_officer_manager', 'general_supplies', 'General supplies', 40),
  ('sourcing_agent', 'local', 'Local', 10),
  ('sourcing_agent', 'china', 'China', 20),
  ('sourcing_agent', 'dubai', 'Dubai', 30),
  ('sourcing_agent', 'india', 'India', 40),
  ('sourcing_agent', 'europe_usa', 'Europe / USA', 50),
  ('clearing_customs_agent', 'imports', 'Imports', 10),
  ('clearing_customs_agent', 'exports', 'Exports', 20),
  ('clearing_customs_agent', 'freight_forwarding', 'Freight forwarding', 30),
  ('travel_agent_consultant', 'flights', 'Flights', 10),
  ('travel_agent_consultant', 'tours_packages', 'Tours & packages', 20),
  ('travel_agent_consultant', 'visas', 'Visas', 30),
  ('travel_agent_consultant', 'hajj_umrah', 'Hajj & Umrah', 40),
  ('travel_agent_consultant', 'relocation', 'Relocation', 50),
  ('tour_guide', 'wildlife_safari', 'Wildlife safari', 10),
  ('tour_guide', 'cultural', 'Cultural', 20),
  ('tour_guide', 'city_tours', 'City tours', 30),
  ('tour_guide', 'adventure', 'Adventure', 40),
  ('driver_guide', 'safari_vehicle', 'Safari vehicle', 10),
  ('driver_guide', 'minibus', 'Minibus', 20),
  ('driver_guide', 'airport_transfers', 'Airport transfers', 30),
  ('operations_manager', 'tours', 'Tours', 10),
  ('operations_manager', 'visa_documentation', 'Visa & documentation', 20),
  ('operations_manager', 'travel_desk', 'Travel desk', 30)
on conflict (role_slug, slug) do update set
  name = excluded.name,
  sort_order = excluded.sort_order;

alter table public.role_qualifications
  add column if not exists is_evidence boolean not null default false;

insert into public.role_qualifications (role_slug, slug, name, sort_order, is_evidence)
values
  ('developer', 'degree_diploma_in_it_or_cs', 'Degree / Diploma in IT or CS', 10, false),
  ('developer', 'portfolio_or_github_link', 'Portfolio or GitHub link', 20, false),
  ('developer', 'cloud_certification_aws_azure_gcp', 'Cloud certification (AWS/Azure/GCP)', 30, false),
  ('developer', '3_years_experience', '3+ years experience', 40, false),
  ('it_technician', 'comptia_a_n', 'CompTIA A+ / N+', 10, false),
  ('it_technician', 'ccna', 'CCNA', 20, false),
  ('it_technician', 'own_toolkit', 'Own toolkit', 30, false),
  ('it_technician', '2_years_experience', '2+ years experience', 40, false),
  ('security_specialist', 'ceh', 'CEH', 10, false),
  ('security_specialist', 'cissp_cism', 'CISSP / CISM', 20, false),
  ('security_specialist', 'iso_27001', 'ISO 27001', 30, false),
  ('security_specialist', 'police_clearance', 'Police clearance', 40, false),
  ('project_manager', 'pmp_prince2', 'PMP / PRINCE2', 10, false),
  ('project_manager', 'agile_scrum_certified', 'Agile / Scrum certified', 20, false),
  ('project_manager', 'led_3_projects', 'Led 3+ projects', 30, false),
  ('project_manager', 'degree', 'Degree', 40, false),
  ('team_lead_manager', 'managed_5_people', 'Managed 5+ people', 10, false),
  ('team_lead_manager', 'degree', 'Degree', 20, false),
  ('team_lead_manager', '3_years_leadership', '3+ years leadership', 30, false),
  ('marketer_specialist', 'marketing_diploma_degree', 'Marketing diploma / degree', 10, false),
  ('marketer_specialist', 'google_ads_meta_certified', 'Google Ads / Meta certified', 20, false),
  ('marketer_specialist', 'case_studies_or_portfolio', 'Case studies or portfolio', 30, false),
  ('marketer_specialist', '2_years_experience', '2+ years experience', 40, false),
  ('content_creator', 'portfolio', 'Portfolio', 10, false),
  ('content_creator', 'own_equipment', 'Own equipment', 20, false),
  ('content_creator', 'audience_size_proof', 'Audience size proof', 30, false),
  ('marketing_manager', 'degree', 'Degree', 10, false),
  ('marketing_manager', 'managed_budgets', 'Managed budgets', 20, false),
  ('marketing_manager', 'managed_3_people', 'Managed 3+ people', 30, false),
  ('campaign_project_manager', 'pmp_prince2', 'PMP / PRINCE2', 10, false),
  ('campaign_project_manager', 'led_3_campaigns', 'Led 3+ campaigns', 20, false),
  ('accountant_finance_officer', 'cpa_acca_cpa_u', 'CPA / ACCA / CPA-U', 10, false),
  ('accountant_finance_officer', 'degree', 'Degree', 20, false),
  ('accountant_finance_officer', 'practising_certificate', 'Practising certificate', 30, false),
  ('accountant_finance_officer', '3_years_experience', '3+ years experience', 40, false),
  ('lawyer_legal_officer', 'bar_admission_practising_certificate', 'Bar admission / practising certificate', 10, false),
  ('lawyer_legal_officer', 'llb', 'LLB', 20, false),
  ('lawyer_legal_officer', '3_years_experience', '3+ years experience', 30, false),
  ('engineer', 'degree_in_engineering', 'Degree in engineering', 10, false),
  ('engineer', 'registered_with_engineers_board', 'Registered with engineers board', 20, false),
  ('engineer', 'site_experience', 'Site experience', 30, false),
  ('architect_designer', 'registered_architect', 'Registered architect', 10, false),
  ('architect_designer', 'portfolio', 'Portfolio', 20, false),
  ('architect_designer', 'cad_bim_skills', 'CAD/BIM skills', 30, false),
  ('hr_officer_manager', 'hr_diploma_degree', 'HR diploma / degree', 10, false),
  ('hr_officer_manager', 'ihrm_cipd', 'IHRM / CIPD', 20, false),
  ('hr_officer_manager', '3_years_experience', '3+ years experience', 30, false),
  ('business_administrator_office_manager', 'diploma_degree_in_business_administration', 'Diploma / degree in business administration', 10, false),
  ('business_administrator_office_manager', 'office_software_skills_documents_spreadsheets_email', 'Office software skills (documents, spreadsheets, email)', 20, false),
  ('business_administrator_office_manager', '2_years_experience', '2+ years experience', 30, false),
  ('business_administrator_office_manager', 'references', 'References', 40, false),
  ('consultant', 'degree', 'Degree', 10, false),
  ('consultant', 'case_studies', 'Case studies', 20, false),
  ('consultant', '5_years_experience', '5+ years experience', 30, false),
  ('professional_services_project_manager', 'pmp_prince2', 'PMP / PRINCE2', 10, false),
  ('professional_services_project_manager', 'led_3_projects', 'Led 3+ projects', 20, false),
  ('teacher_tutor', 'teaching_certificate_degree', 'Teaching certificate / degree', 10, false),
  ('teacher_tutor', 'registered_with_teaching_board', 'Registered with teaching board', 20, false),
  ('teacher_tutor', '2_years_teaching', '2+ years teaching', 30, false),
  ('teacher_tutor', 'subject_specialisation', 'Subject specialisation', 40, false),
  ('trainer_instructor', 'trade_certificate', 'Trade certificate', 10, false),
  ('trainer_instructor', 'trainer_of_trainers_tot', 'Trainer-of-trainers (ToT)', 20, false),
  ('trainer_instructor', 'industry_experience_3_years', 'Industry experience 3+ years', 30, false),
  ('placement_coordinator', 'education_or_hr_background', 'Education or HR background', 10, false),
  ('placement_coordinator', 'partner_network', 'Partner network', 20, false),
  ('placement_coordinator', 'counselling_certificate', 'Counselling certificate', 30, false),
  ('programme_manager', 'degree', 'Degree', 10, false),
  ('programme_manager', 'managed_3_programmes', 'Managed 3+ programmes', 20, false),
  ('event_manager_planner', 'event_planning_certificate', 'Event planning certificate', 10, false),
  ('event_manager_planner', 'portfolio_of_5_events', 'Portfolio of 5+ events', 20, false),
  ('event_manager_planner', 'insurance_permit', 'Insurance / permit', 30, false),
  ('event_manager_planner', 'team_of_3_staff', 'Team of 3+ staff', 40, false),
  ('mc_dj', 'own_equipment', 'Own equipment', 10, false),
  ('mc_dj', 'sample_mix_video', 'Sample mix / video', 20, false),
  ('mc_dj', 'references', 'References', 30, false),
  ('event_crew_technician', 'technical_training', 'Technical training', 10, false),
  ('event_crew_technician', 'own_tools', 'Own tools', 20, false),
  ('event_crew_technician', 'event_experience_1_year', 'Event experience 1+ year', 30, false),
  ('caterer_chef', 'food_handler_certificate', 'Food handler certificate', 10, false),
  ('caterer_chef', 'health_permit', 'Health permit', 20, false),
  ('caterer_chef', 'culinary_diploma', 'Culinary diploma', 30, false),
  ('event_supervisor', 'managed_5_events', 'Managed 5+ events', 10, false),
  ('event_supervisor', 'team_leadership', 'Team leadership', 20, false),
  ('photographer_videographer', 'portfolio_link', 'Portfolio link', 10, false),
  ('photographer_videographer', 'own_camera_drone_kit', 'Own camera / drone kit', 20, false),
  ('photographer_videographer', 'drone_licence', 'Drone licence', 30, false),
  ('photographer_videographer', 'editing_skills', 'Editing skills', 40, false),
  ('audio_engineer_producer', 'own_studio_daw', 'Own studio / DAW', 10, false),
  ('audio_engineer_producer', 'portfolio', 'Portfolio', 20, false),
  ('audio_engineer_producer', 'audio_engineering_diploma', 'Audio engineering diploma', 30, false),
  ('performer_talent', 'showreel_audition_clip', 'Showreel / audition clip', 10, false),
  ('performer_talent', 'agency_representation', 'Agency representation', 20, false),
  ('performer_talent', 'performance_experience', 'Performance experience', 30, false),
  ('production_manager', 'managed_3_productions', 'Managed 3+ productions', 10, false),
  ('production_manager', 'budget_handling', 'Budget handling', 20, false),
  ('production_manager', 'crew_network', 'Crew network', 30, false),
  ('makeup_artist', 'cosmetology_certificate', 'Cosmetology certificate', 10, false),
  ('makeup_artist', 'portfolio', 'Portfolio', 20, false),
  ('makeup_artist', 'own_kit', 'Own kit', 30, false),
  ('makeup_artist', 'hygiene_certification', 'Hygiene certification', 40, false),
  ('hair_stylist', 'cosmetology_certificate', 'Cosmetology certificate', 10, false),
  ('hair_stylist', 'portfolio', 'Portfolio', 20, false),
  ('hair_stylist', 'salon_licence', 'Salon licence', 30, false),
  ('stylist_designer', 'fashion_diploma', 'Fashion diploma', 10, false),
  ('stylist_designer', 'portfolio', 'Portfolio', 20, false),
  ('stylist_designer', 'own_workshop', 'Own workshop', 30, false),
  ('salon_studio_manager', 'managed_3_staff', 'Managed 3+ staff', 10, false),
  ('salon_studio_manager', 'business_licence', 'Business licence', 20, false),
  ('site_manager', 'civil_construction_diploma_or_degree', 'Civil/Construction diploma or degree', 10, false),
  ('site_manager', 'registered_with_engineers_contractors_board', 'Registered with engineers/contractors board', 20, false),
  ('site_manager', '5_years_on_site', '5+ years on site', 30, false),
  ('site_manager', 'safety_certification_osha', 'Safety certification (OSHA)', 40, false),
  ('construction_building_project_manager', 'pmp_prince2', 'PMP / PRINCE2', 10, false),
  ('construction_building_project_manager', 'degree', 'Degree', 20, false),
  ('construction_building_project_manager', 'delivered_3_projects', 'Delivered 3+ projects', 30, false),
  ('foreman_supervisor', 'trade_test_certificate', 'Trade test certificate', 10, false),
  ('foreman_supervisor', 'managed_10_workers', 'Managed 10+ workers', 20, false),
  ('foreman_supervisor', 'safety_training', 'Safety training', 30, false),
  ('skilled_tradesperson', 'trade_test_grade_i_ii_iii', 'Trade test (Grade I/II/III)', 10, false),
  ('skilled_tradesperson', 'licence_electrical_plumbing', 'Licence (electrical/plumbing)', 20, false),
  ('skilled_tradesperson', 'own_tools', 'Own tools', 30, false),
  ('skilled_tradesperson', '2_years_experience', '2+ years experience', 40, false),
  ('surveyor', 'registered_surveyor', 'Registered surveyor', 10, false),
  ('surveyor', 'degree_diploma', 'Degree / diploma', 20, false),
  ('surveyor', 'own_instruments', 'Own instruments', 30, false),
  ('solar_electrical_technician', 'electrical_licence', 'Electrical licence', 10, false),
  ('solar_electrical_technician', 'solar_installer_certificate', 'Solar installer certificate', 20, false),
  ('solar_electrical_technician', 'safety_training', 'Safety training', 30, false),
  ('solar_electrical_technician', 'own_tools', 'Own tools', 40, false),
  ('borehole_water_technician', 'water_technician_certificate', 'Water technician certificate', 10, false),
  ('borehole_water_technician', 'drilling_permit', 'Drilling permit', 20, false),
  ('borehole_water_technician', 'own_equipment', 'Own equipment', 30, false),
  ('energy_engineer', 'engineering_degree', 'Engineering degree', 10, false),
  ('energy_engineer', 'registered_engineer', 'Registered engineer', 20, false),
  ('energy_engineer', 'design_software_skills', 'Design software skills', 30, false),
  ('energy_utilities_project_manager', 'pmp_prince2', 'PMP / PRINCE2', 10, false),
  ('energy_utilities_project_manager', 'delivered_3_projects', 'Delivered 3+ projects', 20, false),
  ('driver', 'valid_driving_licence_class', 'Valid driving licence (class)', 10, false),
  ('driver', 'psv_badge', 'PSV badge', 20, false),
  ('driver', 'clean_driving_record', 'Clean driving record', 30, false),
  ('driver', 'defensive_driving_certificate', 'Defensive driving certificate', 40, false),
  ('driver', 'own_vehicle', 'Own vehicle', 50, false),
  ('fleet_operations_manager', 'logistics_diploma_degree', 'Logistics diploma / degree', 10, false),
  ('fleet_operations_manager', 'managed_10_vehicles', 'Managed 10+ vehicles', 20, false),
  ('fleet_operations_manager', 'transport_licence', 'Transport licence', 30, false),
  ('dispatcher_coordinator', 'logistics_experience', 'Logistics experience', 10, false),
  ('dispatcher_coordinator', 'customs_clearing_licence', 'Customs clearing licence', 20, false),
  ('loader_mover', 'physical_fitness', 'Physical fitness', 10, false),
  ('loader_mover', 'experience_1_year', 'Experience 1+ year', 20, false),
  ('machine_operator', 'operator_licence_certificate', 'Operator licence / certificate', 10, false),
  ('machine_operator', 'safety_osha_certificate', 'Safety / OSHA certificate', 20, false),
  ('machine_operator', '3_years_experience', '3+ years experience', 30, false),
  ('machine_operator', 'medical_fitness', 'Medical fitness', 40, false),
  ('machine_operator', 'can_work_away_from_home', 'Can work away from home', 50, false),
  ('equipment_mechanic', 'mechanic_trade_certificate', 'Mechanic trade certificate', 10, false),
  ('equipment_mechanic', 'own_tools', 'Own tools', 20, false),
  ('equipment_mechanic', 'field_repair_experience', 'Field repair experience', 30, false),
  ('fleet_equipment_manager', 'managed_fleet_of_5_machines', 'Managed fleet of 5+ machines', 10, false),
  ('fleet_equipment_manager', 'diploma_degree', 'Diploma / degree', 20, false),
  ('fleet_equipment_manager', 'maintenance_scheduling', 'Maintenance scheduling', 30, false),
  ('site_supervisor', 'plant_experience', 'Plant experience', 10, false),
  ('site_supervisor', 'team_leadership', 'Team leadership', 20, false),
  ('site_supervisor', 'safety_certification', 'Safety certification', 30, false),
  ('farm_manager', 'agriculture_diploma_degree', 'Agriculture diploma / degree', 10, false),
  ('farm_manager', 'managed_5_workers', 'Managed 5+ workers', 20, false),
  ('farm_manager', '5_years_farming_experience', '5+ years farming experience', 30, false),
  ('agronomist_extension_officer', 'degree_diploma_in_agronomy', 'Degree / diploma in agronomy', 10, false),
  ('agronomist_extension_officer', 'field_experience', 'Field experience', 20, false),
  ('veterinary_livestock_officer', 'veterinary_licence', 'Veterinary licence', 10, false),
  ('veterinary_livestock_officer', 'diploma_degree', 'Diploma / degree', 20, false),
  ('veterinary_livestock_officer', 'vaccination_certification', 'Vaccination certification', 30, false),
  ('farm_worker_operator', 'tractor_licence', 'Tractor licence', 10, false),
  ('farm_worker_operator', 'pesticide_handling_certificate', 'Pesticide handling certificate', 20, false),
  ('farm_worker_operator', 'experience_1_year', 'Experience 1+ year', 30, false),
  ('procurement_officer_manager', 'procurement_diploma_cips_or_similar', 'Procurement diploma (CIPS or similar)', 10, false),
  ('procurement_officer_manager', 'supplier_network', 'Supplier network', 20, false),
  ('procurement_officer_manager', '3_years_experience', '3+ years experience', 30, false),
  ('sourcing_agent', 'import_export_experience', 'Import/export experience', 10, false),
  ('sourcing_agent', 'language_skills', 'Language skills', 20, false),
  ('sourcing_agent', 'supplier_contacts', 'Supplier contacts', 30, false),
  ('clearing_customs_agent', 'customs_clearing_licence', 'Customs clearing licence', 10, false),
  ('clearing_customs_agent', 'logistics_experience', 'Logistics experience', 20, false),
  ('travel_agent_consultant', 'iata_certification', 'IATA certification', 10, false),
  ('travel_agent_consultant', 'travel_agency_licence', 'Travel agency licence', 20, false),
  ('travel_agent_consultant', '2_years_experience', '2+ years experience', 30, false),
  ('tour_guide', 'tourism_board_guide_licence', 'Tourism board guide licence', 10, false),
  ('tour_guide', 'first_aid_certificate', 'First aid certificate', 20, false),
  ('tour_guide', 'languages_spoken', 'Languages spoken', 30, false),
  ('driver_guide', 'valid_driving_licence_class', 'Valid driving licence (class)', 10, false),
  ('driver_guide', 'tourism_licence', 'Tourism licence', 20, false),
  ('driver_guide', 'clean_driving_record', 'Clean driving record', 30, false),
  ('operations_manager', 'tourism_diploma_degree', 'Tourism diploma / degree', 10, false),
  ('operations_manager', 'managed_3_staff', 'Managed 3+ staff', 20, false)
on conflict (role_slug, slug) do update set
  name = excluded.name,
  sort_order = excluded.sort_order,
  is_evidence = excluded.is_evidence;


-- 6. Atomic bulk save RPC for Provider Capabilities
create or replace function public.save_provider_capabilities(
  p_items jsonb default '[]'::jsonb,
  p_category_slug text default null,
  p_remove_slugs text[] default array[]::text[]
)
returns setof public.provider_capabilities
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_max_cap int := 30;
  v_current_count int;
  v_item record;
  v_slug text;
  v_meta jsonb;
  v_incoming_slugs text[] := array[]::text[];
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select coalesce(nullif(setting_value, '')::int, 30)
  into v_max_cap
  from public.system_settings
  where setting_key = 'max_provider_capabilities'
    and (country is null or country = '__global__')
  limit 1;
  v_max_cap := coalesce(v_max_cap, 30);

  -- Extract incoming slugs
  for v_item in select * from jsonb_to_recordset(p_items) as x(capability_slug text, metadata jsonb)
  loop
    v_incoming_slugs := array_append(v_incoming_slugs, v_item.capability_slug);
  end loop;

  -- Calculate anticipated total
  select count(*)
  into v_current_count
  from public.provider_capabilities pc
  join public.need_capabilities nc on nc.slug = pc.capability_slug
  where pc.user_id = v_user_id
    and (
      (p_category_slug is not null and nc.category_slug <> p_category_slug)
      or (p_category_slug is null and not (pc.capability_slug = any(p_remove_slugs)))
    );

  if (v_current_count + coalesce(array_length(v_incoming_slugs, 1), 0)) > v_max_cap then
    raise exception 'Maximum limit of % provider capabilities reached.' , v_max_cap
      using errcode = 'P0206';
  end if;

  -- Process explicit removals
  if p_remove_slugs is not null and array_length(p_remove_slugs, 1) > 0 then
    delete from public.provider_capabilities
    where user_id = v_user_id
      and capability_slug = any(p_remove_slugs);
  end if;

  -- Process category-scoped un-ticked removals
  if p_category_slug is not null then
    delete from public.provider_capabilities pc
    using public.need_capabilities nc
    where pc.capability_slug = nc.slug
      and pc.user_id = v_user_id
      and nc.category_slug = p_category_slug
      and not (pc.capability_slug = any(v_incoming_slugs));
  end if;

  -- Upsert items
  for v_item in select * from jsonb_to_recordset(p_items) as x(capability_slug text, metadata jsonb)
  loop
    insert into public.provider_capabilities (
      user_id,
      capability_slug,
      verification_level,
      metadata,
      created_at
    )
    values (
      v_user_id,
      v_item.capability_slug,
      'self_declared',
      coalesce(v_item.metadata, '{}'::jsonb),
      now()
    )
    on conflict (user_id, capability_slug) do update set
      metadata = case
        when excluded.metadata is not null and excluded.metadata <> '{}'::jsonb
          then excluded.metadata
        else public.provider_capabilities.metadata
      end;
  end loop;

  return query
  select * from public.provider_capabilities
  where user_id = v_user_id;
end;
$$;

grant execute on function public.save_provider_capabilities to authenticated;

-- Helper to safely convert JSONB array to text array
create or replace function private.jsonb_text_array(p_value jsonb)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(x.value), array[]::text[])
  from jsonb_array_elements_text(
    case
      when jsonb_typeof(p_value) = 'array' then p_value
      else '[]'::jsonb
    end
  ) as x(value);
$$;

-- 7. Matching Function
create or replace function private.capability_match_score(
  p_need_details jsonb,
  p_provider_metadata jsonb
)
returns integer
language plpgsql
immutable
as $$
declare
  v_role_id text := nullif(btrim(coalesce(p_need_details->>'role_id', '')), '');
  v_need_kinds text[] := private.jsonb_text_array(p_need_details->'kind_ids');
  v_required_quals text[] := private.jsonb_text_array(p_need_details->'required_qualification_ids');
  v_role jsonb;
  v_role_kinds text[];
  v_role_quals text[];
  v_matched_quals int := 0;
  v_total_quals int := coalesce(array_length(v_required_quals, 1), 0);
begin
  if coalesce(p_need_details->>'engagement', '') <> 'hire_person' then
    return 100;
  end if;

  -- Direct metadata format (single role work capability)
  if p_provider_metadata ? 'kind_ids' or p_provider_metadata ? 'qualification_ids' then
    v_role_kinds := private.jsonb_text_array(p_provider_metadata->'kind_ids');
    v_role_quals := private.jsonb_text_array(p_provider_metadata->'qualification_ids');

    if coalesce(array_length(v_need_kinds, 1), 0) > 0
       and not (v_need_kinds && v_role_kinds) then
      return 0;
    end if;

    if v_total_quals = 0 then
      return 100;
    end if;

    select count(*)::int
    into v_matched_quals
    from unnest(v_required_quals) q
    where q = any(v_role_quals);

    return round((v_matched_quals::numeric / v_total_quals::numeric) * 100)::int;
  end if;

  -- Array format fallback
  if p_provider_metadata ? 'roles' then
    for v_role in select jsonb_array_elements(p_provider_metadata->'roles')
    loop
      if v_role->>'role_id' = v_role_id then
        v_role_kinds := private.jsonb_text_array(v_role->'kind_ids');
        v_role_quals := private.jsonb_text_array(v_role->'qualification_ids');

        if coalesce(array_length(v_need_kinds, 1), 0) > 0
           and not (v_need_kinds && v_role_kinds) then
          continue;
        end if;

        if v_total_quals = 0 then
          return 100;
        end if;

        select count(*)::int
        into v_matched_quals
        from unnest(v_required_quals) q
        where q = any(v_role_quals);

        return round((v_matched_quals::numeric / v_total_quals::numeric) * 100)::int;
      end if;
    end loop;
  end if;

  return 0;
end;
$$;

-- 8. Status view
drop view if exists public.v_my_capability_status cascade;
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
  nc.capability_type
from public.provider_capabilities pc
join public.need_capabilities nc on nc.slug = pc.capability_slug
join public.need_categories cat on cat.slug = nc.category_slug
left join evidence_summary es on es.provider_capability_id = pc.id
left join latest_rejection lr on lr.provider_capability_id = pc.id
where pc.user_id = auth.uid() or private.is_admin();

grant select on public.v_my_capability_status to authenticated;

-- 9. System settings flags
insert into public.system_settings
  (setting_key, country, setting_value, setting_type, category, description, is_public)
values
  ('capability_profiles_enabled', null, 'false', 'boolean', 'provider',
   'Enables Provider Services v2 multi-capability flow.', true),
  ('work_profiles_enabled', null, 'false', 'boolean', 'provider',
   'Enables Work Profiles and roles across categories.', true),
  ('max_provider_capabilities', null, '30', 'number', 'provider',
   'Maximum number of provider capabilities per user.', true),
  ('work_profile_requires_kyc', null, 'true', 'boolean', 'provider',
   'Requires approved KYC status for work profile marketplace matching.', true),
  ('hire_person_needs_enabled', null, 'false', 'boolean', 'provider',
   'Allows posting hire-person Needs.', true)
on conflict (setting_key, coalesce(country, '__global__')) do update set
  setting_type = excluded.setting_type,
  category = excluded.category,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();

commit;
