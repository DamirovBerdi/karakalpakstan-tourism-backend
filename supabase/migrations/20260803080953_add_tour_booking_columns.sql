/*
# Add tour booking columns to tourist_requests

## Purpose
The new Tours section booking form needs to store the tour name, travel date,
guest count, and buddy opt-in flag. The existing tourist_requests table
(from the Budget Planner) has budget_total, group_size, duration_days, interests
which are NOT applicable to tour bookings. We add nullable columns so both
the Budget Planner and Tour Booking flows can use the same table without
breaking existing rows.

## Changes to tourist_requests
- tour_name (text, nullable) — name of the booked tour
- travel_date (date, nullable) — preferred travel date
- guests (integer, nullable) — number of guests for the tour booking
- buddy_opt_in (boolean, nullable, default false) — whether the tourist wants
  to find a travel buddy / join an open group

## Security
- No policy changes needed — existing INSERT/SELECT policies for anon already
  cover the new columns (they are nullable, so existing inserts still work).

## Important Notes
1. All new columns are nullable so existing Budget Planner inserts that omit
   them continue to work without error.
2. No data is lost — this is purely additive.
*/

ALTER TABLE tourist_requests
  ADD COLUMN IF NOT EXISTS tour_name text,
  ADD COLUMN IF NOT EXISTS travel_date date,
  ADD COLUMN IF NOT EXISTS guests integer,
  ADD COLUMN IF NOT EXISTS buddy_opt_in boolean DEFAULT false;
