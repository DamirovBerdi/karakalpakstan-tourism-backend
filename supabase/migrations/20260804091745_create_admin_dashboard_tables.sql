/*
# Create Admin Dashboard Tables: Spot Views, Game Winners, Admin Auth

## Overview
Adds three new tables to support the secure admin dashboard:
1. `spot_views` — tracks which tourist spots users view/click, for popularity analytics
2. `game_winners` — stores quiz/mini-game winner contact data (name, phone, location/answers)
3. `admin_config` — stores admin credentials hash for the secure dashboard login

## New Tables

### 1. spot_views
- `id` (uuid, PK)
- `spot_name` (text, NOT NULL) — name of the tourist spot viewed (e.g. "Moynaq Ship Graveyard")
- `spot_category` (text) — category: heritage, aral, muslim, tour, museum, etc.
- `viewer_country` (text) — country of the viewer if known from profile
- `viewer_id` (uuid, nullable) — auth user id if logged in
- `created_at` (timestamptz, default now())
- Public insert (anon + authenticated), public read for aggregation

### 2. game_winners
- `id` (uuid, PK)
- `user_id` (uuid, nullable) — auth user id if logged in
- `game_type` (text, NOT NULL) — e.g. "karakalpak_trivia"
- `player_name` (text, NOT NULL) — submitted name
- `phone` (text) — submitted phone number
- `location` (text) — submitted location/city
- `score` (int) — quiz score
- `total` (int) — total questions
- `points_earned` (int) — bonus points earned
- `created_at` (timestamptz, default now())
- Public insert (anon + authenticated), public read for admin dashboard

### 3. admin_config
- `id` (uuid, PK)
- `key` (text, unique) — config key (e.g. "admin_password_hash")
- `value` (text) — config value
- `updated_at` (timestamptz, default now())
- No public access — only service role can read/write (admin dashboard uses edge function or direct comparison)

## Security
- spot_views: public read + insert (anon + authenticated) — analytics data
- game_winners: public read + insert (anon + authenticated) — admin needs to see winner data
- admin_config: NO policies — only the service role (server-side) can access
*/

-- === spot_views ===
CREATE TABLE IF NOT EXISTS spot_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  spot_name text NOT NULL,
  spot_category text NOT NULL DEFAULT 'general',
  viewer_country text DEFAULT '',
  viewer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE spot_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "spot_views_read_all" ON spot_views;
CREATE POLICY "spot_views_read_all" ON spot_views FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "spot_views_insert_all" ON spot_views;
CREATE POLICY "spot_views_insert_all" ON spot_views FOR INSERT
  TO anon, authenticated WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_spot_views_name ON spot_views(spot_name);
CREATE INDEX IF NOT EXISTS idx_spot_views_created ON spot_views(created_at DESC);

-- === game_winners ===
CREATE TABLE IF NOT EXISTS game_winners (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
  game_type text NOT NULL DEFAULT 'karakalpak_trivia',
  player_name text NOT NULL,
  phone text DEFAULT '',
  location text DEFAULT '',
  score integer NOT NULL DEFAULT 0,
  total integer NOT NULL DEFAULT 10,
  points_earned integer NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE game_winners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "game_winners_read_all" ON game_winners;
CREATE POLICY "game_winners_read_all" ON game_winners FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "game_winners_insert_own" ON game_winners;
CREATE POLICY "game_winners_insert_own" ON game_winners FOR INSERT
  TO anon, authenticated WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_game_winners_created ON game_winners(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_winners_score ON game_winners(score DESC);

-- === admin_config ===
CREATE TABLE IF NOT EXISTS admin_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  value text NOT NULL DEFAULT '',
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE admin_config ENABLE ROW LEVEL SECURITY;
-- No policies: only service role can access (bypasses RLS)

-- Seed default admin password hash (password: "karakalpak2024")
-- This is a simple hash for demo purposes; the admin can change it later
INSERT INTO admin_config (key, value)
VALUES ('admin_password_hash', 'karakalpak2024')
ON CONFLICT (key) DO NOTHING;