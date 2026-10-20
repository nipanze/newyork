-- Provider Services v2 catalog synchronization.
-- Source: provider_services_v2.json
-- Apply in Supabase SQL Editor after the base schema and capability-profile patch.
-- Safe to re-run. Existing capability slugs are preserved when they already
-- represent the same service, so provider_capabilities and saved offers remain linked.
-- The repeated Project Manager role gets category-scoped slugs because
-- capability_roles.slug is globally unique in the existing schema.

begin;

do $$
begin
  if to_regclass('public.need_categories') is null
     or to_regclass('public.need_capabilities') is null
     or to_regclass('public.capability_roles') is null
     or to_regclass('public.role_kinds') is null
     or to_regclass('public.role_qualifications') is null
     or to_regclass('public.system_settings') is null then
    raise exception 'Provider Services base tables are missing. Apply the base schema and capability-profile patch first.';
  end if;
end;
$$;

alter table public.need_categories
  add column if not exists description text;

alter table public.need_capabilities
  add column if not exists ui_group_slug text,
  add column if not exists sort_order integer not null default 1000,
  add column if not exists service_group_slug text,
  add column if not exists service_group_name text,
  add column if not exists service_sort_order integer not null default 1000;

comment on column public.need_capabilities.ui_group_slug is
  'Provider Services v2 top-level category id from provider_services_v2.json.';
comment on column public.need_capabilities.service_group_slug is
  'Provider Services v2 service-group id, scoped by category_slug.';
comment on column public.need_capabilities.service_group_name is
  'Provider Services v2 service-group display label.';
comment on column public.need_capabilities.service_sort_order is
  'Display order of the service within its Provider Services v2 group.';

-- Use existing backend category slugs to avoid changing foreign keys and saved data.
insert into public.need_categories
  (slug, name, icon, sort_order, description, is_active)
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

-- Canonical v2 offers, reusing established database slugs for equivalent services.
insert into public.need_capabilities
  (slug, category_slug, name, is_active, ui_group_slug, sort_order,
   service_group_slug, service_group_name, service_sort_order)
values
  ('software_development', 'technology_digital', 'Software Development', true, 'technology_digital', 110, 'build', 'Build', 10),
  ('website_development', 'technology_digital', 'Website Development', true, 'technology_digital', 120, 'build', 'Build', 20),
  ('mobile_app_development', 'technology_digital', 'Mobile App Development', true, 'technology_digital', 130, 'build', 'Build', 30),
  ('automation_services', 'technology_digital', 'Automation', true, 'technology_digital', 140, 'build', 'Build', 40),
  ('it_support', 'technology_digital', 'IT Support', true, 'technology_digital', 210, 'support_infrastructure', 'Support & Infrastructure', 10),
  ('networking_services', 'technology_digital', 'Networking', true, 'technology_digital', 220, 'support_infrastructure', 'Support & Infrastructure', 20),
  ('cybersecurity_services', 'technology_digital', 'Cybersecurity', true, 'technology_digital', 230, 'support_infrastructure', 'Support & Infrastructure', 30),
  ('other_technology', 'technology_digital', 'Other Technology', true, 'technology_digital', 310, 'other', 'Other', 10),
  ('digital_marketing', 'marketing_promotion', 'Digital Marketing', true, 'marketing_promotion', 110, 'campaigns', 'Campaigns', 10),
  ('social_media_marketing', 'marketing_promotion', 'Social Media Marketing', true, 'marketing_promotion', 120, 'campaigns', 'Campaigns', 20),
  ('advertising_campaigns', 'marketing_promotion', 'Advertising Campaigns', true, 'marketing_promotion', 130, 'campaigns', 'Campaigns', 30),
  ('brand_promotion', 'marketing_promotion', 'Brand Promotion', true, 'marketing_promotion', 140, 'campaigns', 'Campaigns', 40),
  ('event_promotion', 'marketing_promotion', 'Event Promotion', true, 'marketing_promotion', 150, 'campaigns', 'Campaigns', 50),
  ('affiliate_marketing', 'marketing_promotion', 'Affiliate Marketing', true, 'marketing_promotion', 160, 'campaigns', 'Campaigns', 60),
  ('content_creation', 'marketing_promotion', 'Content Creation', true, 'marketing_promotion', 210, 'content_reach', 'Content & Reach', 10),
  ('influencer_marketing', 'marketing_promotion', 'Influencer Marketing', true, 'marketing_promotion', 220, 'content_reach', 'Content & Reach', 20),
  ('product_reviews', 'marketing_promotion', 'Product Reviews', true, 'marketing_promotion', 230, 'content_reach', 'Content & Reach', 30),
  ('i_have_an_audience', 'marketing_promotion', 'I Have an Audience', true, 'marketing_promotion', 240, 'content_reach', 'Content & Reach', 40),
  ('other_marketing_services', 'marketing_promotion', 'Other Marketing Services', true, 'marketing_promotion', 310, 'other', 'Other', 10),
  ('accounting_tax', 'professional_services', 'Accounting & Tax', true, 'business_professional_services', 110, 'finance_legal', 'Finance & Legal', 10),
  ('legal_services', 'professional_services', 'Legal Services', true, 'business_professional_services', 120, 'finance_legal', 'Finance & Legal', 20),
  ('company_registration', 'professional_services', 'Company Registration', true, 'business_professional_services', 130, 'finance_legal', 'Finance & Legal', 30),
  ('business_consulting', 'professional_services', 'Business Consulting', true, 'business_professional_services', 210, 'advisory', 'Advisory', 10),
  ('hr_services', 'professional_services', 'HR Services', true, 'business_professional_services', 220, 'advisory', 'Advisory', 20),
  ('architecture_services', 'professional_services', 'Architecture', true, 'business_professional_services', 310, 'design_engineering', 'Design & Engineering', 10),
  ('engineering_consulting', 'professional_services', 'Engineering', true, 'business_professional_services', 320, 'design_engineering', 'Design & Engineering', 20),
  ('driving_school', 'professional_services', 'Driving School / Driver Training', true, 'business_professional_services', 330, 'design_engineering', 'Design & Engineering', 30),
  ('other_professional', 'professional_services', 'Other Professional Services', true, 'business_professional_services', 410, 'other', 'Other', 10),
  ('private_tutoring', 'education_training', 'Private Tutoring', true, 'education_training', 110, 'learning', 'Learning', 10),
  ('online_classes', 'education_training', 'Online Classes', true, 'education_training', 120, 'learning', 'Learning', 20),
  ('exam_preparation', 'education_training', 'Exam Preparation', true, 'education_training', 130, 'learning', 'Learning', 30),
  ('language_training', 'education_training', 'Language Training', true, 'education_training', 140, 'learning', 'Learning', 40),
  ('computer_training', 'education_training', 'Computer Training', true, 'education_training', 150, 'learning', 'Learning', 50),
  ('professional_training', 'education_training', 'Professional Training', true, 'education_training', 160, 'learning', 'Learning', 60),
  ('vocational_training', 'education_training', 'Vocational Training', true, 'education_training', 170, 'learning', 'Learning', 70),
  ('academic_consulting', 'education_training', 'Academic Consulting', true, 'education_training', 180, 'learning', 'Learning', 80),
  ('university_admissions', 'education_training', 'University Admissions', true, 'education_training', 210, 'admissions_placements', 'Admissions & Placements', 10),
  ('study_abroad_guidance', 'education_training', 'Study Abroad Guidance', true, 'education_training', 220, 'admissions_placements', 'Admissions & Placements', 20),
  ('internship_placement', 'education_training', 'Internship Placement', true, 'education_training', 230, 'admissions_placements', 'Admissions & Placements', 30),
  ('health_nursing_placements', 'education_training', 'Health / Nursing Placements', true, 'education_training', 240, 'admissions_placements', 'Admissions & Placements', 40),
  ('event_planning', 'events_production', 'Event Planning', true, 'events_celebrations', 110, 'planning_styling', 'Planning & Styling', 10),
  ('event_decoration', 'events_production', 'Decoration', true, 'events_celebrations', 120, 'planning_styling', 'Planning & Styling', 20),
  ('celebration_cakes', 'events_production', 'Cakes', true, 'events_celebrations', 130, 'planning_styling', 'Planning & Styling', 30),
  ('celebration_catering', 'events_production', 'Catering', true, 'events_celebrations', 140, 'planning_styling', 'Planning & Styling', 40),
  ('tent_hire', 'events_production', 'Tents', true, 'events_celebrations', 210, 'equipment_venue_setup', 'Equipment & Venue Setup', 10),
  ('event_equipment', 'events_production', 'Event Equipment', true, 'events_celebrations', 220, 'equipment_venue_setup', 'Equipment & Venue Setup', 20),
  ('sound_systems', 'events_production', 'Sound Systems', true, 'events_celebrations', 230, 'equipment_venue_setup', 'Equipment & Venue Setup', 30),
  ('lighting_hire', 'events_production', 'Lighting', true, 'events_celebrations', 240, 'equipment_venue_setup', 'Equipment & Venue Setup', 40),
  ('celebration_mc_dj', 'events_production', 'DJs / MCs', true, 'events_celebrations', 310, 'entertainment_hosting', 'Entertainment & Hosting', 10),
  ('event_transport', 'events_production', 'Event Transport', true, 'events_celebrations', 320, 'entertainment_hosting', 'Entertainment & Hosting', 20),
  ('other_events', 'events_production', 'Other Events', true, 'events_celebrations', 410, 'other', 'Other', 10),
  ('photography_services', 'photo_video_music_talent', 'Photography', true, 'photo_video_music_talent', 110, 'photo_video', 'Photo & Video', 10),
  ('videography_services', 'photo_video_music_talent', 'Videography', true, 'photo_video_music_talent', 120, 'photo_video', 'Photo & Video', 20),
  ('video_editors', 'photo_video_music_talent', 'Video Editors', true, 'photo_video_music_talent', 130, 'photo_video', 'Photo & Video', 30),
  ('recording_studios', 'photo_video_music_talent', 'Recording Studios', true, 'photo_video_music_talent', 210, 'music_production', 'Music Production', 10),
  ('music_producers', 'photo_video_music_talent', 'Music Producers', true, 'photo_video_music_talent', 220, 'music_production', 'Music Production', 20),
  ('mixing_mastering', 'photo_video_music_talent', 'Mixing & Mastering', true, 'photo_video_music_talent', 230, 'music_production', 'Music Production', 30),
  ('songwriters', 'photo_video_music_talent', 'Songwriters', true, 'photo_video_music_talent', 240, 'music_production', 'Music Production', 40),
  ('singers_vocalists', 'photo_video_music_talent', 'Singers / Vocalists', true, 'photo_video_music_talent', 250, 'music_production', 'Music Production', 50),
  ('actors_actresses', 'photo_video_music_talent', 'Actors / Actresses', true, 'photo_video_music_talent', 310, 'on_screen_performers', 'On-screen & Performers', 10),
  ('dancers', 'photo_video_music_talent', 'Dancers', true, 'photo_video_music_talent', 320, 'on_screen_performers', 'On-screen & Performers', 20),
  ('background_extras', 'photo_video_music_talent', 'Background Extras', true, 'photo_video_music_talent', 330, 'on_screen_performers', 'On-screen & Performers', 30),
  ('music_video_models', 'photo_video_music_talent', 'Music Video Models', true, 'photo_video_music_talent', 340, 'on_screen_performers', 'On-screen & Performers', 40),
  ('celebration_makeup', 'beauty_fashion_styling', 'Makeup Artists', true, 'beauty_fashion_styling', 110, 'beauty', 'Beauty', 10),
  ('hair_styling', 'beauty_fashion_styling', 'Hair Stylists', true, 'beauty_fashion_styling', 120, 'beauty', 'Beauty', 20),
  ('bridal_styling', 'beauty_fashion_styling', 'Bridal Styling', true, 'beauty_fashion_styling', 210, 'fashion', 'Fashion', 10),
  ('music_video_stylists', 'beauty_fashion_styling', 'Stylists', true, 'beauty_fashion_styling', 220, 'fashion', 'Fashion', 20),
  ('dresses_bridesmaid_outfits', 'beauty_fashion_styling', 'Wedding Dresses / Bridesmaid Outfits', true, 'beauty_fashion_styling', 230, 'fashion', 'Fashion', 30),
  ('building_contractors', 'construction_building', 'Building Contractors', true, 'construction_building', 110, 'contracting', 'Contracting', 10),
  ('roofing_services', 'construction_building', 'Roofing', true, 'construction_building', 120, 'contracting', 'Contracting', 20),
  ('excavation_works', 'construction_building', 'Excavation', true, 'construction_building', 130, 'contracting', 'Contracting', 30),
  ('concrete_works', 'construction_building', 'Concrete', true, 'construction_building', 140, 'contracting', 'Contracting', 40),
  ('plumbing_services', 'construction_building', 'Plumbing', true, 'construction_building', 210, 'trades', 'Trades', 10),
  ('electrical_works', 'construction_building', 'Electrical Works', true, 'construction_building', 220, 'trades', 'Trades', 20),
  ('construction_materials', 'construction_building', 'Construction Materials', true, 'construction_building', 310, 'materials_survey', 'Materials & Survey', 10),
  ('surveying_services', 'construction_building', 'Surveying', true, 'construction_building', 320, 'materials_survey', 'Materials & Survey', 20),
  ('other_construction', 'construction_building', 'Other Construction', true, 'construction_building', 410, 'other', 'Other', 10),
  ('solar_systems', 'energy_utilities', 'Solar Systems', true, 'energy_water', 110, 'power', 'Power', 10),
  ('battery_supply', 'energy_utilities', 'Batteries', true, 'energy_water', 120, 'power', 'Power', 20),
  ('backup_power', 'energy_utilities', 'Backup Power', true, 'energy_water', 130, 'power', 'Power', 30),
  ('generator_supply', 'energy_utilities', 'Generators', true, 'energy_water', 140, 'power', 'Power', 40),
  ('electrical_installation', 'energy_utilities', 'Electrical Installation', true, 'energy_water', 150, 'power', 'Power', 50),
  ('borehole_drilling', 'energy_utilities', 'Boreholes', true, 'energy_water', 210, 'water', 'Water', 10),
  ('water_systems', 'energy_utilities', 'Water Systems', true, 'energy_water', 220, 'water', 'Water', 20),
  ('energy_consulting', 'energy_utilities', 'Energy Consulting', true, 'energy_water', 310, 'advisory', 'Advisory', 10),
  ('other_energy', 'energy_utilities', 'Other Energy Services', true, 'energy_water', 320, 'advisory', 'Advisory', 20),
  ('cargo_transport', 'transport_logistics', 'Cargo Transport', true, 'transport_logistics', 110, 'freight', 'Freight', 10),
  ('bulk_delivery', 'transport_logistics', 'Bulk Delivery', true, 'transport_logistics', 120, 'freight', 'Freight', 20),
  ('heavy_haulage', 'transport_logistics', 'Heavy Haulage', true, 'transport_logistics', 130, 'freight', 'Freight', 30),
  ('agricultural_transport', 'transport_logistics', 'Agricultural Transport', true, 'transport_logistics', 140, 'freight', 'Freight', 40),
  ('cold_chain_transport', 'transport_logistics', 'Cold Chain & Refrigerated', true, 'transport_logistics', 150, 'freight', 'Freight', 50),
  ('courier_delivery', 'transport_logistics', 'Courier', true, 'transport_logistics', 210, 'delivery_moving', 'Delivery & Moving', 10),
  ('moving_services', 'transport_logistics', 'Moving Services', true, 'transport_logistics', 220, 'delivery_moving', 'Delivery & Moving', 20),
  ('truck_hire', 'transport_logistics', 'Truck Hire', true, 'transport_logistics', 310, 'vehicles', 'Vehicles', 10),
  ('vehicle_transport', 'transport_logistics', 'Vehicle Transport', true, 'transport_logistics', 320, 'vehicles', 'Vehicles', 20),
  ('other_logistics', 'transport_logistics', 'Other Logistics', true, 'transport_logistics', 410, 'other', 'Other', 10),
  ('excavator_hire', 'machinery_equipment', 'Excavator Hire', true, 'machinery_equipment', 110, 'earthmoving', 'Earthmoving', 10),
  ('loader_hire', 'machinery_equipment', 'Loader Hire', true, 'machinery_equipment', 120, 'earthmoving', 'Earthmoving', 20),
  ('grader_hire', 'machinery_equipment', 'Grader Hire', true, 'machinery_equipment', 130, 'earthmoving', 'Earthmoving', 30),
  ('crane_hire', 'machinery_equipment', 'Crane Hire', true, 'machinery_equipment', 210, 'lifting_power', 'Lifting & Power', 10),
  ('generator_hire', 'machinery_equipment', 'Generator Hire', true, 'machinery_equipment', 220, 'lifting_power', 'Lifting & Power', 20),
  ('tractor_hire', 'machinery_equipment', 'Tractor Hire', true, 'machinery_equipment', 310, 'farm_industrial', 'Farm & Industrial', 10),
  ('industrial_equipment', 'machinery_equipment', 'Industrial Equipment', true, 'machinery_equipment', 320, 'farm_industrial', 'Farm & Industrial', 20),
  ('other_machinery', 'machinery_equipment', 'Other Machinery', true, 'machinery_equipment', 410, 'other', 'Other', 10),
  ('farm_services', 'agriculture_agribusiness', 'Farm Services', true, 'agriculture_agribusiness', 110, 'farm_operations', 'Farm Operations', 10),
  ('irrigation_services', 'agriculture_agribusiness', 'Irrigation', true, 'agriculture_agribusiness', 120, 'farm_operations', 'Farm Operations', 20),
  ('seeds_inputs', 'agriculture_agribusiness', 'Seeds & Inputs', true, 'agriculture_agribusiness', 210, 'inputs_livestock', 'Inputs & Livestock', 10),
  ('livestock_sourcing', 'agriculture_agribusiness', 'Livestock Sourcing', true, 'agriculture_agribusiness', 220, 'inputs_livestock', 'Inputs & Livestock', 20),
  ('produce_buyers', 'agriculture_agribusiness', 'Produce Buyers', true, 'agriculture_agribusiness', 310, 'market', 'Market', 10),
  ('other_agriculture', 'agriculture_agribusiness', 'Other Agriculture', true, 'agriculture_agribusiness', 320, 'market', 'Market', 20),
  ('bulk_procurement', 'specialized_products', 'Bulk Procurement', true, 'procurement_sourcing', 110, 'sourcing', 'Sourcing', 10),
  ('equipment_sourcing', 'specialized_products', 'Equipment Sourcing', true, 'procurement_sourcing', 120, 'sourcing', 'Sourcing', 20),
  ('imported_products', 'specialized_products', 'Imported Products', true, 'procurement_sourcing', 130, 'sourcing', 'Sourcing', 30),
  ('hard_to_find_products', 'specialized_products', 'Hard-to-Find Products', true, 'procurement_sourcing', 140, 'sourcing', 'Sourcing', 40),
  ('electronics_procurement', 'specialized_products', 'Electronics Procurement', true, 'procurement_sourcing', 210, 'parts_supplies', 'Parts & Supplies', 10),
  ('industrial_parts', 'specialized_products', 'Industrial Parts', true, 'procurement_sourcing', 220, 'parts_supplies', 'Parts & Supplies', 20),
  ('spare_parts', 'specialized_products', 'Spare Parts', true, 'procurement_sourcing', 230, 'parts_supplies', 'Parts & Supplies', 30),
  ('medical_supplies', 'specialized_products', 'Medical & Lab Supplies', true, 'procurement_sourcing', 240, 'parts_supplies', 'Parts & Supplies', 40),
  ('other_procurement', 'specialized_products', 'Other Procurement', true, 'procurement_sourcing', 310, 'other', 'Other', 10),
  ('flight_tickets', 'travel_international', 'Flight Tickets & Bookings', true, 'travel_international', 110, 'bookings', 'Bookings', 10),
  ('accommodation', 'travel_international', 'Accommodation', true, 'travel_international', 120, 'bookings', 'Bookings', 20),
  ('airport_transfers', 'travel_international', 'Airport Transfers', true, 'travel_international', 130, 'bookings', 'Bookings', 30),
  ('tour_packages', 'travel_international', 'Tour Packages', true, 'travel_international', 140, 'bookings', 'Bookings', 40),
  ('visa_assistance', 'travel_international', 'Visa Assistance', true, 'travel_international', 210, 'documents_cover', 'Documents & Cover', 10),
  ('travel_documentation', 'travel_international', 'Travel Documentation', true, 'travel_international', 220, 'documents_cover', 'Documents & Cover', 20),
  ('travel_insurance', 'travel_international', 'Travel Insurance', true, 'travel_international', 230, 'documents_cover', 'Documents & Cover', 30),
  ('hajj_umrah', 'travel_international', 'Hajj & Umrah', true, 'travel_international', 310, 'specialised', 'Specialised', 10),
  ('international_relocation', 'travel_international', 'International Relocation', true, 'travel_international', 320, 'specialised', 'Specialised', 20),
  ('travel_consultation', 'travel_international', 'Travel Consultation', true, 'travel_international', 330, 'specialised', 'Specialised', 30),
  ('other_travel', 'travel_international', 'Other Travel Services', true, 'travel_international', 340, 'specialised', 'Specialised', 40)
on conflict (slug) do update set
  category_slug = excluded.category_slug,
  name = excluded.name,
  is_active = true,
  ui_group_slug = excluded.ui_group_slug,
  sort_order = excluded.sort_order,
  service_group_slug = excluded.service_group_slug,
  service_group_name = excluded.service_group_name,
  service_sort_order = excluded.service_sort_order;

-- Hide legacy extras in these Provider Services categories so the picker shows
-- the unified v2 catalog, while retaining rows and existing provider selections.
update public.need_capabilities
set is_active = false
where category_slug in ('agriculture_agribusiness', 'beauty_fashion_styling', 'construction_building', 'education_training', 'energy_utilities', 'events_production', 'machinery_equipment', 'marketing_promotion', 'photo_video_music_talent', 'professional_services', 'specialized_products', 'technology_digital', 'transport_logistics', 'travel_international')
  and slug not in ('academic_consulting', 'accommodation', 'accounting_tax', 'actors_actresses', 'advertising_campaigns', 'affiliate_marketing', 'agricultural_transport', 'airport_transfers', 'architecture_services', 'automation_services', 'background_extras', 'backup_power', 'battery_supply', 'borehole_drilling', 'brand_promotion', 'bridal_styling', 'building_contractors', 'bulk_delivery', 'bulk_procurement', 'business_consulting', 'cargo_transport', 'celebration_cakes', 'celebration_catering', 'celebration_makeup', 'celebration_mc_dj', 'cold_chain_transport', 'company_registration', 'computer_training', 'concrete_works', 'construction_materials', 'content_creation', 'courier_delivery', 'crane_hire', 'cybersecurity_services', 'dancers', 'digital_marketing', 'dresses_bridesmaid_outfits', 'driving_school', 'electrical_installation', 'electrical_works', 'electronics_procurement', 'energy_consulting', 'engineering_consulting', 'equipment_sourcing', 'event_decoration', 'event_equipment', 'event_planning', 'event_promotion', 'event_transport', 'exam_preparation', 'excavation_works', 'excavator_hire', 'farm_services', 'flight_tickets', 'generator_hire', 'generator_supply', 'grader_hire', 'hair_styling', 'hajj_umrah', 'hard_to_find_products', 'health_nursing_placements', 'heavy_haulage', 'hr_services', 'i_have_an_audience', 'imported_products', 'industrial_equipment', 'industrial_parts', 'influencer_marketing', 'international_relocation', 'internship_placement', 'irrigation_services', 'it_support', 'language_training', 'legal_services', 'lighting_hire', 'livestock_sourcing', 'loader_hire', 'medical_supplies', 'mixing_mastering', 'mobile_app_development', 'moving_services', 'music_producers', 'music_video_models', 'music_video_stylists', 'networking_services', 'online_classes', 'other_agriculture', 'other_construction', 'other_energy', 'other_events', 'other_logistics', 'other_machinery', 'other_marketing_services', 'other_procurement', 'other_professional', 'other_technology', 'other_travel', 'photography_services', 'plumbing_services', 'private_tutoring', 'produce_buyers', 'product_reviews', 'professional_training', 'recording_studios', 'roofing_services', 'seeds_inputs', 'singers_vocalists', 'social_media_marketing', 'software_development', 'solar_systems', 'songwriters', 'sound_systems', 'spare_parts', 'study_abroad_guidance', 'surveying_services', 'tent_hire', 'tour_packages', 'tractor_hire', 'travel_consultation', 'travel_documentation', 'travel_insurance', 'truck_hire', 'university_admissions', 'vehicle_transport', 'video_editors', 'videography_services', 'visa_assistance', 'vocational_training', 'water_systems', 'website_development');

insert into public.capability_roles
  (slug, category_slug, capability_slug, name, kind_question, is_active)
values
  ('developer', 'technology_digital', null, 'Developer', 'What do you build?', true),
  ('it_technician', 'technology_digital', null, 'IT Technician', 'What do you do?', true),
  ('security_specialist', 'technology_digital', null, 'Security Specialist', 'Which area?', true),
  ('project_manager', 'technology_digital', null, 'Project Manager', 'What kind of projects?', true),
  ('team_lead_manager', 'technology_digital', null, 'Team Lead / Manager', 'What do you lead?', true),
  ('marketer_specialist', 'marketing_promotion', null, 'Marketer / Specialist', 'Which channel?', true),
  ('content_creator', 'marketing_promotion', null, 'Content Creator', 'What do you produce?', true),
  ('marketing_manager', 'marketing_promotion', null, 'Marketing Manager', 'What scope?', true),
  ('campaign_project_manager', 'marketing_promotion', null, 'Campaign Project Manager', 'Campaign type?', true),
  ('accountant_finance_officer', 'professional_services', null, 'Accountant / Finance Officer', 'What area?', true),
  ('lawyer_legal_officer', 'professional_services', null, 'Lawyer / Legal Officer', 'What area?', true),
  ('engineer', 'professional_services', null, 'Engineer', 'Which discipline?', true),
  ('architect_designer', 'professional_services', null, 'Architect / Designer', 'What do you design?', true),
  ('hr_officer_manager', 'professional_services', null, 'HR Officer / Manager', 'What area?', true),
  ('consultant', 'professional_services', null, 'Consultant', 'Advisory area?', true),
  ('business_professional_services_project_manager', 'professional_services', null, 'Project Manager', 'What kind of projects?', true),
  ('teacher_tutor', 'education_training', null, 'Teacher / Tutor', 'What do you teach?', true),
  ('trainer_instructor', 'education_training', null, 'Trainer / Instructor', 'Training field?', true),
  ('placement_coordinator', 'education_training', null, 'Placement Coordinator', 'What placements?', true),
  ('programme_manager', 'education_training', null, 'Programme Manager', 'What programmes?', true),
  ('event_manager_planner', 'events_production', null, 'Event Manager / Planner', 'What events?', true),
  ('mc_dj', 'events_production', null, 'MC / DJ', 'Which role?', true),
  ('event_crew_technician', 'events_production', null, 'Event Crew / Technician', 'What do you operate?', true),
  ('caterer_chef', 'events_production', null, 'Caterer / Chef', 'What kind?', true),
  ('event_supervisor', 'events_production', null, 'Event Supervisor', 'What scope?', true),
  ('photographer_videographer', 'photo_video_music_talent', null, 'Photographer / Videographer', 'What do you shoot?', true),
  ('audio_engineer_producer', 'photo_video_music_talent', null, 'Audio Engineer / Producer', 'What do you do?', true),
  ('performer_talent', 'photo_video_music_talent', null, 'Performer / Talent', 'What kind?', true),
  ('production_manager', 'photo_video_music_talent', null, 'Production Manager', 'What productions?', true),
  ('makeup_artist', 'beauty_fashion_styling', null, 'Makeup Artist', 'Specialty?', true),
  ('hair_stylist', 'beauty_fashion_styling', null, 'Hair Stylist', 'Specialty?', true),
  ('stylist_designer', 'beauty_fashion_styling', null, 'Stylist / Designer', 'Specialty?', true),
  ('salon_studio_manager', 'beauty_fashion_styling', null, 'Salon / Studio Manager', 'What scope?', true),
  ('site_manager', 'construction_building', null, 'Site Manager', 'What type of sites?', true),
  ('construction_building_project_manager', 'construction_building', null, 'Project Manager', 'What kind of projects?', true),
  ('foreman_supervisor', 'construction_building', null, 'Foreman / Supervisor', 'Which trade?', true),
  ('skilled_tradesperson', 'construction_building', null, 'Skilled Tradesperson', 'Which trade?', true),
  ('surveyor', 'construction_building', null, 'Surveyor', 'What type?', true),
  ('solar_electrical_technician', 'energy_utilities', null, 'Solar / Electrical Technician', 'What do you install?', true),
  ('borehole_water_technician', 'energy_utilities', null, 'Borehole / Water Technician', 'What do you do?', true),
  ('energy_engineer', 'energy_utilities', null, 'Energy Engineer', 'Which area?', true),
  ('energy_water_project_manager', 'energy_utilities', null, 'Project Manager', 'What kind of projects?', true),
  ('driver', 'transport_logistics', null, 'Driver', 'What do you drive?', true),
  ('fleet_operations_manager', 'transport_logistics', null, 'Fleet / Operations Manager', 'What fleet?', true),
  ('dispatcher_coordinator', 'transport_logistics', null, 'Dispatcher / Coordinator', 'What area?', true),
  ('loader_mover', 'transport_logistics', null, 'Loader / Mover', 'What work?', true),
  ('machine_operator', 'machinery_equipment', null, 'Machine Operator', 'Which machine do you operate?', true),
  ('equipment_mechanic', 'machinery_equipment', null, 'Equipment Mechanic', 'What do you service?', true),
  ('fleet_equipment_manager', 'machinery_equipment', null, 'Fleet / Equipment Manager', 'What fleet?', true),
  ('site_supervisor', 'machinery_equipment', null, 'Site Supervisor', 'Which sites?', true),
  ('farm_manager', 'agriculture_agribusiness', null, 'Farm Manager', 'What farm?', true),
  ('agronomist_extension_officer', 'agriculture_agribusiness', null, 'Agronomist / Extension Officer', 'What focus?', true),
  ('veterinary_livestock_officer', 'agriculture_agribusiness', null, 'Veterinary / Livestock Officer', 'What animals?', true),
  ('farm_worker_operator', 'agriculture_agribusiness', null, 'Farm Worker / Operator', 'What work?', true),
  ('procurement_officer_manager', 'specialized_products', null, 'Procurement Officer / Manager', 'What do you buy?', true),
  ('sourcing_agent', 'specialized_products', null, 'Sourcing Agent', 'Where do you source?', true),
  ('clearing_customs_agent', 'specialized_products', null, 'Clearing & Customs Agent', 'What do you handle?', true),
  ('travel_agent_consultant', 'travel_international', null, 'Travel Agent / Consultant', 'What do you handle?', true),
  ('tour_guide', 'travel_international', null, 'Tour Guide', 'What tours?', true),
  ('driver_guide', 'travel_international', null, 'Driver-Guide', 'What vehicle?', true),
  ('operations_manager', 'travel_international', null, 'Operations Manager', 'What scope?', true)
on conflict (slug) do update set
  category_slug = excluded.category_slug,
  capability_slug = null,
  name = excluded.name,
  kind_question = excluded.kind_question,
  is_active = true;

-- Roles are category-scoped by the existing query path. The repeated
-- Project Manager entries therefore use distinct category-prefixed slugs.
update public.capability_roles
set is_active = false
where category_slug in ('agriculture_agribusiness', 'beauty_fashion_styling', 'construction_building', 'education_training', 'energy_utilities', 'events_production', 'machinery_equipment', 'marketing_promotion', 'photo_video_music_talent', 'professional_services', 'specialized_products', 'technology_digital', 'transport_logistics', 'travel_international')
  and slug not in ('accountant_finance_officer', 'agronomist_extension_officer', 'architect_designer', 'audio_engineer_producer', 'borehole_water_technician', 'business_professional_services_project_manager', 'campaign_project_manager', 'caterer_chef', 'clearing_customs_agent', 'construction_building_project_manager', 'consultant', 'content_creator', 'developer', 'dispatcher_coordinator', 'driver', 'driver_guide', 'energy_engineer', 'energy_water_project_manager', 'engineer', 'equipment_mechanic', 'event_crew_technician', 'event_manager_planner', 'event_supervisor', 'farm_manager', 'farm_worker_operator', 'fleet_equipment_manager', 'fleet_operations_manager', 'foreman_supervisor', 'hair_stylist', 'hr_officer_manager', 'it_technician', 'lawyer_legal_officer', 'loader_mover', 'machine_operator', 'makeup_artist', 'marketer_specialist', 'marketing_manager', 'mc_dj', 'operations_manager', 'performer_talent', 'photographer_videographer', 'placement_coordinator', 'procurement_officer_manager', 'production_manager', 'programme_manager', 'project_manager', 'salon_studio_manager', 'security_specialist', 'site_manager', 'site_supervisor', 'skilled_tradesperson', 'solar_electrical_technician', 'sourcing_agent', 'stylist_designer', 'surveyor', 'teacher_tutor', 'team_lead_manager', 'tour_guide', 'trainer_instructor', 'travel_agent_consultant', 'veterinary_livestock_officer');

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
  ('consultant', 'strategy', 'Strategy', 10),
  ('consultant', 'operations', 'Operations', 20),
  ('consultant', 'finance', 'Finance', 30),
  ('consultant', 'compliance', 'Compliance', 40),
  ('business_professional_services_project_manager', 'business', 'Business', 10),
  ('business_professional_services_project_manager', 'compliance', 'Compliance', 20),
  ('business_professional_services_project_manager', 'operations', 'Operations', 30),
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
  ('energy_water_project_manager', 'solar', 'Solar', 10),
  ('energy_water_project_manager', 'water', 'Water', 20),
  ('energy_water_project_manager', 'electrification', 'Electrification', 30),
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

insert into public.role_qualifications
  (role_slug, slug, name, is_evidence, sort_order)
values
  ('developer', 'degree_diploma_in_it_or_cs', 'Degree / Diploma in IT or CS', false, 10),
  ('developer', 'portfolio_or_github_link', 'Portfolio or GitHub link', false, 20),
  ('developer', 'cloud_certification_aws_azure_gcp', 'Cloud certification (AWS/Azure/GCP)', true, 30),
  ('developer', '3_years_experience', '3+ years experience', false, 40),
  ('it_technician', 'comptia_a_n', 'CompTIA A+ / N+', false, 10),
  ('it_technician', 'ccna', 'CCNA', false, 20),
  ('it_technician', 'own_toolkit', 'Own toolkit', false, 30),
  ('it_technician', '2_years_experience', '2+ years experience', false, 40),
  ('security_specialist', 'ceh', 'CEH', false, 10),
  ('security_specialist', 'cissp_cism', 'CISSP / CISM', false, 20),
  ('security_specialist', 'iso_27001', 'ISO 27001', false, 30),
  ('security_specialist', 'police_clearance', 'Police clearance', false, 40),
  ('project_manager', 'pmp_prince2', 'PMP / PRINCE2', false, 10),
  ('project_manager', 'agile_scrum_certified', 'Agile / Scrum certified', true, 20),
  ('project_manager', 'led_3_projects', 'Led 3+ projects', false, 30),
  ('project_manager', 'degree', 'Degree', false, 40),
  ('team_lead_manager', 'managed_5_people', 'Managed 5+ people', false, 10),
  ('team_lead_manager', 'degree', 'Degree', false, 20),
  ('team_lead_manager', '3_years_leadership', '3+ years leadership', false, 30),
  ('marketer_specialist', 'marketing_diploma_degree', 'Marketing diploma / degree', false, 10),
  ('marketer_specialist', 'google_ads_meta_certified', 'Google Ads / Meta certified', true, 20),
  ('marketer_specialist', 'case_studies_or_portfolio', 'Case studies or portfolio', false, 30),
  ('marketer_specialist', '2_years_experience', '2+ years experience', false, 40),
  ('content_creator', 'portfolio', 'Portfolio', false, 10),
  ('content_creator', 'own_equipment', 'Own equipment', false, 20),
  ('content_creator', 'audience_size_proof', 'Audience size proof', false, 30),
  ('marketing_manager', 'degree', 'Degree', false, 10),
  ('marketing_manager', 'managed_budgets', 'Managed budgets', false, 20),
  ('marketing_manager', 'managed_3_people', 'Managed 3+ people', false, 30),
  ('campaign_project_manager', 'pmp_prince2', 'PMP / PRINCE2', false, 10),
  ('campaign_project_manager', 'led_3_campaigns', 'Led 3+ campaigns', false, 20),
  ('accountant_finance_officer', 'cpa_acca_cpa_u', 'CPA / ACCA / CPA-U', false, 10),
  ('accountant_finance_officer', 'degree', 'Degree', false, 20),
  ('accountant_finance_officer', 'practising_certificate', 'Practising certificate', true, 30),
  ('accountant_finance_officer', '3_years_experience', '3+ years experience', false, 40),
  ('lawyer_legal_officer', 'bar_admission_practising_certificate', 'Bar admission / practising certificate', true, 10),
  ('lawyer_legal_officer', 'llb', 'LLB', false, 20),
  ('lawyer_legal_officer', '3_years_experience', '3+ years experience', false, 30),
  ('engineer', 'degree_in_engineering', 'Degree in engineering', false, 10),
  ('engineer', 'registered_with_engineers_board', 'Registered with engineers board', true, 20),
  ('engineer', 'site_experience', 'Site experience', false, 30),
  ('architect_designer', 'registered_architect', 'Registered architect', true, 10),
  ('architect_designer', 'portfolio', 'Portfolio', false, 20),
  ('architect_designer', 'cad_bim_skills', 'CAD/BIM skills', false, 30),
  ('hr_officer_manager', 'hr_diploma_degree', 'HR diploma / degree', false, 10),
  ('hr_officer_manager', 'ihrm_cipd', 'IHRM / CIPD', false, 20),
  ('hr_officer_manager', '3_years_experience', '3+ years experience', false, 30),
  ('consultant', 'degree', 'Degree', false, 10),
  ('consultant', 'case_studies', 'Case studies', false, 20),
  ('consultant', '5_years_experience', '5+ years experience', false, 30),
  ('business_professional_services_project_manager', 'pmp_prince2', 'PMP / PRINCE2', false, 10),
  ('business_professional_services_project_manager', 'led_3_projects', 'Led 3+ projects', false, 20),
  ('teacher_tutor', 'teaching_certificate_degree', 'Teaching certificate / degree', true, 10),
  ('teacher_tutor', 'registered_with_teaching_board', 'Registered with teaching board', true, 20),
  ('teacher_tutor', '2_years_teaching', '2+ years teaching', false, 30),
  ('teacher_tutor', 'subject_specialisation', 'Subject specialisation', false, 40),
  ('trainer_instructor', 'trade_certificate', 'Trade certificate', true, 10),
  ('trainer_instructor', 'trainer_of_trainers_tot', 'Trainer-of-trainers (ToT)', false, 20),
  ('trainer_instructor', 'industry_experience_3_years', 'Industry experience 3+ years', false, 30),
  ('placement_coordinator', 'education_or_hr_background', 'Education or HR background', false, 10),
  ('placement_coordinator', 'partner_network', 'Partner network', false, 20),
  ('placement_coordinator', 'counselling_certificate', 'Counselling certificate', true, 30),
  ('programme_manager', 'degree', 'Degree', false, 10),
  ('programme_manager', 'managed_3_programmes', 'Managed 3+ programmes', false, 20),
  ('event_manager_planner', 'event_planning_certificate', 'Event planning certificate', true, 10),
  ('event_manager_planner', 'portfolio_of_5_events', 'Portfolio of 5+ events', false, 20),
  ('event_manager_planner', 'insurance_permit', 'Insurance / permit', false, 30),
  ('event_manager_planner', 'team_of_3_staff', 'Team of 3+ staff', false, 40),
  ('mc_dj', 'own_equipment', 'Own equipment', false, 10),
  ('mc_dj', 'sample_mix_video', 'Sample mix / video', false, 20),
  ('mc_dj', 'references', 'References', false, 30),
  ('event_crew_technician', 'technical_training', 'Technical training', false, 10),
  ('event_crew_technician', 'own_tools', 'Own tools', false, 20),
  ('event_crew_technician', 'event_experience_1_year', 'Event experience 1+ year', false, 30),
  ('caterer_chef', 'food_handler_certificate', 'Food handler certificate', true, 10),
  ('caterer_chef', 'health_permit', 'Health permit', false, 20),
  ('caterer_chef', 'culinary_diploma', 'Culinary diploma', false, 30),
  ('event_supervisor', 'managed_5_events', 'Managed 5+ events', false, 10),
  ('event_supervisor', 'team_leadership', 'Team leadership', false, 20),
  ('photographer_videographer', 'portfolio_link', 'Portfolio link', false, 10),
  ('photographer_videographer', 'own_camera_drone_kit', 'Own camera / drone kit', false, 20),
  ('photographer_videographer', 'drone_licence', 'Drone licence', true, 30),
  ('photographer_videographer', 'editing_skills', 'Editing skills', false, 40),
  ('audio_engineer_producer', 'own_studio_daw', 'Own studio / DAW', false, 10),
  ('audio_engineer_producer', 'portfolio', 'Portfolio', false, 20),
  ('audio_engineer_producer', 'audio_engineering_diploma', 'Audio engineering diploma', false, 30),
  ('performer_talent', 'showreel_audition_clip', 'Showreel / audition clip', false, 10),
  ('performer_talent', 'agency_representation', 'Agency representation', false, 20),
  ('performer_talent', 'performance_experience', 'Performance experience', false, 30),
  ('production_manager', 'managed_3_productions', 'Managed 3+ productions', false, 10),
  ('production_manager', 'budget_handling', 'Budget handling', false, 20),
  ('production_manager', 'crew_network', 'Crew network', false, 30),
  ('makeup_artist', 'cosmetology_certificate', 'Cosmetology certificate', true, 10),
  ('makeup_artist', 'portfolio', 'Portfolio', false, 20),
  ('makeup_artist', 'own_kit', 'Own kit', false, 30),
  ('makeup_artist', 'hygiene_certification', 'Hygiene certification', true, 40),
  ('hair_stylist', 'cosmetology_certificate', 'Cosmetology certificate', true, 10),
  ('hair_stylist', 'portfolio', 'Portfolio', false, 20),
  ('hair_stylist', 'salon_licence', 'Salon licence', true, 30),
  ('stylist_designer', 'fashion_diploma', 'Fashion diploma', false, 10),
  ('stylist_designer', 'portfolio', 'Portfolio', false, 20),
  ('stylist_designer', 'own_workshop', 'Own workshop', false, 30),
  ('salon_studio_manager', 'managed_3_staff', 'Managed 3+ staff', false, 10),
  ('salon_studio_manager', 'business_licence', 'Business licence', true, 20),
  ('site_manager', 'civil_construction_diploma_or_degree', 'Civil/Construction diploma or degree', false, 10),
  ('site_manager', 'registered_with_engineers_contractors_board', 'Registered with engineers/contractors board', true, 20),
  ('site_manager', '5_years_on_site', '5+ years on site', false, 30),
  ('site_manager', 'safety_certification_osha', 'Safety certification (OSHA)', true, 40),
  ('construction_building_project_manager', 'pmp_prince2', 'PMP / PRINCE2', false, 10),
  ('construction_building_project_manager', 'degree', 'Degree', false, 20),
  ('construction_building_project_manager', 'delivered_3_projects', 'Delivered 3+ projects', false, 30),
  ('foreman_supervisor', 'trade_test_certificate', 'Trade test certificate', true, 10),
  ('foreman_supervisor', 'managed_10_workers', 'Managed 10+ workers', false, 20),
  ('foreman_supervisor', 'safety_training', 'Safety training', false, 30),
  ('skilled_tradesperson', 'trade_test_grade_i_ii_iii', 'Trade test (Grade I/II/III)', false, 10),
  ('skilled_tradesperson', 'licence_electrical_plumbing', 'Licence (electrical/plumbing)', true, 20),
  ('skilled_tradesperson', 'own_tools', 'Own tools', false, 30),
  ('skilled_tradesperson', '2_years_experience', '2+ years experience', false, 40),
  ('surveyor', 'registered_surveyor', 'Registered surveyor', true, 10),
  ('surveyor', 'degree_diploma', 'Degree / diploma', false, 20),
  ('surveyor', 'own_instruments', 'Own instruments', false, 30),
  ('solar_electrical_technician', 'electrical_licence', 'Electrical licence', true, 10),
  ('solar_electrical_technician', 'solar_installer_certificate', 'Solar installer certificate', true, 20),
  ('solar_electrical_technician', 'safety_training', 'Safety training', false, 30),
  ('solar_electrical_technician', 'own_tools', 'Own tools', false, 40),
  ('borehole_water_technician', 'water_technician_certificate', 'Water technician certificate', true, 10),
  ('borehole_water_technician', 'drilling_permit', 'Drilling permit', false, 20),
  ('borehole_water_technician', 'own_equipment', 'Own equipment', false, 30),
  ('energy_engineer', 'engineering_degree', 'Engineering degree', false, 10),
  ('energy_engineer', 'registered_engineer', 'Registered engineer', true, 20),
  ('energy_engineer', 'design_software_skills', 'Design software skills', false, 30),
  ('energy_water_project_manager', 'pmp_prince2', 'PMP / PRINCE2', false, 10),
  ('energy_water_project_manager', 'delivered_3_projects', 'Delivered 3+ projects', false, 20),
  ('driver', 'valid_driving_licence_class', 'Valid driving licence (class)', true, 10),
  ('driver', 'psv_badge', 'PSV badge', false, 20),
  ('driver', 'clean_driving_record', 'Clean driving record', false, 30),
  ('driver', 'defensive_driving_certificate', 'Defensive driving certificate', true, 40),
  ('driver', 'own_vehicle', 'Own vehicle', false, 50),
  ('fleet_operations_manager', 'logistics_diploma_degree', 'Logistics diploma / degree', false, 10),
  ('fleet_operations_manager', 'managed_10_vehicles', 'Managed 10+ vehicles', false, 20),
  ('fleet_operations_manager', 'transport_licence', 'Transport licence', true, 30),
  ('dispatcher_coordinator', 'logistics_experience', 'Logistics experience', false, 10),
  ('dispatcher_coordinator', 'customs_clearing_licence', 'Customs clearing licence', true, 20),
  ('loader_mover', 'physical_fitness', 'Physical fitness', false, 10),
  ('loader_mover', 'experience_1_year', 'Experience 1+ year', false, 20),
  ('machine_operator', 'operator_licence_certificate', 'Operator licence / certificate', true, 10),
  ('machine_operator', 'safety_osha_certificate', 'Safety / OSHA certificate', true, 20),
  ('machine_operator', '3_years_experience', '3+ years experience', false, 30),
  ('machine_operator', 'medical_fitness', 'Medical fitness', false, 40),
  ('machine_operator', 'can_work_away_from_home', 'Can work away from home', false, 50),
  ('equipment_mechanic', 'mechanic_trade_certificate', 'Mechanic trade certificate', true, 10),
  ('equipment_mechanic', 'own_tools', 'Own tools', false, 20),
  ('equipment_mechanic', 'field_repair_experience', 'Field repair experience', false, 30),
  ('fleet_equipment_manager', 'managed_fleet_of_5_machines', 'Managed fleet of 5+ machines', false, 10),
  ('fleet_equipment_manager', 'diploma_degree', 'Diploma / degree', false, 20),
  ('fleet_equipment_manager', 'maintenance_scheduling', 'Maintenance scheduling', false, 30),
  ('site_supervisor', 'plant_experience', 'Plant experience', false, 10),
  ('site_supervisor', 'team_leadership', 'Team leadership', false, 20),
  ('site_supervisor', 'safety_certification', 'Safety certification', true, 30),
  ('farm_manager', 'agriculture_diploma_degree', 'Agriculture diploma / degree', false, 10),
  ('farm_manager', 'managed_5_workers', 'Managed 5+ workers', false, 20),
  ('farm_manager', '5_years_farming_experience', '5+ years farming experience', false, 30),
  ('agronomist_extension_officer', 'degree_diploma_in_agronomy', 'Degree / diploma in agronomy', false, 10),
  ('agronomist_extension_officer', 'field_experience', 'Field experience', false, 20),
  ('veterinary_livestock_officer', 'veterinary_licence', 'Veterinary licence', true, 10),
  ('veterinary_livestock_officer', 'diploma_degree', 'Diploma / degree', false, 20),
  ('veterinary_livestock_officer', 'vaccination_certification', 'Vaccination certification', true, 30),
  ('farm_worker_operator', 'tractor_licence', 'Tractor licence', true, 10),
  ('farm_worker_operator', 'pesticide_handling_certificate', 'Pesticide handling certificate', true, 20),
  ('farm_worker_operator', 'experience_1_year', 'Experience 1+ year', false, 30),
  ('procurement_officer_manager', 'procurement_diploma_cips_or_similar', 'Procurement diploma (CIPS or similar)', false, 10),
  ('procurement_officer_manager', 'supplier_network', 'Supplier network', false, 20),
  ('procurement_officer_manager', '3_years_experience', '3+ years experience', false, 30),
  ('sourcing_agent', 'import_export_experience', 'Import/export experience', false, 10),
  ('sourcing_agent', 'language_skills', 'Language skills', false, 20),
  ('sourcing_agent', 'supplier_contacts', 'Supplier contacts', false, 30),
  ('clearing_customs_agent', 'customs_clearing_licence', 'Customs clearing licence', true, 10),
  ('clearing_customs_agent', 'logistics_experience', 'Logistics experience', false, 20),
  ('travel_agent_consultant', 'iata_certification', 'IATA certification', true, 10),
  ('travel_agent_consultant', 'travel_agency_licence', 'Travel agency licence', true, 20),
  ('travel_agent_consultant', '2_years_experience', '2+ years experience', false, 30),
  ('tour_guide', 'tourism_board_guide_licence', 'Tourism board guide licence', true, 10),
  ('tour_guide', 'first_aid_certificate', 'First aid certificate', true, 20),
  ('tour_guide', 'languages_spoken', 'Languages spoken', false, 30),
  ('driver_guide', 'valid_driving_licence_class', 'Valid driving licence (class)', true, 10),
  ('driver_guide', 'tourism_licence', 'Tourism licence', true, 20),
  ('driver_guide', 'clean_driving_record', 'Clean driving record', false, 30),
  ('operations_manager', 'tourism_diploma_degree', 'Tourism diploma / degree', false, 10),
  ('operations_manager', 'managed_3_staff', 'Managed 3+ staff', false, 20)
on conflict (role_slug, slug) do update set
  name = excluded.name,
  is_evidence = excluded.is_evidence,
  sort_order = excluded.sort_order;

-- Provider-entered qualifications remain claims until Nipanze reviews evidence.
create table if not exists public.provider_role_qualification_claims (
  id uuid primary key default gen_random_uuid(),
  provider_capability_id uuid not null
    references public.provider_capabilities(id) on delete cascade,
  role_slug text not null,
  qualification_slug text not null,
  is_claimed boolean not null default true,
  status text not null default 'self_declared'
    check (status in ('self_declared', 'pending_review', 'verified', 'rejected', 'expired')),
  evidence_object_path text,
  reject_reason text,
  expires_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_role_qualification_claims_unique
    unique (provider_capability_id, role_slug, qualification_slug),
  constraint provider_role_qualification_claims_qualification_fk
    foreign key (role_slug, qualification_slug)
    references public.role_qualifications(role_slug, slug)
    on delete restrict,
  constraint provider_role_qualification_claims_review_state_check
    check (
      (status in ('self_declared', 'pending_review') and reviewed_by is null and reviewed_at is null)
      or (status in ('verified', 'rejected', 'expired') and reviewed_by is not null and reviewed_at is not null)
    )
);

create index if not exists idx_provider_role_qualification_claims_owner
  on public.provider_role_qualification_claims(provider_capability_id, is_claimed);
create index if not exists idx_provider_role_qualification_claims_review
  on public.provider_role_qualification_claims(status, updated_at);

alter table public.provider_role_qualification_claims enable row level security;
drop policy if exists "provider role qualification claims owner select"
  on public.provider_role_qualification_claims;
create policy "provider role qualification claims owner select"
  on public.provider_role_qualification_claims
  for select to authenticated
  using (
    exists (
      select 1 from public.provider_capabilities pc
      where pc.id = provider_role_qualification_claims.provider_capability_id
        and (pc.user_id = auth.uid() or private.is_admin())
    )
  );
revoke all on public.provider_role_qualification_claims from anon, public, authenticated;
grant select on public.provider_role_qualification_claims to authenticated;

-- Keep qualification selections in metadata as the existing app contract,
-- while mirroring them into a reviewable per-qualification claim table.
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
        values
          (new.id, v_role_slug, v_qualification_slug, true)
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

-- Backfill existing self-declared role selections; invalid legacy option IDs
-- are left untouched in metadata and are not promoted into verified claims.
update public.provider_capabilities
set metadata = metadata
where metadata ? 'roles';

create or replace function public.submit_provider_role_qualification_evidence(
  p_provider_capability_id uuid,
  p_role_slug text,
  p_qualification_slug text,
  p_evidence_object_path text
)
returns uuid
language plpgsql
security definer
set search_path = public, private, storage
as $$
declare
  v_user_id uuid := auth.uid();
  v_capability_slug text;
  v_claim_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated.' using errcode = '42501';
  end if;

  select pc.capability_slug, claim.id
  into v_capability_slug, v_claim_id
  from public.provider_capabilities pc
  join public.provider_role_qualification_claims claim
    on claim.provider_capability_id = pc.id
  join public.role_qualifications rq
    on rq.role_slug = claim.role_slug
   and rq.slug = claim.qualification_slug
  where pc.id = p_provider_capability_id
    and pc.user_id = v_user_id
    and claim.role_slug = p_role_slug
    and claim.qualification_slug = p_qualification_slug
    and claim.is_claimed
    and rq.is_evidence
  for update of claim;

  if not found then
    raise exception 'Claim not found or this qualification does not accept evidence.'
      using errcode = 'P0212';
  end if;

  if p_evidence_object_path is null
     or position('..' in p_evidence_object_path) > 0
     or left(
       p_evidence_object_path,
       length('evidence/' || v_user_id::text || '/' || v_capability_slug || '/')
     ) <> ('evidence/' || v_user_id::text || '/' || v_capability_slug || '/') then
    raise exception 'Evidence must be stored in the provider''s private capability folder.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from storage.objects so
    where so.bucket_id = 'provider-evidence'
      and so.name = p_evidence_object_path
  ) then
    raise exception 'Uploaded provider evidence was not found in private storage.'
      using errcode = 'P0213';
  end if;

  update public.provider_role_qualification_claims
  set status = 'pending_review',
      evidence_object_path = p_evidence_object_path,
      reject_reason = null,
      expires_at = null,
      reviewed_by = null,
      reviewed_at = null,
      updated_at = now()
  where id = v_claim_id;

  return v_claim_id;
end;
$$;

revoke all on function public.submit_provider_role_qualification_evidence(uuid, text, text, text)
  from public, anon;
grant execute on function public.submit_provider_role_qualification_evidence(uuid, text, text, text)
  to authenticated;

create or replace function public.admin_review_provider_role_qualification(
  p_claim_id uuid,
  p_action text,
  p_reject_reason text default null,
  p_expires_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_admin uuid := auth.uid();
  v_claim record;
begin
  if not private.is_admin() then
    raise exception 'Unauthorized: Admin access required.' using errcode = '42501';
  end if;
  if p_action not in ('approve', 'reject', 'expire') then
    raise exception 'Action must be approve, reject, or expire.' using errcode = '22023';
  end if;

  select claim.*, pc.capability_slug, pc.user_id
  into v_claim
  from public.provider_role_qualification_claims claim
  join public.provider_capabilities pc on pc.id = claim.provider_capability_id
  where claim.id = p_claim_id
  for update of claim;

  if not found then
    raise exception 'Provider role qualification claim not found.' using errcode = 'P0212';
  end if;
  if p_action = 'approve' and v_claim.status <> 'pending_review' then
    raise exception 'Only submitted qualification evidence can be approved.' using errcode = '22023';
  end if;
  if p_action = 'approve' and p_expires_at is not null and p_expires_at <= now() then
    raise exception 'Evidence expiry must be in the future.' using errcode = '22023';
  end if;

  update public.provider_role_qualification_claims
  set status = case
        when p_action = 'approve' then 'verified'
        when p_action = 'reject' then 'rejected'
        else 'expired'
      end,
      reject_reason = case when p_action = 'reject' then coalesce(p_reject_reason, '') else null end,
      expires_at = case when p_action = 'approve' then p_expires_at else expires_at end,
      reviewed_by = v_admin,
      reviewed_at = now(),
      updated_at = now()
  where id = p_claim_id;

  insert into public.audit_logs
    (user_id, event_type, entity_type, entity_id, action, new_values)
  values
    (v_admin, 'admin_action', 'provider_role_qualification_claim', p_claim_id,
     'review_provider_role_qualification',
     jsonb_build_object(
       'action', p_action,
       'provider_capability_id', v_claim.provider_capability_id,
       'capability_slug', v_claim.capability_slug,
       'role_slug', v_claim.role_slug,
       'qualification_slug', v_claim.qualification_slug,
       'reject_reason', p_reject_reason,
       'expires_at', p_expires_at
     ));

  return true;
end;
$$;

revoke all on function public.admin_review_provider_role_qualification(uuid, text, text, timestamptz)
  from public, anon;
grant execute on function public.admin_review_provider_role_qualification(uuid, text, text, timestamptz)
  to authenticated;

-- Owner/admin status view: evidence paths stay private; status is safe to render in-app.
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
  coalesce(qs.claims, '[]'::jsonb) as role_qualification_claims
from public.provider_capabilities pc
join public.need_capabilities nc on nc.slug = pc.capability_slug
join public.need_categories cat on cat.slug = nc.category_slug
left join evidence_summary es on es.provider_capability_id = pc.id
left join latest_rejection lr on lr.provider_capability_id = pc.id
left join qualification_summary qs on qs.provider_capability_id = pc.id
where pc.user_id = auth.uid() or private.is_admin();

grant select on public.v_my_capability_status to authenticated;

-- The role/kind/qualification step is feature-flagged in the app.
-- Enable it so the pictured Provider Services flow is available after this patch.
insert into public.system_settings
  (setting_key, country, setting_value, setting_type, category, description, is_public)
values
  ('capability_profiles_enabled', null, 'true', 'boolean', 'provider',
   'Enables Provider Services v2 roles, kinds, qualifications, evidence, and hire-person matching.',
   true)
on conflict (setting_key, coalesce(country, '__global__')) do update set
  setting_value = excluded.setting_value,
  setting_type = excluded.setting_type,
  category = excluded.category,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();

-- Keep the public catalog readable through Supabase/PostgREST.
grant select on public.need_categories, public.need_capabilities to anon, authenticated;
grant select on public.capability_roles, public.role_kinds, public.role_qualifications to anon, authenticated;

commit;
