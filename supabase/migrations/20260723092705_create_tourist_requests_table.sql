/*
# Create tourist_requests table (single-tenant, no auth)

1. New Tables
- `tourist_requests` — stores custom travel requests submitted by tourists through the Budget Planner.
  - `id` (uuid, primary key)
  - `name` (text, not null) — tourist's name
  - `email` (text, not null) — tourist's email
  - `phone` (text, not null) — tourist's phone number
  - `budget_total` (integer, not null) — total budget in USD
  - `group_size` (integer, not null) — number of travelers
  - `duration_days` (integer, not null) — length of trip in days
  - `interests` (text[], nullable) — array of selected interests
  - `message` (text, nullable) — additional requests / special needs
  - `per_person_per_day` (numeric, nullable) — calculated per-person daily budget
  - `status` (text, not null, default 'pending') — request status
  - `created_at` (timestamptz, default now())

2. Security
- Enable RLS on `tourist_requests`.
- Allow anon + authenticated to INSERT (tourists submit requests without signing in).
- Allow anon + authenticated to SELECT (so the UI can confirm submission).
- No UPDATE or DELETE from the anon key — only service role manages status changes.
*/

CREATE TABLE IF NOT EXISTS tourist_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  phone text NOT NULL,
  budget_total integer NOT NULL,
  group_size integer NOT NULL,
  duration_days integer NOT NULL,
  interests text[],
  message text,
  per_person_per_day numeric,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE tourist_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_tourist_requests" ON tourist_requests;
CREATE POLICY "anon_select_tourist_requests" ON tourist_requests
FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anon_insert_tourist_requests" ON tourist_requests;
CREATE POLICY "anon_insert_tourist_requests" ON tourist_requests
FOR INSERT TO anon, authenticated WITH CHECK (true);
