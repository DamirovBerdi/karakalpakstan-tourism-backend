-- =====================================================================
-- МИГРАЦИЯ УСТРАНЕНИЯ БИЗНЕС-ЛОГИЧЕСКИХ УЯЗВИМОСТЕЙ (STATUS MANIPULATION & INPUT LIMITS)
-- Проект: Karakalpakstan Tourism Portal
-- =====================================================================

-- 1. hotel_bookings: Защита от манипуляции статусом (клиент не может поставить status='confirmed' или отрицательные цены)
drop policy if exists "hotel_bookings_insert_public" on hotel_bookings;
create policy "hotel_bookings_insert_public" on hotel_bookings
  for insert to anon, authenticated
  with check (
    (status = 'pending' or status is null) and
    nights >= 1 and
    guests >= 1 and
    price_per_night >= 0 and
    total_price >= 0
  );

-- 2. taxi_bookings: Защита от манипуляции статусом заказа такси
drop policy if exists "taxi_bookings_insert_public" on taxi_bookings;
create policy "taxi_bookings_insert_public" on taxi_bookings
  for insert to anon, authenticated
  with check (
    (status = 'pending' or status is null) and
    passengers >= 1 and passengers <= 20
  );

-- 3. aral_bookings: Защита от манипуляции статусом туров на Арал
drop policy if exists "aral_bookings_insert_public" on aral_bookings;
create policy "aral_bookings_insert_public" on aral_bookings
  for insert to anon, authenticated
  with check (
    (status = 'pending' or status is null) and
    group_size >= 1 and group_size <= 50
  );

-- 4. tourist_requests: Защита от манипуляции статусом заявок на туры
drop policy if exists "tourist_requests_insert_public" on tourist_requests;
create policy "tourist_requests_insert_public" on tourist_requests
  for insert to anon, authenticated
  with check (
    (status = 'pending' or status is null) and
    group_size >= 1 and group_size <= 50
  );

-- 5. visa_applications: Защита от манипуляции статусом визовых анкет
drop policy if exists "visa_insert_public" on visa_applications;
create policy "visa_insert_public" on visa_applications
  for insert to anon, authenticated
  with check (
    (status = 'pending' or status is null)
  );

-- 6. open_groups: Валидация вместимости и статуса группы попутчиков
drop policy if exists "open_groups_insert_public" on open_groups;
create policy "open_groups_insert_public" on open_groups
  for insert to anon, authenticated
  with check (
    (status = 'open' or status is null) and
    max_members between 2 and 30 and
    current_members >= 1 and
    current_members <= max_members and
    length(creator_name) > 0 and
    length(creator_name) <= 100
  );

-- 7. travel_buddies: Валидация статуса поиска попутчиков
drop policy if exists "travel_buddies_insert_public" on travel_buddies;
create policy "travel_buddies_insert_public" on travel_buddies
  for insert to anon, authenticated
  with check (
    (status = 'active' or status is null) and
    length(name) > 0 and
    length(name) <= 100
  );

-- 8. admin_support_messages: Ограничение длины сообщений поддержки
drop policy if exists "admin_support_insert" on admin_support_messages;
create policy "admin_support_insert" on admin_support_messages
  for insert to anon, authenticated
  with check (
    length(content) > 0 and
    length(content) <= 5000 and
    length(sender_name) > 0 and
    length(sender_name) <= 100
  );
