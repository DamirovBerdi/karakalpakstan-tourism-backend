/*
# Create travel_buddies and open_groups tables for Travel Buddy & Group Matcher

## Purpose
Enables the "Travel Buddy & Group Matcher" community feature where solo travelers
can find partners for the same destination/date and join open tour groups to split costs.

## New Tables

### travel_buddies
Stores solo travelers looking for a buddy to visit a specific destination on a specific date.
- id (uuid, PK)
- name (text, not null) — display name of the traveler
- destination (text, not null) — e.g. "Moynaq", "Nukus Museum"
- travel_date (date, not null) — the date they want to travel
- contact (text, not null) — phone, email, or Telegram handle
- languages (text, nullable) — languages the traveler speaks
- notes (text, nullable) — free-form message
- status (text, default 'searching') — 'searching' or 'matched'
- created_at (timestamptz, default now())

### open_groups
Stores public tour groups created by travelers that others can join to split costs.
- id (uuid, PK)
- title (text, not null) — group name, e.g. "Nukus Tour - 4 people group"
- destination (text, not null) — where the group is going
- travel_date (date, not null) — date of the trip
- max_members (int, default 4) — maximum group size
- current_members (int, default 1) — how many are already in
- creator_name (text, not null) — who created the group
- creator_contact (text, not null) — contact info
- cost_per_person (numeric, default 0) — estimated cost to split
- notes (text, nullable) — description / itinerary
- status (text, default 'open') — 'open' or 'full' or 'closed'
- created_at (timestamptz, default now())

## Security
- This is a NO-AUTH app (no sign-in screen). All policies use `TO anon, authenticated`
  so the anon-key frontend can read and write community data.
- RLS is enabled on both tables.
- USING (true) is acceptable because this data is intentionally public/shared
  — the whole point is for travelers to discover each other's requests.

## Important Notes
1. Both tables are single-tenant / public — any visitor can list, create, and
   (for open_groups) increment the member count by joining.
2. current_members is incremented client-side via an UPDATE; the policy allows
   anon updates so the "Join Group" button works without auth.
3. No user_id columns since there is no authentication in this app.
*/

CREATE TABLE IF NOT EXISTS travel_buddies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  destination text NOT NULL,
  travel_date date NOT NULL,
  contact text NOT NULL,
  languages text,
  notes text,
  status text NOT NULL DEFAULT 'searching',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE travel_buddies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tb_select_all" ON travel_buddies;
CREATE POLICY "tb_select_all" ON travel_buddies FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "tb_insert_all" ON travel_buddies;
CREATE POLICY "tb_insert_all" ON travel_buddies FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "tb_update_all" ON travel_buddies;
CREATE POLICY "tb_update_all" ON travel_buddies FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "tb_delete_all" ON travel_buddies;
CREATE POLICY "tb_delete_all" ON travel_buddies FOR DELETE
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS open_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  destination text NOT NULL,
  travel_date date NOT NULL,
  max_members int NOT NULL DEFAULT 4,
  current_members int NOT NULL DEFAULT 1,
  creator_name text NOT NULL,
  creator_contact text NOT NULL,
  cost_per_person numeric NOT NULL DEFAULT 0,
  notes text,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE open_groups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "og_select_all" ON open_groups;
CREATE POLICY "og_select_all" ON open_groups FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "og_insert_all" ON open_groups;
CREATE POLICY "og_insert_all" ON open_groups FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "og_update_all" ON open_groups;
CREATE POLICY "og_update_all" ON open_groups FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "og_delete_all" ON open_groups;
CREATE POLICY "og_delete_all" ON open_groups FOR DELETE
  TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_travel_buddies_destination ON travel_buddies(destination);
CREATE INDEX IF NOT EXISTS idx_travel_buddies_status ON travel_buddies(status);
CREATE INDEX IF NOT EXISTS idx_open_groups_destination ON open_groups(destination);
CREATE INDEX IF NOT EXISTS idx_open_groups_status ON open_groups(status);
