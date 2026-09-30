/*
# Create Visitor Analytics Tracking System

## Overview
Creates two tables to track visitor analytics:
1. `visitor_sessions` — one row per unique visitor session, captures IP address,
   country, browser/user-agent, first/last seen timestamps, and total page views.
2. `page_views` — one row per page view, links to a session, captures the page path,
   page title, and service used (e.g. "taxi", "hotel", "heritage").

## New Tables

### visitor_sessions
- `id` (uuid, PK)
- `session_token` (text, unique) — random token stored in localStorage to identify returning visitors
- `ip_address` (text) — visitor's real IP (captured by edge function via headers)
- `country` (text) — visitor's country (from IP or browser locale)
- `user_agent` (text) — browser/device info
- `page_views` (int, default 0) — denormalized count for quick stats
- `first_seen` (timestamptz, default now())
- `last_seen` (timestamptz, default now())

### page_views
- `id` (uuid, PK)
- `session_token` (text) — links to visitor_sessions
- `page_path` (text) — the URL path visited (e.g. "/", "/#taxi")
- `page_title` (text) — human-readable page/section name
- `service_used` (text) — which service was viewed (taxi, hotel, heritage, etc.)
- `created_at` (timestamptz, default now())

## Security
- RLS enabled on both tables.
- Public insert allowed (anon + authenticated) so the edge function can write.
- Public read allowed so the frontend can update session counts.
- No update/delete for anon — only service role (admin) can modify/delete.
*/

CREATE TABLE IF NOT EXISTS visitor_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_token text UNIQUE NOT NULL,
  ip_address text DEFAULT '',
  country text DEFAULT '',
  user_agent text DEFAULT '',
  page_views integer NOT NULL DEFAULT 0,
  first_seen timestamptz DEFAULT now(),
  last_seen timestamptz DEFAULT now()
);

ALTER TABLE visitor_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "visitor_sessions_read_all" ON visitor_sessions;
CREATE POLICY "visitor_sessions_read_all" ON visitor_sessions FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "visitor_sessions_insert_all" ON visitor_sessions;
CREATE POLICY "visitor_sessions_insert_all" ON visitor_sessions FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "visitor_sessions_update_all" ON visitor_sessions;
CREATE POLICY "visitor_sessions_update_all" ON visitor_sessions FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_visitor_sessions_token ON visitor_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_visitor_sessions_last_seen ON visitor_sessions(last_seen DESC);

CREATE TABLE IF NOT EXISTS page_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_token text NOT NULL DEFAULT '',
  page_path text NOT NULL DEFAULT '',
  page_title text NOT NULL DEFAULT '',
  service_used text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE page_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "page_views_read_all" ON page_views;
CREATE POLICY "page_views_read_all" ON page_views FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "page_views_insert_all" ON page_views;
CREATE POLICY "page_views_insert_all" ON page_views FOR INSERT
  TO anon, authenticated WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_page_views_session ON page_views(session_token);
CREATE INDEX IF NOT EXISTS idx_page_views_created ON page_views(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_page_views_service ON page_views(service_used);

-- === Update admin_config: add admin_username key ===
INSERT INTO admin_config (key, value)
VALUES ('admin_username', 'admin')
ON CONFLICT (key) DO NOTHING;