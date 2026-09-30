/*
# Add Test Mode (Beta) Support to Booking Tables

## Overview
Adds `is_test_mode` boolean column to both taxi_bookings and hotel_bookings tables.
During the 1-month free test period, all bookings are tagged as test mode with
0% commission. This allows testing the full booking flow with partners before
official contracts and commission cuts take effect.

## Changes
- taxi_bookings: add is_test_mode boolean (default true during beta)
- hotel_bookings: add is_test_mode boolean (default true during beta)
- Set commission_rate to 0 for all existing bookings (test period)

## Security
- No RLS policy changes needed — is_test_mode is set by the application at insert time
*/

ALTER TABLE taxi_bookings
  ADD COLUMN IF NOT EXISTS is_test_mode boolean NOT NULL DEFAULT true;

ALTER TABLE hotel_bookings
  ADD COLUMN IF NOT EXISTS is_test_mode boolean NOT NULL DEFAULT true;

-- Set commission to 0 for all existing bookings during test period
UPDATE taxi_bookings SET commission_rate = 0 WHERE is_test_mode = true;
UPDATE hotel_bookings SET commission_rate = 0 WHERE is_test_mode = true;

CREATE INDEX IF NOT EXISTS idx_taxi_bookings_test_mode ON taxi_bookings(is_test_mode);
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_test_mode ON hotel_bookings(is_test_mode);