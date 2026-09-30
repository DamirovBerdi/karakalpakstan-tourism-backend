-- ==============================================================================
-- Migration: Fix All Missing Tables, Constraints, and Policies
-- Date: 2026-08-07 10:00:00
-- ==============================================================================

-- 1. Fix constraints on tourist_requests (allow nullable / defaults for flight & tour bookings)
DO $$
BEGIN
  -- Drop NOT NULL constraints if they exist
  ALTER TABLE tourist_requests ALTER COLUMN budget_total DROP NOT NULL;
  ALTER TABLE tourist_requests ALTER COLUMN group_size DROP NOT NULL;
  ALTER TABLE tourist_requests ALTER COLUMN duration_days DROP NOT NULL;

  -- Set safe defaults
  ALTER TABLE tourist_requests ALTER COLUMN budget_total SET DEFAULT 0;
  ALTER TABLE tourist_requests ALTER COLUMN group_size SET DEFAULT 1;
  ALTER TABLE tourist_requests ALTER COLUMN duration_days SET DEFAULT 1;
EXCEPTION
  WHEN undefined_table THEN
    -- If tourist_requests does not exist, it will be created by its base migration
    NULL;
END $$;

-- 2. Create table reviews if it does not already exist
CREATE TABLE IF NOT EXISTS reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  place_id text NOT NULL,
  place_name text NOT NULL,
  rating integer NOT NULL DEFAULT 5 CHECK (rating >= 1 AND rating <= 5),
  comment text NOT NULL,
  photo_urls text[] DEFAULT '{}',
  author_name text,
  country text,
  is_verified_trip boolean DEFAULT false,
  trip_date date,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reviews_read_all" ON reviews;
CREATE POLICY "reviews_read_all" ON reviews FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "reviews_insert_public" ON reviews;
CREATE POLICY "reviews_insert_public" ON reviews FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "reviews_modify_own" ON reviews;
CREATE POLICY "reviews_modify_own" ON reviews FOR UPDATE
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "reviews_delete_own" ON reviews;
CREATE POLICY "reviews_delete_own" ON reviews FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_reviews_place_id ON reviews(place_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created ON reviews(created_at DESC);

-- 3. Create table guides if it does not already exist
CREATE TABLE IF NOT EXISTS guides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  photo text DEFAULT '',
  rating numeric DEFAULT 5.0,
  reviews_count integer DEFAULT 1,
  languages text[] DEFAULT '{}',
  specialties text[] DEFAULT '{}',
  daily_rate numeric DEFAULT 45,
  phone text DEFAULT '',
  whatsapp text DEFAULT '',
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE guides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "guides_read_all" ON guides;
CREATE POLICY "guides_read_all" ON guides FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "guides_manage_auth" ON guides;
CREATE POLICY "guides_manage_auth" ON guides FOR ALL
  TO anon, authenticated USING (true) WITH CHECK (true);

-- 4. Create table tour_agencies if it does not already exist
CREATE TABLE IF NOT EXISTS tour_agencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  contact_person text DEFAULT '',
  phone text DEFAULT '',
  email text DEFAULT '',
  city text DEFAULT 'Nukus',
  commission_rate numeric DEFAULT 10,
  active_tours integer DEFAULT 0,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE tour_agencies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "agencies_read_all" ON tour_agencies;
CREATE POLICY "agencies_read_all" ON tour_agencies FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "agencies_manage_all" ON tour_agencies FOR ALL
  TO anon, authenticated USING (true) WITH CHECK (true);

-- 5. Fix admin_config RLS policies to prevent silent query failure
ALTER TABLE admin_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_config_read_all" ON admin_config;
CREATE POLICY "admin_config_read_all" ON admin_config FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "admin_config_upsert_all" ON admin_config;
CREATE POLICY "admin_config_upsert_all" ON admin_config FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "admin_config_update_all" ON admin_config;
CREATE POLICY "admin_config_update_all" ON admin_config FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);
