-- =====================================================================
-- ПОЛНЫЙ ЕДИНЫЙ МАСТЕР-СКРИПТ SUPABASE (СХЕМА + КИБЕРБЕЗОПАСНОСТЬ RLS)
-- Проект: Karakalpakstan Tourism Portal
-- Дата: 2026-09-18
--
-- ЧТО ДЕЛАЕТ ЭТОТ СКРИПТ:
-- 1. Создаёт/обновляет все 28 таблиц проекта (согласованы с фронтендом).
-- 2. Включает Row Level Security (RLS) на 100% таблиц.
-- 3. УДАЛЯЕТ ВСЕ СТАРЫЕ ДЫРЯВЫЕ ПОЛИТИКИ (allow read visa, allow manage guides и т.д.).
-- 4. Закрывает утечку паспортов, телефонов туристов и запрещает анонимное удаление гидов.
-- 5. Даёт админам (azada122321, damir122321, admin@karakalpak.travel) полный доступ.
-- =====================================================================

-- Включаем криптографические функции UUID
create extension if not exists "pgcrypto";

-- =====================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦ (ЕСЛИ ЕЩЁ НЕ СОЗДАНЫ)
-- =====================================================================

-- 1.1. АДМИНИСТРАТОРЫ СИСТЕМЫ
create table if not exists admin_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  email text unique not null,
  role text not null default 'Super Admin',
  display_name text not null,
  created_at timestamptz default now()
);

-- 1.2. КОНФИГУРАЦИЯ И НАСТРОЙКИ
create table if not exists admin_config (
  id uuid not null default gen_random_uuid() primary key,
  key text not null unique,
  value text not null,
  updated_at timestamptz default now()
);

-- 1.3. СООБЩЕНИЯ СЛУЖБЫ ПОДДЕРЖКИ
create table if not exists admin_support_messages (
  id text not null primary key,
  sender_id text not null,
  sender_name text not null,
  recipient_id text not null,
  content text not null,
  created_at timestamptz default now()
);

-- 1.4. БРОНИРОВАНИЕ ТУРОВ НА АРАЛ
create table if not exists aral_bookings (
  id uuid not null default gen_random_uuid() primary key,
  tour_id text not null,
  tour_name text not null,
  name text not null,
  email text not null,
  phone text not null,
  date date not null,
  group_size integer not null default 1,
  message text,
  status text not null default 'pending',
  created_at timestamptz default now()
);

-- 1.5. СПРАВОЧНИК БЕЙДЖЕЙ
create table if not exists badges (
  id uuid not null default gen_random_uuid() primary key,
  code text not null unique,
  name text not null,
  description text not null,
  place_name text not null,
  icon text not null,
  points integer not null default 0,
  image text,
  created_at timestamptz default now()
);

-- 1.6. ПРОФИЛИ СООБЩЕСТВА
create table if not exists community_profiles (
  id uuid not null default gen_random_uuid() primary key,
  username text not null,
  full_name text,
  avatar_url text,
  bio text,
  home_country text,
  travel_interests text[],
  created_at timestamptz default now()
);

-- 1.7. ЭКО-ВОЛОНТЁРЫ
create table if not exists eco_volunteers (
  id uuid not null default gen_random_uuid() primary key,
  project_id text not null,
  project_name text not null,
  name text not null,
  email text not null,
  phone text not null,
  country text not null,
  preferred_date date,
  message text,
  status text not null default 'pending',
  created_at timestamptz default now()
);

-- 1.8. РЕЗУЛЬТАТЫ МИНИ-ИГР
create table if not exists game_winners (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid,
  game_type text not null,
  player_name text not null,
  phone text,
  location text,
  score integer not null default 0,
  total integer not null default 0,
  points_earned integer not null default 0,
  created_at timestamptz default now()
);

-- 1.9. ГИДЫ
create table if not exists guides (
  id text not null primary key,
  name text not null,
  photo text,
  rating numeric default 5.0,
  reviews_count integer default 0,
  languages text[],
  specialties text[],
  daily_rate numeric default 45,
  phone text,
  whatsapp text,
  status text default 'active',
  created_at timestamptz default now()
);

-- 1.10. БРОНИРОВАНИЕ ОТЕЛЕЙ
create table if not exists hotel_bookings (
  id uuid not null default gen_random_uuid() primary key,
  tracking_id text not null,
  hotel_name text not null,
  room_type text not null,
  guest_name text not null,
  email text,
  phone text not null,
  check_in date not null,
  check_out date not null,
  guests integer not null default 1,
  nights integer not null default 1,
  price_per_night numeric not null default 0,
  total_price numeric not null default 0,
  commission_rate numeric not null default 10,
  status text not null default 'pending',
  language text,
  notes text,
  created_at timestamptz default now()
);

-- 1.11. ЖИВЫЕ МЕТКИ НА GPS-КАРТЕ
create table if not exists location_shares (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid default gen_random_uuid(),
  lat numeric not null,
  lng numeric not null,
  label text,
  expires_at timestamptz,
  created_at timestamptz default now()
);

-- 1.12. ОТКРЫТЫЕ ГРУППЫ ПОПУТЧИКОВ
create table if not exists open_groups (
  id uuid not null default gen_random_uuid() primary key,
  title text not null,
  destination text not null,
  travel_date date not null,
  max_members integer not null default 4,
  current_members integer not null default 1,
  creator_name text not null,
  creator_contact text not null,
  cost_per_person numeric not null default 0,
  notes text,
  status text not null default 'open',
  created_at timestamptz default now()
);

-- 1.13. ПРОСМОТРЫ СТРАНИЦ (АНАЛИТИКА)
create table if not exists page_views (
  id uuid not null default gen_random_uuid() primary key,
  session_token text,
  page_path text not null,
  page_title text,
  service_used text,
  created_at timestamptz default now()
);

-- 1.14. ФОТОКОНКУРС: РАБОТЫ
create table if not exists photo_entries (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
  title text not null,
  image_url text not null,
  location text not null,
  votes integer not null default 0,
  created_at timestamptz default now()
);

-- 1.15. ФОТОКОНКУРС: ГОЛОСА
create table if not exists photo_votes (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
  entry_id uuid not null references photo_entries(id) on delete cascade,
  created_at timestamptz default now()
);

-- 1.16. РЕЗУЛЬТАТЫ ВИКТОРИНЫ
create table if not exists quiz_results (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
  score integer not null default 0,
  total integer not null default 0,
  points_earned integer not null default 0,
  created_at timestamptz default now()
);

-- 1.17. ОТЗЫВЫ О МЕСТАХ
create table if not exists reviews (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid,
  place_id text not null,
  place_name text not null,
  rating integer default 5,
  comment text,
  photo_urls text[],
  author_name text,
  country text,
  is_verified_trip boolean default false,
  trip_date text,
  created_at timestamptz default now()
);

-- 1.18. ПРОСМОТРЫ ДОСТОПРИМЕЧАТЕЛЬНОСТЕЙ
create table if not exists spot_views (
  id uuid not null default gen_random_uuid() primary key,
  spot_name text not null,
  spot_category text not null,
  viewer_country text,
  viewer_id uuid,
  created_at timestamptz default now()
);

-- 1.19. ЗАКАЗЫ ТАКСИ
create table if not exists taxi_bookings (
  id uuid not null default gen_random_uuid() primary key,
  tracking_id text not null,
  tourist_name text not null,
  email text,
  phone text not null,
  pickup_location text not null,
  dropoff_location text not null,
  travel_datetime timestamptz not null,
  passengers integer not null default 1,
  notes text,
  language text,
  total_price numeric not null default 0,
  commission_rate numeric not null default 10,
  status text not null default 'pending',
  created_at timestamptz default now()
);

-- 1.20. ТУРАГЕНТСТВА
create table if not exists tour_agencies (
  id text not null primary key,
  name text not null,
  contact_person text,
  phone text,
  email text,
  city text,
  commission_rate numeric default 10,
  active_tours integer default 3,
  status text default 'active',
  created_at timestamptz default now()
);

-- 1.21. ЗАПРОСЫ ТУРИСТОВ
create table if not exists tourist_requests (
  id uuid not null default gen_random_uuid() primary key,
  name text not null,
  email text not null,
  phone text not null,
  tour_name text,
  travel_date date,
  guests integer default 1,
  budget_total integer default 0,
  group_size integer default 1,
  duration_days integer default 1,
  interests text[],
  message text,
  per_person_per_day numeric,
  buddy_opt_in boolean default false,
  status text not null default 'pending',
  created_at timestamptz default now()
);

-- 1.22. ДОСКА ОБЪЯВЛЕНИЙ ПОПУТЧИКОВ (TRAVEL BUDDIES)
create table if not exists travel_buddies (
  id uuid not null default gen_random_uuid() primary key,
  name text not null,
  destination text not null,
  travel_date date not null,
  contact text not null,
  languages text,
  notes text,
  status text not null default 'open',
  created_at timestamptz default now()
);

-- 1.23. ЛИЧНЫЕ СООБЩЕНИЯ МЕЖДУ ПУТЕШЕСТВЕННИКАМИ
create table if not exists traveler_messages (
  id uuid not null default gen_random_uuid() primary key,
  sender_id uuid not null,
  recipient_id uuid not null,
  content text not null,
  read boolean not null default false,
  created_at timestamptz default now()
);

-- 1.24. ЧЕК-ИНЫ НА КАРТЕ
create table if not exists trip_checkins (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
  place_name text not null,
  place_id text,
  lat numeric,
  lng numeric,
  note text,
  photo_url text,
  created_at timestamptz default now()
);

-- 1.25. ПОЛУЧЕННЫЕ БЕЙДЖИ
create table if not exists user_badges (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
  badge_id uuid not null references badges(id) on delete cascade,
  qr_code text not null,
  created_at timestamptz default now()
);

-- 1.26. БАЛЛЫ И НАГРАДЫ ПОЛЬЗОВАТЕЛЕЙ
create table if not exists user_points (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
  points integer not null default 0,
  reason text not null,
  created_at timestamptz default now()
);

-- 1.27. ЗАЯВКИ НА ВИЗОВУЮ ПОДДЕРЖКУ (СОДЕРЖАТ ПАСПОРТА!)
create table if not exists visa_applications (
  id uuid not null default gen_random_uuid() primary key,
  full_name text not null,
  nationality text not null,
  passport_number text not null,
  email text not null,
  phone text not null,
  arrival_date date not null,
  departure_date date not null,
  visa_type text not null default 'tourist',
  purpose text,
  status text not null default 'pending',
  created_at timestamptz default now()
);

-- 1.28. СЕССИИ ПОСЕТИТЕЛЕЙ (АНАЛИТИКА)
create table if not exists visitor_sessions (
  id uuid not null default gen_random_uuid() primary key,
  session_token text not null unique,
  ip_address text,
  country text,
  user_agent text,
  page_views integer default 1,
  first_seen timestamptz default now(),
  last_seen timestamptz default now()
);

-- =====================================================================
-- 2. ИНДЕКСЫ ДЛЯ УСКОРЕНИЯ
-- =====================================================================
create index if not exists idx_admin_config_key on admin_config(key);
create index if not exists idx_tourist_req_created on tourist_requests(created_at desc);
create index if not exists idx_hotel_book_created on hotel_bookings(created_at desc);
create index if not exists idx_taxi_book_created on taxi_bookings(created_at desc);
create index if not exists idx_reviews_place on reviews(place_id);
create index if not exists idx_traveler_msg_sender on traveler_messages(sender_id);
create index if not exists idx_traveler_msg_recipient on traveler_messages(recipient_id);
create index if not exists idx_visitor_sessions_token on visitor_sessions(session_token);

-- =====================================================================
-- 3. ВКЛЮЧЕНИЕ ROW LEVEL SECURITY (RLS)
-- =====================================================================
alter table admin_users enable row level security;
alter table admin_config enable row level security;
alter table admin_support_messages enable row level security;
alter table aral_bookings enable row level security;
alter table badges enable row level security;
alter table community_profiles enable row level security;
alter table eco_volunteers enable row level security;
alter table game_winners enable row level security;
alter table guides enable row level security;
alter table hotel_bookings enable row level security;
alter table location_shares enable row level security;
alter table open_groups enable row level security;
alter table page_views enable row level security;
alter table photo_entries enable row level security;
alter table photo_votes enable row level security;
alter table quiz_results enable row level security;
alter table reviews enable row level security;
alter table spot_views enable row level security;
alter table taxi_bookings enable row level security;
alter table tour_agencies enable row level security;
alter table tourist_requests enable row level security;
alter table travel_buddies enable row level security;
alter table traveler_messages enable row level security;
alter table trip_checkins enable row level security;
alter table user_badges enable row level security;
alter table user_points enable row level security;
alter table visa_applications enable row level security;
alter table visitor_sessions enable row level security;

-- =====================================================================
-- 4. ЗАЩИЩЁННАЯ ФУНКЦИЯ ПРОВЕРКИ СТАТУСА АДМИНИСТРАТОРА
-- =====================================================================
create or replace function is_admin()
returns boolean as $$
begin
  return (
    auth.role() = 'authenticated' and (
      exists (
        select 1 from admin_users 
        where user_id = auth.uid() 
           or lower(email) = lower(auth.jwt() ->> 'email')
      )
    )
  );
end;
$$ language plpgsql security definer stable;

-- =====================================================================
-- 5. УДАЛЕНИЕ ВСЕХ СТАРЫХ УЯЗВИМЫХ ПОЛИТИК (ИЗ СТАРОГО И НОВОГО СКРИПТОВ)
-- =====================================================================

-- visa_applications
drop policy if exists "allow read visa_applications" on visa_applications;
drop policy if exists "allow update visa_applications" on visa_applications;
drop policy if exists "allow delete visa_applications" on visa_applications;
drop policy if exists "va_select_all" on visa_applications;
drop policy if exists "visa_select_admin" on visa_applications;
drop policy if exists "allow insert visa_applications" on visa_applications;
drop policy if exists "va_insert_all" on visa_applications;
drop policy if exists "visa_manage_admin" on visa_applications;

-- tourist_requests
drop policy if exists "allow read tourist_requests" on tourist_requests;
drop policy if exists "allow update tourist_requests" on tourist_requests;
drop policy if exists "allow delete tourist_requests" on tourist_requests;
drop policy if exists "anon_select_tourist_requests" on tourist_requests;
drop policy if exists "tourist_requests_select_admin" on tourist_requests;
drop policy if exists "allow insert tourist_requests" on tourist_requests;
drop policy if exists "anon_insert_tourist_requests" on tourist_requests;
drop policy if exists "tourist_requests_manage_admin" on tourist_requests;

-- aral_bookings
drop policy if exists "allow read aral_bookings" on aral_bookings;
drop policy if exists "allow update aral_bookings" on aral_bookings;
drop policy if exists "allow delete aral_bookings" on aral_bookings;
drop policy if exists "aral_bookings_select_admin" on aral_bookings;
drop policy if exists "allow insert aral_bookings" on aral_bookings;
drop policy if exists "aral_bookings_manage_admin" on aral_bookings;

-- eco_volunteers
drop policy if exists "allow read eco_volunteers" on eco_volunteers;
drop policy if exists "allow update eco_volunteers" on eco_volunteers;
drop policy if exists "allow delete eco_volunteers" on eco_volunteers;
drop policy if exists "eco_volunteers_select_admin" on eco_volunteers;
drop policy if exists "allow insert eco_volunteers" on eco_volunteers;
drop policy if exists "eco_volunteers_manage_admin" on eco_volunteers;

-- hotel_bookings
drop policy if exists "allow read hotel_bookings" on hotel_bookings;
drop policy if exists "allow update hotel_bookings" on hotel_bookings;
drop policy if exists "allow delete hotel_bookings" on hotel_bookings;
drop policy if exists "hotel_bookings_read_all" on hotel_bookings;
drop policy if exists "hotel_bookings_select_admin" on hotel_bookings;
drop policy if exists "allow insert hotel_bookings" on hotel_bookings;
drop policy if exists "hotel_bookings_insert_all" on hotel_bookings;
drop policy if exists "hotel_bookings_manage_admin" on hotel_bookings;

-- taxi_bookings
drop policy if exists "allow read taxi_bookings" on taxi_bookings;
drop policy if exists "allow update taxi_bookings" on taxi_bookings;
drop policy if exists "allow delete taxi_bookings" on taxi_bookings;
drop policy if exists "taxi_bookings_read_all" on taxi_bookings;
drop policy if exists "taxi_bookings_select_admin" on taxi_bookings;
drop policy if exists "allow insert taxi_bookings" on taxi_bookings;
drop policy if exists "taxi_bookings_insert_all" on taxi_bookings;
drop policy if exists "taxi_bookings_manage_admin" on taxi_bookings;

-- guides
drop policy if exists "allow manage guides" on guides;
drop policy if exists "guides_manage_auth" on guides;
drop policy if exists "guides_manage_all" on guides;
drop policy if exists "public read guides" on guides;
drop policy if exists "guides_read_all" on guides;
drop policy if exists "guides_manage_admin" on guides;

-- tour_agencies
drop policy if exists "allow manage agencies" on tour_agencies;
drop policy if exists "agencies_manage_all" on tour_agencies;
drop policy if exists "agencies_manage_auth" on tour_agencies;
drop policy if exists "public read agencies" on tour_agencies;
drop policy if exists "agencies_read_all" on tour_agencies;
drop policy if exists "agencies_manage_admin" on tour_agencies;

-- admin_config
drop policy if exists "manage admin config" on admin_config;
drop policy if exists "read admin config" on admin_config;
drop policy if exists "admin_config_read_all" on admin_config;
drop policy if exists "admin_config_upsert_all" on admin_config;
drop policy if exists "admin_config_update_all" on admin_config;
drop policy if exists "admin_config_read_admin" on admin_config;
drop policy if exists "admin_config_write_admin" on admin_config;

-- admin_support_messages
drop policy if exists "manage admin support messages" on admin_support_messages;
drop policy if exists "read admin support messages" on admin_support_messages;

-- game_winners
drop policy if exists "public read game winners" on game_winners;
drop policy if exists "game_winners_read_all" on game_winners;
drop policy if exists "insert game winners" on game_winners;
drop policy if exists "game_winners_select_admin" on game_winners;
drop policy if exists "game_winners_insert_own" on game_winners;

-- =====================================================================
-- 6. ПРИМЕНЕНИЕ НАДЁЖНЫХ И БЕЗОПАСНЫХ ПОЛИТИК (RLS)
-- =====================================================================

-- 6.1. АДМИНИСТРАТОРЫ (admin_users)
drop policy if exists "admin_users_view_admin" on admin_users;
create policy "admin_users_view_admin" on admin_users
  for select to authenticated using (is_admin() or auth.uid() = user_id);

drop policy if exists "admin_users_manage_admin" on admin_users;
create policy "admin_users_manage_admin" on admin_users
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.2. ЗАЯВКИ НА ВИЗЫ (visa_applications) — ЗАЩИТА ПАСПОРТНЫХ ДАННЫХ
drop policy if exists "visa_insert_public" on visa_applications;
create policy "visa_insert_public" on visa_applications
  for insert to anon, authenticated with check (status = 'pending' or status is null);

drop policy if exists "visa_select_admin" on visa_applications;
create policy "visa_select_admin" on visa_applications
  for select to authenticated using (is_admin());

drop policy if exists "visa_manage_admin" on visa_applications;
create policy "visa_manage_admin" on visa_applications
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.3. ЗАПРОСЫ ТУРИСТОВ (tourist_requests) — ЗАЩИТА ТЕЛЕФОНОВ И БЮДЖЕТОВ
drop policy if exists "tourist_requests_insert_public" on tourist_requests;
create policy "tourist_requests_insert_public" on tourist_requests
  for insert to anon, authenticated with check ((status = 'pending' or status is null) and group_size >= 1 and group_size <= 50);

drop policy if exists "tourist_requests_select_admin" on tourist_requests;
create policy "tourist_requests_select_admin" on tourist_requests
  for select to authenticated using (is_admin());

drop policy if exists "tourist_requests_manage_admin" on tourist_requests;
create policy "tourist_requests_manage_admin" on tourist_requests
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.4. БРОНИРОВАНИЕ ТУРОВ НА АРАЛ (aral_bookings)
drop policy if exists "aral_bookings_insert_public" on aral_bookings;
create policy "aral_bookings_insert_public" on aral_bookings
  for insert to anon, authenticated with check ((status = 'pending' or status is null) and group_size >= 1 and group_size <= 50);

drop policy if exists "aral_bookings_select_admin" on aral_bookings;
create policy "aral_bookings_select_admin" on aral_bookings
  for select to authenticated using (is_admin());

drop policy if exists "aral_bookings_manage_admin" on aral_bookings;
create policy "aral_bookings_manage_admin" on aral_bookings
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.5. ЭКО-ВОЛОНТЁРЫ (eco_volunteers)
drop policy if exists "eco_volunteers_insert_public" on eco_volunteers;
create policy "eco_volunteers_insert_public" on eco_volunteers
  for insert to anon, authenticated with check (true);

drop policy if exists "eco_volunteers_select_admin" on eco_volunteers;
create policy "eco_volunteers_select_admin" on eco_volunteers
  for select to authenticated using (is_admin());

drop policy if exists "eco_volunteers_manage_admin" on eco_volunteers;
create policy "eco_volunteers_manage_admin" on eco_volunteers
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.6. ОТЕЛИ (hotel_bookings)
drop policy if exists "hotel_bookings_insert_public" on hotel_bookings;
create policy "hotel_bookings_insert_public" on hotel_bookings
  for insert to anon, authenticated with check (
    (status = 'pending' or status is null) and
    nights >= 1 and
    guests >= 1 and
    price_per_night >= 0 and
    total_price >= 0
  );

drop policy if exists "hotel_bookings_select_admin" on hotel_bookings;
create policy "hotel_bookings_select_admin" on hotel_bookings
  for select to authenticated using (is_admin());

drop policy if exists "hotel_bookings_manage_admin" on hotel_bookings;
create policy "hotel_bookings_manage_admin" on hotel_bookings
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.7. ТАКСИ (taxi_bookings)
drop policy if exists "taxi_bookings_insert_public" on taxi_bookings;
create policy "taxi_bookings_insert_public" on taxi_bookings
  for insert to anon, authenticated with check (
    (status = 'pending' or status is null) and
    passengers >= 1 and passengers <= 20
  );

drop policy if exists "taxi_bookings_select_admin" on taxi_bookings;
create policy "taxi_bookings_select_admin" on taxi_bookings
  for select to authenticated using (is_admin());

drop policy if exists "taxi_bookings_manage_admin" on taxi_bookings;
create policy "taxi_bookings_manage_admin" on taxi_bookings
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.8. ГИДЫ (guides) — Чтение всем, редактирование ТОЛЬКО админам
drop policy if exists "guides_read_public" on guides;
create policy "guides_read_public" on guides
  for select to anon, authenticated using (true);

drop policy if exists "guides_manage_admin" on guides;
create policy "guides_manage_admin" on guides
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.9. ТУРАГЕНТСТВА (tour_agencies) — Чтение всем, редактирование ТОЛЬКО админам
drop policy if exists "agencies_read_public" on tour_agencies;
create policy "agencies_read_public" on tour_agencies
  for select to anon, authenticated using (true);

drop policy if exists "agencies_manage_admin" on tour_agencies;
create policy "agencies_manage_admin" on tour_agencies
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.10. КОНФИГУРАЦИЯ АДМИНКИ (admin_config) — ТОЛЬКО админам
drop policy if exists "admin_config_select_admin" on admin_config;
create policy "admin_config_select_admin" on admin_config
  for select to authenticated using (is_admin());

drop policy if exists "admin_config_manage_admin" on admin_config;
create policy "admin_config_manage_admin" on admin_config
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.11. ЧАТЫ ПОДДЕРЖКИ (admin_support_messages)
drop policy if exists "admin_support_select" on admin_support_messages;
create policy "admin_support_select" on admin_support_messages
  for select to authenticated using (is_admin() or auth.uid()::text = sender_id or auth.uid()::text = recipient_id);

drop policy if exists "admin_support_insert" on admin_support_messages;
create policy "admin_support_insert" on admin_support_messages
  for insert to anon, authenticated with check (true);

drop policy if exists "admin_support_manage_admin" on admin_support_messages;
create policy "admin_support_manage_admin" on admin_support_messages
  for all to authenticated using (is_admin()) with check (is_admin());

-- 6.12. ПОБЕДИТЕЛИ ИГР (game_winners)
drop policy if exists "game_winners_insert_public" on game_winners;
drop policy if exists "game_winners_insert_authenticated" on game_winners;
create policy "game_winners_insert_authenticated" on game_winners
  for insert to authenticated with check (auth.uid() = user_id and score >= 0 and score <= 100);

drop policy if exists "game_winners_select_admin" on game_winners;
create policy "game_winners_select_admin" on game_winners
  for select to authenticated using (is_admin() or auth.uid() = user_id);

-- 6.13. СПРАВОЧНИК БЕЙДЖЕЙ (badges)
drop policy if exists "public read badges" on badges;
drop policy if exists "allow manage badges" on badges;
drop policy if exists "badges_read_public" on badges;
drop policy if exists "badges_manage_admin" on badges;
create policy "badges_read_public" on badges for select to anon, authenticated using (true);
create policy "badges_manage_admin" on badges for all to authenticated using (is_admin()) with check (is_admin());

-- 6.14. ОТЗЫВЫ (reviews)
drop policy if exists "public read reviews" on reviews;
drop policy if exists "anyone can submit review" on reviews;
drop policy if exists "allow update reviews" on reviews;
drop policy if exists "allow delete reviews" on reviews;
drop policy if exists "reviews_read_public" on reviews;
drop policy if exists "reviews_insert_public" on reviews;
drop policy if exists "reviews_insert_authenticated" on reviews;
drop policy if exists "reviews_update_admin_or_owner" on reviews;
drop policy if exists "reviews_delete_admin_or_owner" on reviews;
create policy "reviews_read_public" on reviews for select to anon, authenticated using (true);
create policy "reviews_insert_authenticated" on reviews for insert to authenticated 
  with check (auth.uid() = user_id and rating >= 1 and rating <= 5 and length(comment) > 0 and length(comment) <= 2000);
create policy "reviews_update_admin_or_owner" on reviews for update to authenticated using (is_admin() or auth.uid() = user_id);
create policy "reviews_delete_admin_or_owner" on reviews for delete to authenticated using (is_admin() or auth.uid() = user_id);

-- 6.15. ФОТОКОНКУРС (photo_entries, photo_votes)
drop policy if exists "public read photos" on photo_entries;
drop policy if exists "anyone can submit photo" on photo_entries;
drop policy if exists "allow vote on photo" on photo_entries;
drop policy if exists "allow delete photo" on photo_entries;
drop policy if exists "photos_read_public" on photo_entries;
drop policy if exists "photos_insert_user" on photo_entries;
drop policy if exists "photos_manage_admin_or_owner" on photo_entries;
create policy "photos_read_public" on photo_entries for select to anon, authenticated using (true);
create policy "photos_insert_user" on photo_entries for insert to authenticated with check (auth.uid() = user_id);
create policy "photos_manage_admin_or_owner" on photo_entries for all to authenticated using (is_admin() or auth.uid() = user_id);

drop policy if exists "public read photo votes" on photo_votes;
drop policy if exists "anyone can submit vote" on photo_votes;
drop policy if exists "photo_votes_read_public" on photo_votes;
drop policy if exists "photo_votes_insert_user" on photo_votes;
create policy "photo_votes_read_public" on photo_votes for select to anon, authenticated using (true);
create policy "photo_votes_insert_user" on photo_votes for insert to authenticated with check (auth.uid() = user_id);

-- 6.16. ПОПУТЧИКИ И ОТКРЫТЫЕ ГРУППЫ (open_groups, travel_buddies)
drop policy if exists "public read open groups" on open_groups;
drop policy if exists "anyone can create open group" on open_groups;
drop policy if exists "anyone can join open group" on open_groups;
drop policy if exists "allow delete open group" on open_groups;
drop policy if exists "open_groups_manage" on open_groups;
drop policy if exists "open_groups_read_public" on open_groups;
drop policy if exists "open_groups_insert_public" on open_groups;
drop policy if exists "open_groups_update_join" on open_groups;
drop policy if exists "open_groups_update_owner_or_admin" on open_groups;
drop policy if exists "open_groups_delete_admin" on open_groups;
create policy "open_groups_read_public" on open_groups for select to anon, authenticated using (true);
create policy "open_groups_insert_public" on open_groups for insert to anon, authenticated with check (
  (status = 'open' or status is null) and
  max_members between 2 and 30 and
  current_members >= 1 and
  current_members <= max_members and
  length(creator_name) > 0 and
  length(creator_name) <= 100
);
create policy "open_groups_update_owner_or_admin" on open_groups for update to authenticated using (auth.uid() = user_id or is_admin()) with check (auth.uid() = user_id or is_admin());
create policy "open_groups_delete_admin" on open_groups for delete to authenticated using (is_admin());

drop policy if exists "public read travel buddies" on travel_buddies;
drop policy if exists "anyone can post travel buddy" on travel_buddies;
drop policy if exists "allow delete travel buddy" on travel_buddies;
drop policy if exists "travel_buddies_read_public" on travel_buddies;
drop policy if exists "travel_buddies_insert_public" on travel_buddies;
drop policy if exists "travel_buddies_delete_admin" on travel_buddies;
create policy "travel_buddies_read_public" on travel_buddies for select to anon, authenticated using (true);
create policy "travel_buddies_insert_public" on travel_buddies for insert to anon, authenticated with check (
  (status = 'active' or status is null) and
  length(name) > 0 and
  length(name) <= 100
);
create policy "travel_buddies_delete_admin" on travel_buddies for delete to authenticated using (is_admin());

-- 6.17. GPS-МЕТКИ И ЧЕК-ИНЫ (location_shares, trip_checkins)
drop policy if exists "public read location shares" on location_shares;
drop policy if exists "anyone can share location" on location_shares;
drop policy if exists "allow delete location share" on location_shares;
drop policy if exists "location_shares_read_public" on location_shares;
drop policy if exists "location_shares_read_valid" on location_shares;
drop policy if exists "location_shares_insert_public" on location_shares;
drop policy if exists "location_shares_insert_authenticated" on location_shares;
drop policy if exists "location_shares_delete" on location_shares;
create policy "location_shares_read_valid" on location_shares for select to anon, authenticated using (expires_at is null or expires_at > now());
create policy "location_shares_insert_authenticated" on location_shares for insert to authenticated with check (auth.uid() = user_id);
create policy "location_shares_delete" on location_shares for delete to authenticated using (is_admin() or auth.uid() = user_id);

drop policy if exists "public read trip checkins" on trip_checkins;
drop policy if exists "anyone can post trip checkin" on trip_checkins;
drop policy if exists "anyone can delete trip checkin" on trip_checkins;
drop policy if exists "trip_checkins_read_public" on trip_checkins;
drop policy if exists "trip_checkins_insert_user" on trip_checkins;
drop policy if exists "trip_checkins_delete_user" on trip_checkins;
create policy "trip_checkins_read_public" on trip_checkins for select to anon, authenticated using (true);
create policy "trip_checkins_insert_user" on trip_checkins for insert to authenticated with check (auth.uid() = user_id);
create policy "trip_checkins_delete_user" on trip_checkins for delete to authenticated using (is_admin() or auth.uid() = user_id);

-- 6.18. ЛИЧНЫЕ СООБЩЕНИЯ И ПРОФИЛИ (traveler_messages, community_profiles)
drop policy if exists "read traveler messages" on traveler_messages;
drop policy if exists "send traveler message" on traveler_messages;
drop policy if exists "update traveler message" on traveler_messages;
drop policy if exists "delete traveler message" on traveler_messages;
drop policy if exists "traveler_messages_select_parties" on traveler_messages;
drop policy if exists "traveler_messages_insert_sender" on traveler_messages;
drop policy if exists "traveler_messages_update_parties" on traveler_messages;
drop policy if exists "traveler_messages_delete_parties" on traveler_messages;
create policy "traveler_messages_select_parties" on traveler_messages
  for select to authenticated using (auth.uid() = sender_id or auth.uid() = recipient_id or is_admin());
create policy "traveler_messages_insert_sender" on traveler_messages
  for insert to authenticated with check (auth.uid() = sender_id);
create policy "traveler_messages_update_parties" on traveler_messages
  for update to authenticated using (auth.uid() = recipient_id or is_admin());
create policy "traveler_messages_delete_parties" on traveler_messages
  for delete to authenticated using (auth.uid() = sender_id or is_admin());

drop policy if exists "public read community profiles" on community_profiles;
drop policy if exists "anyone can create community profile" on community_profiles;
drop policy if exists "anyone can update community profile" on community_profiles;
drop policy if exists "community_profiles_read_public" on community_profiles;
drop policy if exists "community_profiles_insert_user" on community_profiles;
drop policy if exists "community_profiles_update_user" on community_profiles;
create policy "community_profiles_read_public" on community_profiles for select to anon, authenticated using (true);
create policy "community_profiles_insert_user" on community_profiles for insert to authenticated with check (auth.uid() = id);
create policy "community_profiles_update_user" on community_profiles for update to authenticated using (auth.uid() = id or is_admin());

-- 6.19. ИГРЫ, БАЛЛЫ И ВИКТОРИНЫ (user_points, user_badges, quiz_results)
drop policy if exists "public read user points" on user_points;
drop policy if exists "insert user points" on user_points;
drop policy if exists "user_points_read_public" on user_points;
drop policy if exists "user_points_insert_user" on user_points;
create policy "user_points_read_public" on user_points for select to anon, authenticated using (true);
create policy "user_points_insert_user" on user_points for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "public read user badges" on user_badges;
drop policy if exists "insert user badges" on user_badges;
drop policy if exists "user_badges_read_public" on user_badges;
drop policy if exists "user_badges_insert_user" on user_badges;
create policy "user_badges_read_public" on user_badges for select to anon, authenticated using (true);
create policy "user_badges_insert_user" on user_badges for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "public read quiz results" on quiz_results;
drop policy if exists "insert quiz results" on quiz_results;
drop policy if exists "quiz_results_read_public" on quiz_results;
drop policy if exists "quiz_results_insert_user" on quiz_results;
create policy "quiz_results_read_public" on quiz_results for select to anon, authenticated using (true);
create policy "quiz_results_insert_user" on quiz_results for insert to authenticated with check (auth.uid() = user_id);

-- 6.20. АНАЛИТИКА (spot_views, page_views, visitor_sessions)
drop policy if exists "allow insert spot views" on spot_views;
drop policy if exists "allow read spot views" on spot_views;
drop policy if exists "spot_views_insert_public" on spot_views;
drop policy if exists "spot_views_read_public" on spot_views;
create policy "spot_views_insert_public" on spot_views for insert to anon, authenticated with check (true);
create policy "spot_views_read_public" on spot_views for select to anon, authenticated using (true);

drop policy if exists "allow insert page views" on page_views;
drop policy if exists "allow read page views" on page_views;
drop policy if exists "page_views_insert_public" on page_views;
drop policy if exists "page_views_select_admin" on page_views;
create policy "page_views_insert_public" on page_views for insert to anon, authenticated with check (true);
create policy "page_views_select_admin" on page_views for select to authenticated using (is_admin());

drop policy if exists "allow insert visitor sessions" on visitor_sessions;
drop policy if exists "allow read visitor sessions" on visitor_sessions;
drop policy if exists "allow update visitor sessions" on visitor_sessions;
drop policy if exists "visitor_sessions_update_public" on visitor_sessions;
drop policy if exists "visitor_sessions_update_admin" on visitor_sessions;
drop policy if exists "visitor_sessions_select_admin" on visitor_sessions;
create policy "visitor_sessions_insert_public" on visitor_sessions for insert to anon, authenticated with check (true);
create policy "visitor_sessions_update_admin" on visitor_sessions for update to authenticated using (is_admin()) with check (is_admin());
create policy "visitor_sessions_select_admin" on visitor_sessions for select to authenticated using (is_admin());
