/*
# Create Community, GPS & Social Feature Tables

## Overview
Creates schema for geolocation and social community features: user profiles,
trip check-ins, traveler messaging, and location sharing. Also extends the
existing reviews table with user_id and photo_urls columns.

## Changes to Existing Tables

### reviews (already exists)
- ADD COLUMN `user_id` (uuid, nullable, references auth.users) — links review to author
- ADD COLUMN `photo_urls` (text[], default '{}') — uploaded photo URLs

## New Tables

### 1. community_profiles
- `id` (uuid, PK, references auth.users) — one-to-one with Supabase auth users
- `username` (text, unique) — display name
- `full_name` (text) — optional real name
- `avatar_url` (text) — profile photo URL
- `bio` (text) — short bio
- `home_country` (text) — where the traveler is from
- `travel_interests` (text[]) — interest tags
- `created_at` (timestamptz)

### 2. trip_checkins
- `id` (uuid, PK)
- `user_id` (uuid, references auth.users) — who checked in
- `place_name` (text) — name of place visited
- `place_id` (text) — optional place identifier
- `lat` / `lng` (numeric, nullable) — GPS coordinates
- `note` (text) — optional note
- `photo_url` (text) — optional photo
- `created_at` (timestamptz)

### 3. traveler_messages
- `id` (uuid, PK)
- `sender_id` / `recipient_id` (uuid, references auth.users)
- `content` (text) — message text
- `read` (boolean, default false)
- `created_at` (timestamptz)

### 4. location_shares
- `id` (uuid, PK)
- `user_id` (uuid, references auth.users)
- `lat` / `lng` (numeric) — shared coordinates
- `label` (text) — optional place label
- `expires_at` (timestamptz) — expiry
- `created_at` (timestamptz)

## Security (RLS)
- community_profiles: authenticated read all, insert/update own only.
- reviews: public read (anon+authenticated), authenticated insert, owner-only update/delete.
- trip_checkins: public read, authenticated insert, owner-only delete.
- traveler_messages: read own (sender or recipient), insert as sender, delete own sent.
- location_shares: public read (shared via link), authenticated insert, owner-only delete.
*/

-- === Extend existing reviews table ===
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'reviews' AND column_name = 'user_id') THEN
    ALTER TABLE reviews ADD COLUMN user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'reviews' AND column_name = 'photo_urls') THEN
    ALTER TABLE reviews ADD COLUMN photo_urls text[] DEFAULT '{}';
  END IF;
END $$;

-- Add owner-scoped policies to reviews (existing table already has RLS)
DROP POLICY IF EXISTS "reviews_insert_own" ON reviews;
CREATE POLICY "reviews_insert_own" ON reviews FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "reviews_update_own" ON reviews;
CREATE POLICY "reviews_update_own" ON reviews
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "reviews_delete_own" ON reviews;
CREATE POLICY "reviews_delete_own" ON reviews FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);

-- === community_profiles ===
CREATE TABLE IF NOT EXISTS community_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text UNIQUE NOT NULL,
  full_name text,
  avatar_url text,
  bio text DEFAULT '',
  home_country text DEFAULT '',
  travel_interests text[] DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE community_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_read_all" ON community_profiles;
CREATE POLICY "profiles_read_all" ON community_profiles FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "profiles_insert_own" ON community_profiles;
CREATE POLICY "profiles_insert_own" ON community_profiles FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON community_profiles;
CREATE POLICY "profiles_update_own" ON community_profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- === trip_checkins ===
CREATE TABLE IF NOT EXISTS trip_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  place_name text NOT NULL,
  place_id text DEFAULT '',
  lat numeric,
  lng numeric,
  note text DEFAULT '',
  photo_url text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE trip_checkins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "checkins_read_all" ON trip_checkins;
CREATE POLICY "checkins_read_all" ON trip_checkins FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "checkins_insert_own" ON trip_checkins;
CREATE POLICY "checkins_insert_own" ON trip_checkins FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "checkins_delete_own" ON trip_checkins;
CREATE POLICY "checkins_delete_own" ON trip_checkins FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_checkins_user_id ON trip_checkins(user_id);
CREATE INDEX IF NOT EXISTS idx_checkins_created_at ON trip_checkins(created_at DESC);

-- === traveler_messages ===
CREATE TABLE IF NOT EXISTS traveler_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content text NOT NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE traveler_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_read_own" ON traveler_messages;
CREATE POLICY "messages_read_own" ON traveler_messages FOR SELECT
  TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

DROP POLICY IF EXISTS "messages_insert_own" ON traveler_messages;
CREATE POLICY "messages_insert_own" ON traveler_messages FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "messages_delete_own" ON traveler_messages;
CREATE POLICY "messages_delete_own" ON traveler_messages FOR DELETE
  TO authenticated USING (auth.uid() = sender_id);

CREATE INDEX IF NOT EXISTS idx_messages_recipient ON traveler_messages(recipient_id, read);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON traveler_messages(sender_id);

-- === location_shares ===
CREATE TABLE IF NOT EXISTS location_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  lat numeric NOT NULL,
  lng numeric NOT NULL,
  label text DEFAULT '',
  expires_at timestamptz DEFAULT now() + interval '24 hours',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE location_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "location_shares_read_all" ON location_shares;
CREATE POLICY "location_shares_read_all" ON location_shares FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "location_shares_insert_own" ON location_shares;
CREATE POLICY "location_shares_insert_own" ON location_shares FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "location_shares_delete_own" ON location_shares;
CREATE POLICY "location_shares_delete_own" ON location_shares FOR DELETE
  TO authenticated USING (auth.uid() = user_id);
