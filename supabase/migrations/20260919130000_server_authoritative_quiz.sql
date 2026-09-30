-- =====================================================================
-- МИГРАЦИЯ СЕРВЕРНОЙ АВТОРИТАРНОЙ ВАЛИДАЦИИ ОТВЕТОВ ВИКТОРИНЫ
-- Проект: Karakalpakstan Tourism Portal
-- Устраняет подделку баллов: клиент передает только массив ответов p_answers.
-- Сервер сам сверяет ответы с ключами, считает верный балл и начисляет очки.
-- Добавлен кулдаун 60 секунд для защиты от спам-фарминга очков.
-- =====================================================================

-- 1. Удаляем старую функцию, принимавшую доверенный p_score от клиента
drop function if exists public.submit_quiz_result(integer, integer);

-- 2. Создаем новую функцию с серверной валидацией ответов
create or replace function public.submit_quiz_result(p_answers integer[])
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  -- Авторитарный ключ правильных ответов для 10 вопросов викторины
  v_keys integer[] := array[1, 1, 0, 1, 1, 0, 1, 1, 1, 2];
  v_score integer := 0;
  v_total integer := 10;
  v_points integer := 0;
  i integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Unauthorized: must be logged in';
  end if;

  if p_answers is null or array_length(p_answers, 1) is null or array_length(p_answers, 1) = 0 then
    raise exception 'Answers array cannot be empty';
  end if;

  if array_length(p_answers, 1) > 20 then
    raise exception 'Answers array exceeds maximum length';
  end if;

  -- Защита от спама и повторов: кулдаун 60 секунд между попытками викторины
  if exists (
    select 1 from public.quiz_results
    where user_id = v_user_id and created_at > now() - interval '60 seconds'
  ) then
    raise exception 'Cooldown: please wait at least 60 seconds before submitting another quiz';
  end if;

  -- Авторитарный расчет баллов сервером
  for i in 1..least(array_length(p_answers, 1), v_total) loop
    if p_answers[i] is not null and p_answers[i] = v_keys[i] then
      v_score := v_score + 1;
    end if;
  end loop;

  -- 15 баллов за верный ответ (максимум 150 баллов за 10 вопросов)
  v_points := v_score * 15;

  -- Запись результата викторины
  insert into public.quiz_results (user_id, score, total, points_earned)
  values (v_user_id, v_score, v_total, v_points);

  -- Начисление баллов в таблицу лидеров
  if v_points > 0 then
    insert into public.user_points (user_id, points, reason)
    values (v_user_id, v_points, 'quiz_win');
  end if;

  return json_build_object(
    'success', true,
    'score', v_score,
    'total', v_total,
    'points_earned', v_points
  );
end;
$$;
