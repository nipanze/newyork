-- ============================================================================
-- Patch: sql/patch_enable_provider_work_profiles.sql
-- Enables Provider Services v2 and Work Profiles in system_settings by default.
-- ============================================================================

INSERT INTO public.system_settings
  (setting_key, country, setting_value, setting_type, category, description, is_public)
VALUES
  ('capability_profiles_enabled', null, 'true', 'boolean', 'provider',
   'Enables Provider Services v2 multi-capability flow.', true),
  ('work_profiles_enabled', null, 'true', 'boolean', 'provider',
   'Enables Work Profiles and roles across categories.', true)
ON CONFLICT (setting_key, coalesce(country, '__global__')) DO UPDATE SET
  setting_value = excluded.setting_value,
  setting_type = excluded.setting_type,
  category = excluded.category,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();

