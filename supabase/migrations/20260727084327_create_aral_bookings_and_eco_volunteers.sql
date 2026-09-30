/*
# Create Aral Sea booking and eco-volunteering tables

## Purpose
Supports the "Aral Sea Experience" hub — adventure tour bookings and eco-volunteering
project registrations. Both are single-tenant (no sign-in) public forms: any visitor can
submit a booking request or volunteer registration, and the platform operators review them
on the backend. No user accounts are involved.

## New Tables

### aral_bookings
Stores booking requests for Aral Sea adventure tours (jeep tours, quad biking, yurt camps).
- `id` (uuid, PK)
- `tour_id` (text, NOT NULL) — references a tour slug from the static catalog in the frontend
- `tour_name` (text, NOT NULL) — denormalized tour name for admin readability
- `name` (text, NOT NULL) — visitor's full name
- `email` (text, NOT NULL) — visitor's email
- `phone` (text, NOT NULL) — visitor's phone number
- `date` (date, NOT NULL) — preferred tour date
- `group_size` (int, NOT NULL, default 1) — number of people
- `message` (text) — optional notes / special requests
- `status` (text, NOT NULL, default 'pending') — admin workflow: pending / confirmed / completed / cancelled
- `created_at` (timestamptz, default now())

### eco_volunteers
Stores registrations for eco-volunteering projects (e.g. saxaul tree planting in Muynak).
- `id` (uuid, PK)
- `project_id` (text, NOT NULL) — references a project slug from the static catalog
- `project_name` (text, NOT NULL) — denormalized project name
- `name` (text, NOT NULL) — volunteer's full name
- `email` (text, NOT NULL) — volunteer's email
- `phone` (text, NOT NULL) — volunteer's phone
- `country` (text, NOT NULL) — volunteer's country of origin
- `preferred_date` (date) — optional preferred participation date
- `message` (text) — optional notes / motivation
- `status` (text, NOT NULL, default 'pending') — admin workflow: pending / approved / participated / declined
- `created_at` (timestamptz, default now())

## Security
- RLS enabled on both tables.
- Public read + insert for `anon, authenticated` (single-tenant, no-auth app — visitors
  submit forms without logging in; operators read submissions via the Supabase dashboard).
- No update or delete policies exposed to the anon client — only the service role
  (dashboard) can change status or remove rows, preventing visitors from altering
  each other's submissions.
*/

CREATE TABLE IF NOT EXISTS aral_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tour_id text NOT NULL,
  tour_name text NOT NULL,
  name text NOT NULL,
  email text NOT NULL,
  phone text NOT NULL,
  date date NOT NULL,
  group_size int NOT NULL DEFAULT 1,
  message text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE aral_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_aral_bookings" ON aral_bookings;
CREATE POLICY "anon_select_aral_bookings" ON aral_bookings FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anon_insert_aral_bookings" ON aral_bookings;
CREATE POLICY "anon_insert_aral_bookings" ON aral_bookings FOR INSERT
  TO anon, authenticated WITH CHECK (true);


CREATE TABLE IF NOT EXISTS eco_volunteers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  project_name text NOT NULL,
  name text NOT NULL,
  email text NOT NULL,
  phone text NOT NULL,
  country text NOT NULL,
  preferred_date date,
  message text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE eco_volunteers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_eco_volunteers" ON eco_volunteers;
CREATE POLICY "anon_select_eco_volunteers" ON eco_volunteers FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anon_insert_eco_volunteers" ON eco_volunteers;
CREATE POLICY "anon_insert_eco_volunteers" ON eco_volunteers FOR INSERT
  TO anon, authenticated WITH CHECK (true);
