/*
# Create Hotel Bookings Table

## Overview
Creates the `hotel_bookings` table to power the Nukus Hotels partnership booking system.
Tourists select a hotel, room type, check-in/check-out dates, and guest count;
bookings are auto-assigned a unique tracking ID (#SK-H101 format) and managed
in the admin dashboard with 10% commission tracking.

## New Table: hotel_bookings
- `id` (uuid, PK)
- `tracking_id` (text, unique) — human-readable booking ID like #SK-H101
- `hotel_name` (text, NOT NULL) — name of the hotel
- `room_type` (text, NOT NULL) — room type selected (Standard, Deluxe, etc.)
- `guest_name` (text, NOT NULL) — guest's full name
- `email` (text) — contact email
- `phone` (text, NOT NULL) — contact phone
- `check_in` (date, NOT NULL) — check-in date
- `check_out` (date, NOT NULL) — check-out date
- `guests` (int, NOT NULL, default 1) — number of guests
- `nights` (int, NOT NULL, default 1) — number of nights (auto-calculated)
- `price_per_night` (numeric, NOT NULL) — room price per night
- `total_price` (numeric, NOT NULL) — nights * price_per_night
- `commission_rate` (numeric, default 10) — commission percentage
- `status` (text, default 'pending') — pending / confirmed / completed / cancelled
- `language` (text, default 'en') — language used during booking
- `notes` (text) — optional special requests
- `created_at` (timestamptz, default now())

## Security
- RLS enabled.
- Public read + insert (anon + authenticated): tourists submit without logging in.
- No update/delete policies for anon — only the service role (admin) can change
  status or price, preventing visitors from altering bookings.
*/

CREATE TABLE IF NOT EXISTS hotel_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tracking_id text UNIQUE NOT NULL,
  hotel_name text NOT NULL,
  room_type text NOT NULL,
  guest_name text NOT NULL,
  email text,
  phone text NOT NULL,
  check_in date NOT NULL,
  check_out date NOT NULL,
  guests integer NOT NULL DEFAULT 1,
  nights integer NOT NULL DEFAULT 1,
  price_per_night numeric NOT NULL DEFAULT 0,
  total_price numeric NOT NULL DEFAULT 0,
  commission_rate numeric NOT NULL DEFAULT 10,
  status text NOT NULL DEFAULT 'pending',
  language text DEFAULT 'en',
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE hotel_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hotel_bookings_read_all" ON hotel_bookings;
CREATE POLICY "hotel_bookings_read_all" ON hotel_bookings FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "hotel_bookings_insert_all" ON hotel_bookings;
CREATE POLICY "hotel_bookings_insert_all" ON hotel_bookings FOR INSERT
  TO anon, authenticated WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_hotel_bookings_status ON hotel_bookings(status);
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_created ON hotel_bookings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_tracking ON hotel_bookings(tracking_id);

-- === Auto-generate tracking IDs via trigger ===
-- Format: #SK-HXXX where XXX is a sequential number starting at 101
CREATE OR REPLACE FUNCTION generate_hotel_tracking_id()
RETURNS trigger AS $$
DECLARE
  next_num integer;
BEGIN
  SELECT COALESCE(MAX(seq_num), 100) + 1 INTO next_num
  FROM (
    SELECT CAST(
      SUBSTRING(tracking_id FROM '#SK-H([0-9]+)') AS integer
    ) AS seq_num
    FROM hotel_bookings
    WHERE tracking_id ~ '^#SK-H[0-9]+$'
  ) sub;
  NEW.tracking_id := '#SK-H' || next_num;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_hotel_tracking_id ON hotel_bookings;
CREATE TRIGGER set_hotel_tracking_id
  BEFORE INSERT ON hotel_bookings
  FOR EACH ROW
  WHEN (NEW.tracking_id IS NULL OR NEW.tracking_id = '')
  EXECUTE FUNCTION generate_hotel_tracking_id();