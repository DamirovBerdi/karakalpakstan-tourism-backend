-- Telegram-style Chat System: Schema, RBAC, Triggers, RLS, and Realtime publication
-- 1. Chat banned users table for moderator bans
create table if not exists public.chat_banned_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text,
  banned_by uuid references auth.users(id) on delete set null,
  banned_at timestamptz not null default now(),
  banned_until timestamptz,
  constraint uk_chat_banned_user unique (user_id)
);

alter table public.chat_banned_users enable row level security;

drop policy if exists "chat_banned_select" on public.chat_banned_users;
create policy "chat_banned_select" on public.chat_banned_users for select to authenticated using (true);

drop policy if exists "chat_banned_admin_all" on public.chat_banned_users;
create policy "chat_banned_admin_all" on public.chat_banned_users for all to authenticated using (
  exists (select 1 from public.admin_users where user_id = auth.uid() and role in ('admin', 'super_admin', 'moderator'))
);

-- 2. Telegram-style chat_messages table
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  chat_id text not null,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_name text,
  sender_avatar text,
  content text not null check (char_length(trim(content)) > 0 and char_length(content) <= 4096),
  
  -- Reply to another message
  reply_to_message_id uuid references public.chat_messages(id) on delete set null,
  
  -- Forward metadata
  forward_from_chat_id text,
  forward_from_user_id uuid references auth.users(id) on delete set null,
  forward_sender_name text,
  
  -- Pin status
  is_pinned boolean not null default false,
  pinned_at timestamptz,
  pinned_by uuid references auth.users(id) on delete set null,
  
  -- Delivery, Edit and Timestamps
  status text not null default 'sent' check (status in ('sending', 'sent', 'read')),
  is_edited boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Indexes
create index if not exists idx_chat_messages_chat_id_created on public.chat_messages(chat_id, created_at asc);
create index if not exists idx_chat_messages_sender_id on public.chat_messages(sender_id);
create index if not exists idx_chat_messages_reply_to on public.chat_messages(reply_to_message_id);
create index if not exists idx_chat_messages_pinned on public.chat_messages(chat_id) where is_pinned = true;

-- Triggers for validation & security
create or replace function public.validate_chat_message_mutation()
returns trigger as $$
declare
  is_mod boolean;
begin
  select exists (
    select 1 from public.admin_users
    where user_id = auth.uid() and role in ('admin', 'super_admin', 'moderator')
  ) into is_mod;

  -- 1. IF CONTENT IS BEING MODIFIED:
  if new.content is distinct from old.content then
    -- ONLY original author can change content (admins/owners CANNOT edit other users' messages)
    if auth.uid() is distinct from old.sender_id then
      raise exception '403 Forbidden: You cannot edit messages sent by another user.'
        using errcode = '42501';
    end if;

    -- 48-hour edit window (Telegram standard)
    if old.created_at < (now() - interval '48 hours') then
      raise exception '403 Forbidden: Messages can only be edited within 48 hours of creation.'
        using errcode = '42501';
    end if;

    new.is_edited := true;
    new.updated_at := now();
  end if;

  -- 2. IF PIN STATUS IS BEING MODIFIED:
  if new.is_pinned is distinct from old.is_pinned then
    if not is_mod and auth.uid() is distinct from old.sender_id then
      raise exception '403 Forbidden: Only administrators or the message author can pin messages.'
        using errcode = '42501';
    end if;

    new.pinned_at := case when new.is_pinned then now() else null end;
    new.pinned_by := case when new.is_pinned then auth.uid() else null end;
  end if;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_validate_chat_message_mutation on public.chat_messages;
create trigger trg_validate_chat_message_mutation
before update on public.chat_messages
for each row execute function public.validate_chat_message_mutation();

-- Trigger on insert to reject banned users
create or replace function public.check_user_not_banned()
returns trigger as $$
begin
  if exists (
    select 1 from public.chat_banned_users
    where user_id = new.sender_id and (banned_until is null or banned_until > now())
  ) then
    raise exception '403 Forbidden: You are banned from posting in chat.'
      using errcode = '42501';
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_check_user_not_banned on public.chat_messages;
create trigger trg_check_user_not_banned
before insert on public.chat_messages
for each row execute function public.check_user_not_banned();

-- Row Level Security
alter table public.chat_messages enable row level security;

drop policy if exists "chat_messages_select" on public.chat_messages;
create policy "chat_messages_select" on public.chat_messages for select to authenticated using (true);

drop policy if exists "chat_messages_insert" on public.chat_messages;
create policy "chat_messages_insert" on public.chat_messages for insert to authenticated with check (
  auth.uid() = sender_id
);

drop policy if exists "chat_messages_update" on public.chat_messages;
create policy "chat_messages_update" on public.chat_messages for update to authenticated using (
  auth.uid() = sender_id or exists (
    select 1 from public.admin_users where user_id = auth.uid() and role in ('admin', 'super_admin', 'moderator')
  )
);

drop policy if exists "chat_messages_delete" on public.chat_messages;
create policy "chat_messages_delete" on public.chat_messages for delete to authenticated using (
  auth.uid() = sender_id or exists (
    select 1 from public.admin_users where user_id = auth.uid() and role in ('admin', 'super_admin', 'moderator')
  )
);

-- Enable full replica identity and publication for Supabase Realtime WebSockets
alter table public.chat_messages replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'chat_messages') then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end;
$$;
