-- Restore proof eligibility after role catalog seeds that default qualifications
-- to self-declared and overwrite the canonical evidence flags.
begin;

update public.role_qualifications rq
set is_evidence = true
from (
  values
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
    ('massage_therapist', 'massage_therapy_certificate'),
    ('massage_therapist', 'hygiene_certification'),
    ('spa_therapist', 'cosmetology_spa_certificate'),
    ('spa_therapist', 'hygiene_certification')
) as eligible(role_slug, qualification_slug)
where rq.role_slug = eligible.role_slug
  and rq.slug = eligible.qualification_slug
  and not rq.is_evidence;

commit;
