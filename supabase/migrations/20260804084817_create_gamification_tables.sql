/*
# Create Gamification Tables: Badges, Points, Photo Contest, Quiz

## Overview
Adds the full gamification layer to Karakalpak Travel: QR check-in badges,
user points/rewards, photo contest with public voting, and quiz scoring.
Extends the existing auth and check-in system.

## New Tables

### 1. badges
- `id` (uuid, PK)
- `code` (text, unique) — the QR code identifier placed at physical locations
- `name` (text) — badge name
- `description` (text) — what the badge represents
- `place_name` (text) — the physical location
- `icon` (text) — lucide icon name for display
- `points` (int) — points awarded for earning this badge
- `image` (text) — optional location image URL
- `created_at` (timestamptz)
- Public read, admin-managed (authenticated can read; inserts are open to authenticated for now)

### 2. user_badges
- `id` (uuid, PK)
- `user_id` (uuid, references auth.users) — who earned it
- `badge_id` (uuid, references badges) — which badge
- `qr_code` (text) — the code that was scanned
- `created_at` (timestamptz)
- Unique constraint on (user_id, badge_id) — one per user per badge
- Public read (badges are visible on leaderboards), owner-only insert/delete

### 3. user_points
- `id` (uuid, PK)
- `user_id` (uuid, references auth.users) — who earned points
- `points` (int) — amount
- `reason` (text) — why (e.g. "qr_checkin", "quiz_win", "contest_vote")
- `created_at` (timestamptz)
- Public read (leaderboard), owner-only insert

### 4. photo_entries
- `id` (uuid, PK)
- `user_id` (uuid, references auth.users) — photographer
- `title` (text) — photo caption
- `image_url` (text) — photo URL
- `location` (text) — where the photo was taken
- `votes` (int, default 0) — cached vote count for fast sorting
- `created_at` (timestamptz)
- Public read, owner-only insert/delete

### 5. photo_votes
- `id` (uuid, PK)
- `user_id` (uuid, references auth.users) — voter
- `entry_id` (uuid, references photo_entries) — which photo
- `created_at` (timestamptz)
- Unique constraint on (user_id, entry_id) — one vote per user per photo
- Owner-only insert/delete

### 6. quiz_results
- `id` (uuid, PK)
- `user_id` (uuid, references auth.users) — player
- `score` (int) — number correct
- `total` (int) — total questions
- `points_earned` (int) — points awarded
- `created_at` (timestamptz)
- Public read (leaderboard), owner-only insert

## Security (RLS)
- badges: public read (anon+authenticated), authenticated insert.
- user_badges: public read, authenticated insert own, owner-only delete.
- user_points: public read, authenticated insert own.
- photo_entries: public read, authenticated insert own, owner-only delete.
- photo_votes: public read, authenticated insert own (one per photo), owner-only delete.
- quiz_results: public read, authenticated insert own.
*/

-- === badges ===
CREATE TABLE IF NOT EXISTS badges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  place_name text NOT NULL DEFAULT '',
  icon text NOT NULL DEFAULT 'Award',
  points integer NOT NULL DEFAULT 50,
  image text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE badges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "badges_read_all" ON badges;
CREATE POLICY "badges_read_all" ON badges FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "badges_insert_auth" ON badges;
CREATE POLICY "badges_insert_auth" ON badges FOR INSERT
  TO authenticated WITH CHECK (true);

-- Seed badge definitions
INSERT INTO badges (code, name, description, place_name, icon, points, image) VALUES
  ('KTK-SAVITSKY-2026', 'Art Pioneer', 'Visited the Savitsky Museum — the Louvre of the Desert', 'Savitsky Museum, Nukus', 'Palette', 100, ''),
  ('KTK-MOYNAQ-2026', 'Ship Graveyard Explorer', 'Stood among the rusted ships at the Aral Sea graveyard', 'Moynaq Ship Graveyard', 'Ship', 100, ''),
  ('KTK-MIZDAKHAN-2026', 'Ancient Pilgrim', 'Explored the 2000-year-old Mizdakhan Necropolis', 'Mizdakhan Necropolis', 'Landmark', 100, ''),
  ('KTK-CHILPYK-2026', 'Tower of Silence', 'Climbed the Zoroastrian dakhma at Chilpyk', 'Chilpyk Fortress', 'Mountain', 100, ''),
  ('KTK-USTYURT-2026', 'Plateau Conqueror', 'Reached the Ustyurt Plateau chalk cliffs', 'Ustyurt Plateau', 'Compass', 150, ''),
  ('KTK-SUDOCHYE-2026', 'Wetland Wanderer', 'Discovered the bird-filled Sudochye Lake', 'Lake Sudochye', 'Bird', 80, ''),
  ('KTK-NUKUS-BAZAAR-2026', 'Bazaar Shopper', 'Experienced the vibrant Nukus Bazaar', 'Nukus Bazaar', 'ShoppingBag', 50, ''),
  ('KTK-BERDAQ-2026', 'Poetry Lover', 'Visited the Berdaq Poetry Museum', 'Berdaq Museum, Nukus', 'BookOpen', 80, '')
ON CONFLICT (code) DO NOTHING;

-- === user_badges ===
CREATE TABLE IF NOT EXISTS user_badges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_id uuid NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  qr_code text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, badge_id)
);

ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_badges_read_all" ON user_badges;
CREATE POLICY "user_badges_read_all" ON user_badges FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "user_badges_insert_own" ON user_badges;
CREATE POLICY "user_badges_insert_own" ON user_badges FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_badges_delete_own" ON user_badges;
CREATE POLICY "user_badges_delete_own" ON user_badges FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);

-- === user_points ===
CREATE TABLE IF NOT EXISTS user_points (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  points integer NOT NULL DEFAULT 0,
  reason text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE user_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_points_read_all" ON user_points;
CREATE POLICY "user_points_read_all" ON user_points FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "user_points_insert_own" ON user_points;
CREATE POLICY "user_points_insert_own" ON user_points FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_user_points_user ON user_points(user_id);

-- === photo_entries ===
CREATE TABLE IF NOT EXISTS photo_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL DEFAULT '',
  image_url text NOT NULL,
  location text NOT NULL DEFAULT '',
  votes integer NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE photo_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "photo_entries_read_all" ON photo_entries;
CREATE POLICY "photo_entries_read_all" ON photo_entries FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "photo_entries_insert_own" ON photo_entries;
CREATE POLICY "photo_entries_insert_own" ON photo_entries FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "photo_entries_delete_own" ON photo_entries;
CREATE POLICY "photo_entries_delete_own" ON photo_entries FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_photo_entries_votes ON photo_entries(votes DESC);
CREATE INDEX IF NOT EXISTS idx_photo_entries_created ON photo_entries(created_at DESC);

-- === photo_votes ===
CREATE TABLE IF NOT EXISTS photo_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  entry_id uuid NOT NULL REFERENCES photo_entries(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, entry_id)
);

ALTER TABLE photo_votes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "photo_votes_read_all" ON photo_votes;
CREATE POLICY "photo_votes_read_all" ON photo_votes FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "photo_votes_insert_own" ON photo_votes;
CREATE POLICY "photo_votes_insert_own" ON photo_votes FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "photo_votes_delete_own" ON photo_votes;
CREATE POLICY "photo_votes_delete_own" ON photo_votes FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_photo_votes_entry ON photo_votes(entry_id);
CREATE INDEX IF NOT EXISTS idx_photo_votes_user ON photo_votes(user_id);

-- === quiz_results ===
CREATE TABLE IF NOT EXISTS quiz_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  score integer NOT NULL DEFAULT 0,
  total integer NOT NULL DEFAULT 10,
  points_earned integer NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE quiz_results ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quiz_results_read_all" ON quiz_results;
CREATE POLICY "quiz_results_read_all" ON quiz_results FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "quiz_results_insert_own" ON quiz_results;
CREATE POLICY "quiz_results_insert_own" ON quiz_results FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_quiz_results_user ON quiz_results(user_id);
