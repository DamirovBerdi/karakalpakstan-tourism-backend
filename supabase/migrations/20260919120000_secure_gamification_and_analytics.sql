-- =====================================================================
-- МИГРАЦИЯ УСТРАНЕНИЯ УЯЗВИМОСТЕЙ ГЕЙМИФИКАЦИИ И АНАЛИТИКИ
-- Проект: Karakalpakstan Tourism Portal
-- 1. Запрет прямой вставки в user_points и user_badges со стороны клиента
-- 2. Атомарный server-side RPC claim_qr_badge с проверкой QR и защитой от повтора
-- 3. Server-side RPC submit_quiz_result с авторитарным расчетом баллов
-- 4. Триггеры автоматического начисления баллов за фотоконкурс и голосование
-- 5. Запрет прямой анонимной вставки в visitor_sessions (только через Edge Function)
-- =====================================================================

-- 1. СЕМЕНА БЕЙДЖЕЙ (если отсутствуют)
insert into public.badges (code, name, description, place_name, icon, points, image) values
  ('KTK-SAVITSKY-2026', 'Art Pioneer', 'Visited the Savitsky Museum — the Louvre of the Desert', 'Savitsky Museum, Nukus', 'Palette', 100, ''),
  ('KTK-MOYNAQ-2026', 'Ship Graveyard Explorer', 'Stood among the rusted ships at the Aral Sea graveyard', 'Moynaq Ship Graveyard', 'Ship', 100, ''),
  ('KTK-MIZDAKHAN-2026', 'Ancient Pilgrim', 'Explored the 2000-year-old Mizdakhan Necropolis', 'Mizdakhan Necropolis', 'Landmark', 100, ''),
  ('KTK-CHILPYK-2026', 'Tower of Silence', 'Climbed the Zoroastrian dakhma at Chilpyk', 'Chilpyk Fortress', 'Mountain', 100, ''),
  ('KTK-USTYURT-2026', 'Plateau Conqueror', 'Reached the Ustyurt Plateau chalk cliffs', 'Ustyurt Plateau', 'Compass', 150, ''),
  ('KTK-SUDOCHYE-2026', 'Wetland Wanderer', 'Discovered the bird-filled Sudochye Lake', 'Lake Sudochye', 'Bird', 80, ''),
  ('KTK-NUKUS-BAZAAR-2026', 'Bazaar Shopper', 'Experienced the vibrant Nukus Bazaar', 'Nukus Bazaar', 'ShoppingBag', 50, ''),
  ('KTK-BERDAQ-2026', 'Poetry Lover', 'Visited the Berdaq Poetry Museum', 'Berdaq Museum, Nukus', 'BookOpen', 80, '')
on conflict (code) do nothing;

-- 2. УНИКАЛЬНЫЕ ИНДЕКСЫ ДЛЯ ЗАЩИТЫ ОТ REPLAY-АТАК
create unique index if not exists idx_user_badges_user_badge on public.user_badges(user_id, badge_id);
create unique index if not exists idx_photo_votes_unique on public.photo_votes(user_id, entry_id);

-- 3. ЗАПРЕТ ПРЯМОЙ ВСТАВКИ В user_points И user_badges
drop policy if exists "insert user points" on public.user_points;
drop policy if exists "user_points_insert_user" on public.user_points;
drop policy if exists "user_points_insert_own" on public.user_points;

drop policy if exists "insert user badges" on public.user_badges;
drop policy if exists "user_badges_insert_user" on public.user_badges;
drop policy if exists "user_badges_insert_own" on public.user_badges;

-- Чтение баллов и бейджей остается публичным для таблицы лидеров
drop policy if exists "user_points_read_public" on public.user_points;
create policy "user_points_read_public" on public.user_points for select to anon, authenticated using (true);

drop policy if exists "user_badges_read_public" on public.user_badges;
create policy "user_badges_read_public" on public.user_badges for select to anon, authenticated using (true);

-- 4. СЕРВЕРНЫЙ RPC ДЛЯ ПОЛУЧЕНИЯ БЕЙДЖА ПО QR-КОДУ (CLAIM_QR_BADGE)
create or replace function public.claim_qr_badge(p_qr_code text)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_badge record;
  v_badge_id uuid;
  v_points int;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Unauthorized: must be logged in to claim badges';
  end if;

  if p_qr_code is null or length(trim(p_qr_code)) = 0 then
    raise exception 'Invalid QR code provided';
  end if;

  select * into v_badge
  from public.badges
  where upper(trim(code)) = upper(trim(p_qr_code))
  limit 1;

  if not found then
    raise exception 'Badge not found for code: %', p_qr_code;
  end if;

  -- Проверка на повторное получение
  if exists (
    select 1 from public.user_badges
    where user_id = v_user_id and badge_id = v_badge.id
  ) then
    raise exception 'Badge already earned: %', v_badge.name;
  end if;

  -- Атомарная выдача бейджа
  insert into public.user_badges (user_id, badge_id, qr_code)
  values (v_user_id, v_badge.id, upper(trim(p_qr_code)))
  returning id into v_badge_id;

  -- Атомарное начисление баллов (строго из таблицы badges)
  v_points := coalesce(v_badge.points, 50);
  insert into public.user_points (user_id, points, reason)
  values (v_user_id, v_points, 'qr_checkin');

  return json_build_object(
    'success', true,
    'badge_id', v_badge.id,
    'badge_name', v_badge.name,
    'points', v_points
  );
end;
$$;

-- 5. СЕРВЕРНЫЙ RPC ДЛЯ ЗАВЕРШЕНИЯ ВИКТОРИНЫ (SUBMIT_QUIZ_RESULT)
create or replace function public.submit_quiz_result(p_score integer, p_total integer)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_points integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Unauthorized: must be logged in';
  end if;

  if p_score < 0 or p_total <= 0 or p_score > p_total or p_total > 20 then
    raise exception 'Invalid score or total parameters';
  end if;

  -- Баллы рассчитываются сервером (15 баллов за верный ответ, максимум 300)
  v_points := least(p_score * 15, 300);

  -- Запись результата викторины
  insert into public.quiz_results (user_id, score, total, points_earned)
  values (v_user_id, p_score, p_total, v_points);

  -- Начисление баллов
  if v_points > 0 then
    insert into public.user_points (user_id, points, reason)
    values (v_user_id, v_points, 'quiz_win');
  end if;

  return json_build_object(
    'success', true,
    'score', p_score,
    'total', p_total,
    'points_earned', v_points
  );
end;
$$;

-- 6. ТРИГГЕРЫ НАЧИСЛЕНИЯ БАЛЛОВ ЗА ФОТОКОНКУРС
create or replace function public.trg_award_photo_entry()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.user_points (user_id, points, reason)
  values (new.user_id, 10, 'contest_entry');
  return new;
end;
$$;

drop trigger if exists trg_award_photo_entry_points on public.photo_entries;
create trigger trg_award_photo_entry_points
  after insert on public.photo_entries
  for each row execute function public.trg_award_photo_entry();

create or replace function public.trg_award_photo_vote()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.user_points (user_id, points, reason)
  values (new.user_id, 2, 'contest_vote');
  return new;
end;
$$;

drop trigger if exists trg_award_photo_vote_points on public.photo_votes;
create trigger trg_award_photo_vote_points
  after insert on public.photo_votes
  for each row execute function public.trg_award_photo_vote();

-- 7. ЗАПРЕТ ПРЯМОЙ ВСТАВКИ В visitor_sessions (АНАЛИТИКА ТОЛЬКО ЧЕРЕЗ EDGE FUNCTION)
drop policy if exists "visitor_sessions_insert_public" on public.visitor_sessions;
