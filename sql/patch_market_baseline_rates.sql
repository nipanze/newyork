-- Patch: Admin-controlled market baseline rates for interest and late payment
-- Uses system_settings with country overrides and a global default.

INSERT INTO system_settings (
  setting_key,
  country,
  setting_value,
  setting_type,
  category,
  description,
  is_public
) VALUES
  ('market_interest_rate_baseline_pct', NULL, '10.0', 'number', 'marketplace', 'Global default market interest rate baseline percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', NULL, '5.0', 'number', 'marketplace', 'Global default market late payment rate baseline percentage controlled by admin.', TRUE)
ON CONFLICT (setting_key, COALESCE(country, '__global__')) DO UPDATE
SET
  setting_value = EXCLUDED.setting_value,
  setting_type = EXCLUDED.setting_type,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  is_public = EXCLUDED.is_public,
  updated_at = CURRENT_TIMESTAMP;

INSERT INTO system_settings (
  setting_key,
  country,
  setting_value,
  setting_type,
  category,
  description,
  is_public
) VALUES
  ('market_interest_rate_baseline_pct', 'UG', '10.0', 'number', 'marketplace', 'Uganda market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'UG', '5.0', 'number', 'marketplace', 'Uganda market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'KE', '11.5', 'number', 'marketplace', 'Kenya market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'KE', '6.0', 'number', 'marketplace', 'Kenya market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'TZ', '12.0', 'number', 'marketplace', 'Tanzania market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'TZ', '6.5', 'number', 'marketplace', 'Tanzania market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'RW', '11.0', 'number', 'marketplace', 'Rwanda market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'RW', '6.0', 'number', 'marketplace', 'Rwanda market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'NG', '13.0', 'number', 'marketplace', 'Nigeria market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'NG', '7.0', 'number', 'marketplace', 'Nigeria market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'ZA', '9.5', 'number', 'marketplace', 'South Africa market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'ZA', '5.0', 'number', 'marketplace', 'South Africa market baseline late payment rate percentage controlled by admin.', TRUE),
  ('market_interest_rate_baseline_pct', 'EG', '12.5', 'number', 'marketplace', 'Egypt market baseline interest rate percentage controlled by admin.', TRUE),
  ('market_late_payment_rate_baseline_pct', 'EG', '6.5', 'number', 'marketplace', 'Egypt market baseline late payment rate percentage controlled by admin.', TRUE)
ON CONFLICT (setting_key, COALESCE(country, '__global__')) DO UPDATE
SET
  setting_value = EXCLUDED.setting_value,
  updated_at = CURRENT_TIMESTAMP;
