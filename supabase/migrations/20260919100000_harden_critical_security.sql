-- =====================================================================
-- МИГРАЦИЯ УСТРАНЕНИЯ ТОП-10 КРИТИЧЕСКИХ УЯЗВИМОСТЕЙ БЕЗОПАСНОСТИ
-- Проект: Karakalpakstan Tourism Portal
-- =====================================================================

-- 1. УСТРАНЕНИЕ БЭКДОРА @karakalpak.travel В ФУНКЦИИ is_admin()
-- Только пользователи, явно зарегистрированные в таблице admin_users, являются администраторами
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

-- 2. ТРИГГЕР ДЛЯ АВТО-СВЯЗЫВАНИЯ user_id В admin_users ПРИ РЕГИСТРАЦИИ АДМИНИСТРАТОРА
create or replace function sync_admin_user_id()
returns trigger as $$
begin
  update admin_users 
  set user_id = new.id 
  where lower(email) = lower(new.email);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created_admin on auth.users;
create trigger on_auth_user_created_admin
  after insert on auth.users
  for each row execute function sync_admin_user_id();

-- 3. ПРЕДВАРИТЕЛЬНАЯ АВТОРИЗАЦИЯ ГЛАВНОГО АДМИНИСТРАТОРА В ТАБЛИЦЕ admin_users
insert into admin_users (email, role, display_name)
values 
  ('damirovberdi00@gmail.com', 'Super Admin', 'Super Admin')
on conflict (email) do update 
set role = 'Super Admin', display_name = 'Super Admin';

-- 4. ЗАЩИТА ТАБЛИЦЫ admin_users
alter table admin_users enable row level security;
drop policy if exists "admin_users_view_admin" on admin_users;
drop policy if exists "admin_users_manage_admin" on admin_users;
drop policy if exists "admin_users_select_self_or_admin" on admin_users;

create policy "admin_users_select_self_or_admin" on admin_users
  for select to authenticated
  using (
    auth.uid() = user_id or 
    lower(email) = lower(auth.jwt() ->> 'email') or 
    is_admin()
  );

create policy "admin_users_manage_admin" on admin_users
  for all to authenticated
  using (is_admin())
  with check (is_admin());

-- 5. УСТРАНЕНИЕ БЕСКОНТРОЛЬНОГО ОБНОВЛЕНИЯ open_groups
alter table open_groups add column if not exists user_id uuid references auth.users(id) on delete set null;
drop policy if exists "open_groups_update_join" on open_groups;
drop policy if exists "open_groups_update_owner_or_admin" on open_groups;

create policy "open_groups_update_owner_or_admin" on open_groups 
  for update to authenticated 
  using (auth.uid() = user_id or is_admin())
  with check (auth.uid() = user_id or is_admin());

-- 6. УСТРАНЕНИЕ БЕСКОНТРОЛЬНОГО ОБНОВЛЕНИЯ visitor_sessions
drop policy if exists "visitor_sessions_update_public" on visitor_sessions;
drop policy if exists "visitor_sessions_update_admin" on visitor_sessions;

create policy "visitor_sessions_update_admin" on visitor_sessions 
  for update to authenticated 
  using (is_admin())
  with check (is_admin());

-- 7. ЗАЩИТА game_winners ОТ НАКРУТКИ И СПАМА
drop policy if exists "game_winners_insert_public" on game_winners;
drop policy if exists "game_winners_insert_authenticated" on game_winners;

create policy "game_winners_insert_authenticated" on game_winners 
  for insert to authenticated 
  with check (
    auth.uid() = user_id and 
    score >= 0 and score <= 100
  );

-- 8. ЗАЩИТА reviews ОТ АНОНИМНОГО СПАМА
drop policy if exists "reviews_insert_public" on reviews;
drop policy if exists "reviews_insert_authenticated" on reviews;

create policy "reviews_insert_authenticated" on reviews 
  for insert to authenticated 
  with check (
    auth.uid() = user_id and 
    rating >= 1 and rating <= 5 and 
    length(comment) > 0 and length(comment) <= 2000
  );

-- 9. ЗАЩИТА location_shares (СКРЫТИЕ ПРОСРОЧЕННЫХ МЕТОК И ЗАПРЕТ АНОНИМНЫХ ВСТАВОК)
drop policy if exists "location_shares_read_public" on location_shares;
drop policy if exists "location_shares_read_valid" on location_shares;

create policy "location_shares_read_valid" on location_shares 
  for select to anon, authenticated 
  using (expires_at is null or expires_at > now());

drop policy if exists "location_shares_insert_public" on location_shares;
drop policy if exists "location_shares_insert_authenticated" on location_shares;

create policy "location_shares_insert_authenticated" on location_shares 
  for insert to authenticated 
  with check (auth.uid() = user_id);
