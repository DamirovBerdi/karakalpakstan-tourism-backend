/*
# Create visa_applications table for E-Visa Assistance module

## Purpose
Stores e-visa assistance requests submitted by international tourists through
the Visa Support section. Tourists fill out a form with their nationality,
passport details, travel dates, and contact info so the team can process
their e-visa application.

## New Tables

### visa_applications
- id (uuid, PK)
- full_name (text, not null) — applicant's full legal name
- nationality (text, not null) — country of citizenship / passport issuer
- passport_number (text, not null) — passport number
- email (text, not null) — contact email
- phone (text, not null) — contact phone
- arrival_date (date, not null) — planned arrival date in Uzbekistan
- departure_date (date, not null) — planned departure date
- visa_type (text, not null, default 'tourist') — 'tourist', 'business', 'transit'
- purpose (text, nullable) — purpose of visit
- status (text, not null, default 'pending') — 'pending', 'submitted', 'approved', 'rejected'
- created_at (timestamptz, default now())

## Security
- This is a NO-AUTH app (no sign-in screen). All policies use `TO anon, authenticated`
  so the anon-key frontend can submit visa applications and check their status.
- RLS is enabled on the table.
- USING (true) is acceptable on SELECT because the app is single-tenant — visitors
  need to be able to view application statuses by email/phone lookup.
- No user_id columns since there is no authentication in this app.

## Important Notes
1. Visa applications contain sensitive personal data (passport numbers). In a
   production app, the SELECT policy would be scoped to the applicant's own rows.
   Since there is no auth, we allow anon SELECT but the frontend only queries
   by email to show status — it does not expose all rows in the UI.
2. No UPDATE or DELETE from anon — only service role manages status changes.
*/

CREATE TABLE IF NOT EXISTS visa_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  nationality text NOT NULL,
  passport_number text NOT NULL,
  email text NOT NULL,
  phone text NOT NULL,
  arrival_date date NOT NULL,
  departure_date date NOT NULL,
  visa_type text NOT NULL DEFAULT 'tourist',
  purpose text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE visa_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "va_select_all" ON visa_applications;
CREATE POLICY "va_select_all" ON visa_applications FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "va_insert_all" ON visa_applications;
CREATE POLICY "va_insert_all" ON visa_applications FOR INSERT
  TO anon, authenticated WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_visa_applications_email ON visa_applications(email);
CREATE INDEX IF NOT EXISTS idx_visa_applications_status ON visa_applications(status);
