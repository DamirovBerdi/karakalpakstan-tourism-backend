-- ==============================================================================
-- Migration: Comprehensive Security Hardening & Row Level Security (RLS) Fix
-- Date: 2026-09-18
-- Description:
--   1. Fixes critical PII leaks (passports, phone numbers, emails, addresses).
--   2. Prevents unauthorized deletion and tampering of guides & tour agencies.
--   3. Locks down admin_config table against unauthorized anonymous writes.
--   4. Establishes robust role-based admin access control via is_admin() function.
-- ==============================================================================

-- 1. Create Admin Users table (Tracks authorized administrators)
CREATE TABLE IF NOT EXISTS admin_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  email text UNIQUE NOT NULL,
  role text NOT NULL DEFAULT 'Super Admin',
  display_name text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- 2. Helper Security Definer Function: Check if current caller is an authorized Admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean AS $$
BEGIN
  -- Returns true if user is authenticated and registered in admin_users,
  -- or if their email matches designated super admin domains/accounts.
  RETURN (
    auth.role() = 'authenticated' AND (
      EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) OR
      (auth.jwt() ->> 'email') ILIKE '%@karakalpak.travel' OR
      (auth.jwt() ->> 'email') IN (
        'azada122321@karakalpak.travel',
        'damir122321@karakalpak.travel',
        'admin@karakalpak.travel'
      )
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Admin Users Policies
DROP POLICY IF EXISTS "admin_users_view_by_admin" ON admin_users;
CREATE POLICY "admin_users_view_by_admin" ON admin_users
  FOR SELECT TO authenticated USING (is_admin() OR auth.uid() = user_id);

DROP POLICY IF EXISTS "admin_users_manage_by_admin" ON admin_users;
CREATE POLICY "admin_users_manage_by_admin" ON admin_users
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 3. Fix VISA APPLICATIONS (Critical: Passport & PII Data Leak Fix)
-- ==============================================================================
ALTER TABLE visa_applications ENABLE ROW LEVEL SECURITY;

-- Remove dangerous public read of passports
DROP POLICY IF EXISTS "va_select_all" ON visa_applications;
DROP POLICY IF EXISTS "visa_select_own_or_admin" ON visa_applications;

-- Only authenticated admins can read all visa applications
CREATE POLICY "visa_select_admin" ON visa_applications
  FOR SELECT TO authenticated
  USING (is_admin());

-- Tourists can still insert applications without login
DROP POLICY IF EXISTS "va_insert_all" ON visa_applications;
CREATE POLICY "va_insert_all" ON visa_applications
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- Only admins can update or delete visa applications
DROP POLICY IF EXISTS "visa_manage_admin" ON visa_applications;
CREATE POLICY "visa_manage_admin" ON visa_applications
  FOR UPDATE TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 4. Fix TOURIST REQUESTS (Custom Tours & Budget Planner Inquiries)
-- ==============================================================================
ALTER TABLE tourist_requests ENABLE ROW LEVEL SECURITY;

-- Remove dangerous public read of phone numbers & emails
DROP POLICY IF EXISTS "anon_select_tourist_requests" ON tourist_requests;
DROP POLICY IF EXISTS "tourist_requests_select_admin" ON tourist_requests;

-- Only admins can read customer inquiries
CREATE POLICY "tourist_requests_select_admin" ON tourist_requests
  FOR SELECT TO authenticated
  USING (is_admin());

-- Tourists can submit inquiries freely
DROP POLICY IF EXISTS "anon_insert_tourist_requests" ON tourist_requests;
CREATE POLICY "anon_insert_tourist_requests" ON tourist_requests
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- Only admins can change request statuses
DROP POLICY IF EXISTS "tourist_requests_manage_admin" ON tourist_requests;
CREATE POLICY "tourist_requests_manage_admin" ON tourist_requests
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 5. Fix TAXI BOOKINGS (1222 Taxi Customer Private Data)
-- ==============================================================================
ALTER TABLE taxi_bookings ENABLE ROW LEVEL SECURITY;

-- Remove public dump of passenger names & pickup locations
DROP POLICY IF EXISTS "taxi_bookings_read_all" ON taxi_bookings;
DROP POLICY IF EXISTS "taxi_bookings_select_admin" ON taxi_bookings;

CREATE POLICY "taxi_bookings_select_admin" ON taxi_bookings
  FOR SELECT TO authenticated
  USING (is_admin());

-- Public can submit new bookings
DROP POLICY IF EXISTS "taxi_bookings_insert_all" ON taxi_bookings;
CREATE POLICY "taxi_bookings_insert_all" ON taxi_bookings
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- Only admins can manage taxi bookings (confirm, cancel, assign prices)
DROP POLICY IF EXISTS "taxi_bookings_manage_admin" ON taxi_bookings;
CREATE POLICY "taxi_bookings_manage_admin" ON taxi_bookings
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 6. Fix HOTEL BOOKINGS (Nukus Hotels Partnership Data)
-- ==============================================================================
ALTER TABLE hotel_bookings ENABLE ROW LEVEL SECURITY;

-- Remove public read
DROP POLICY IF EXISTS "hotel_bookings_read_all" ON hotel_bookings;
DROP POLICY IF EXISTS "hotel_bookings_select_admin" ON hotel_bookings;

CREATE POLICY "hotel_bookings_select_admin" ON hotel_bookings
  FOR SELECT TO authenticated
  USING (is_admin());

-- Public can submit hotel bookings
DROP POLICY IF EXISTS "hotel_bookings_insert_all" ON hotel_bookings;
CREATE POLICY "hotel_bookings_insert_all" ON hotel_bookings
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- Only admins can update status or delete
DROP POLICY IF EXISTS "hotel_bookings_manage_admin" ON hotel_bookings;
CREATE POLICY "hotel_bookings_manage_admin" ON hotel_bookings
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 7. Fix GUIDES (Protect against unauthorized deletion)
-- ==============================================================================
ALTER TABLE guides ENABLE ROW LEVEL SECURITY;

-- Remove dangerous "manage_all" for anon
DROP POLICY IF EXISTS "guides_manage_auth" ON guides;
DROP POLICY IF EXISTS "guides_manage_all" ON guides;

-- Public can read guides catalog
DROP POLICY IF EXISTS "guides_read_all" ON guides;
CREATE POLICY "guides_read_all" ON guides
  FOR SELECT TO anon, authenticated
  USING (true);

-- Only authenticated admins can add, update, or delete guides
CREATE POLICY "guides_manage_admin" ON guides
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 8. Fix TOUR AGENCIES (Protect against unauthorized deletion)
-- ==============================================================================
ALTER TABLE tour_agencies ENABLE ROW LEVEL SECURITY;

-- Remove dangerous "manage_all" for anon
DROP POLICY IF EXISTS "agencies_manage_all" ON tour_agencies;
DROP POLICY IF EXISTS "agencies_manage_auth" ON tour_agencies;

-- Public can read agency list
DROP POLICY IF EXISTS "agencies_read_all" ON tour_agencies;
CREATE POLICY "agencies_read_all" ON tour_agencies
  FOR SELECT TO anon, authenticated
  USING (true);

-- Only authenticated admins can add, edit, or delete agencies
CREATE POLICY "agencies_manage_admin" ON tour_agencies
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 9. Fix ADMIN CONFIG (Lock down system configuration)
-- ==============================================================================
ALTER TABLE admin_config ENABLE ROW LEVEL SECURITY;

-- Remove dangerous anonymous update/upsert
DROP POLICY IF EXISTS "admin_config_read_all" ON admin_config;
DROP POLICY IF EXISTS "admin_config_upsert_all" ON admin_config;
DROP POLICY IF EXISTS "admin_config_update_all" ON admin_config;

-- Only authenticated admins can read and write system configuration
CREATE POLICY "admin_config_read_admin" ON admin_config
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_config_write_admin" ON admin_config
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());


-- ==============================================================================
-- 10. Fix GAME WINNERS (Protect players' private phone numbers)
-- ==============================================================================
ALTER TABLE game_winners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "game_winners_read_all" ON game_winners;

-- Only admins can see player contact information
CREATE POLICY "game_winners_select_admin" ON game_winners
  FOR SELECT TO authenticated
  USING (is_admin() OR auth.uid() = user_id);

-- Players can submit quiz scores
DROP POLICY IF EXISTS "game_winners_insert_own" ON game_winners;
CREATE POLICY "game_winners_insert_own" ON game_winners
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);


-- ==============================================================================
-- 11. Fix VISITOR SESSIONS & PAGE VIEWS (Protect IP addresses & telemetry)
-- ==============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'visitor_sessions') THEN
    ALTER TABLE visitor_sessions ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "visitor_sessions_read_all" ON visitor_sessions;
    CREATE POLICY "visitor_sessions_select_admin" ON visitor_sessions
      FOR SELECT TO authenticated USING (is_admin());
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'page_views') THEN
    ALTER TABLE page_views ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "page_views_read_all" ON page_views;
    CREATE POLICY "page_views_select_admin" ON page_views
      FOR SELECT TO authenticated USING (is_admin());
  END IF;
END $$;
