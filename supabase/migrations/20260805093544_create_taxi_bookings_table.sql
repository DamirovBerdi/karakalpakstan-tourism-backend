/*
# Create Taxi Booking Table

## Overview
Creates the `taxi_bookings` table to power the 1222 Taxi partnership booking system.
International tourists submit pickup/drop-off details through a multilingual form;
bookings are auto-assigned a unique tracking ID (#SK-101 format) and managed in the
admin dashboard with commission tracking.

## New Table: taxi_bookings
- `id` (uuid, PK)
- `tracking_id` (text, unique) — human-readable booking ID like #SK-101
- `tourist_name` (text, NOT NULL) — tourist's full name
- `email` (text) — contact email
- `phone` (text, NOT NULL) — contact phone
- `pickup_location` (text, NOT NULL) — where to be picked up
- `dropoff_location` (text, NOT NULL) — destination
- `travel_datetime` (timestamptz, NOT NULL) — when the taxi is needed
- `passengers` (int, NOT NULL, default 1) — number of passengers
- `notes` (text) — optional special requests (luggage, child seat, etc.)
- `language` (text, default 'en') — language the tourist used
- `total_price` (numeric, default 0) — manually set by admin
- `commission_rate` (numeric, default 10) — commission percentage (e.g. 10 = 10%)
- `status` (text, default 'pending') — pending / confirmed / completed / cancelled
- `created_at` (timestamptz, default now())

## Security
- RLS enabled.
- Public read + insert (anon + authenticated): tourists submit without logging in.
- No update/delete policies for anon — only the service role (admin) can change
  status, price, or commission, preventing visitors from altering bookings.
*/

CREATE TABLE IF NOT EXISTS taxi_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tracking_id text UNIQUE NOT NULL,
  tourist_name text NOT NULL,
  email text,
  phone text NOT NULL,
  pickup_location text NOT NULL,
  dropoff_location text NOT NULL,
  travel_datetime timestamptz NOT NULL,
  passengers integer NOT NULL DEFAULT 1,
  notes text DEFAULT '',
  language text DEFAULT 'en',
  total_price numeric NOT NULL DEFAULT 0,
  commission_rate numeric NOT NULL DEFAULT 10,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE taxi_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "taxi_bookings_read_all" ON taxi_bookings;
CREATE POLICY "taxi_bookings_read_all" ON taxi_bookings FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "taxi_bookings_insert_all" ON taxi_bookings;
CREATE POLICY "taxi_bookings_insert_all" ON taxi_bookings FOR INSERT
  TO anon, authenticated WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_taxi_bookings_status ON taxi_bookings(status);
CREATE INDEX IF NOT EXISTS idx_taxi_bookings_created ON taxi_bookings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_taxi_bookings_tracking ON taxi_bookings(tracking_id);

-- === Auto-generate tracking IDs via trigger ===
-- Format: #SK-XXX where XXX is a sequential number starting at 101
CREATE OR REPLACE FUNCTION generate_taxi_tracking_id()
RETURNS trigger AS $$
DECLARE
  next_num integer;
BEGIN
  SELECT COALESCE(MAX(seq_num), 100) + 1 INTO next_num
  FROM (
    SELECT CAST(
      SUBSTRING(tracking_id FROM '#SK-([0-9]+)') AS integer
    ) AS seq_num
    FROM taxi_bookings
    WHERE tracking_id ~ '^#SK-[0-9]+$'
  ) sub;
  NEW.tracking_id := '#SK-' || next_num;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_taxi_tracking_id ON taxi_bookings;
CREATE TRIGGER set_taxi_tracking_id
  BEFORE INSERT ON taxi_bookings
  FOR EACH ROW
  WHEN (NEW.tracking_id IS NULL OR NEW.tracking_id = '')
  EXECUTE FUNCTION generate_taxi_tracking_id();