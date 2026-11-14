-- HomaGram isolated in-app support inbox.
-- Support data is intentionally separate from ordinary conversations/messages.

create or replace function private.is_homagram_support_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from auth.users u
    where u.id = (select auth.uid())
      and lower(u.email) = 'theslyapex@gmail.com'
      and u.email_confirmed_at is not null
  );
$function$;

revoke all on function private.is_homagram_support_admin() from public, anon;
grant execute on function private.is_homagram_support_admin() to authenticated;

create table if not exists public.support_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  status text not null default 'open' check (status in ('open','closed')),
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_conversations_status_activity_idx
  on public.support_conversations(status, last_message_at desc nulls last);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.support_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message_type text not null default 'text'
    check (message_type in ('text','image','file')),
  body text not null default '',
  storage_path text unique,
  file_name text,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now(),
  constraint support_messages_body_length check (char_length(body) <= 10000),
  constraint support_messages_content_check check (
    (message_type = 'text' and char_length(btrim(body)) > 0 and storage_path is null)
    or
    (message_type in ('image','file') and
      (char_length(btrim(body)) > 0 or storage_path is not null))
  ),
  constraint support_messages_attachment_metadata_check check (
    (storage_path is null and file_name is null and mime_type is null and size_bytes is null)
    or
    (storage_path is not null and file_name is not null and mime_type is not null
      and size_bytes between 1 and 52428800)
  )
);

create index if not exists support_messages_conversation_created_idx
  on public.support_messages(conversation_id, created_at desc, id desc);

alter table public.support_conversations enable row level security;
alter table public.support_messages enable row level security;

revoke all on public.support_conversations, public.support_messages from anon, authenticated;
grant select on public.support_conversations, public.support_messages to authenticated;
grant insert on public.support_messages to authenticated;
grant update (status, updated_at) on public.support_conversations to authenticated;

drop policy if exists "Support participants can read support conversations" on public.support_conversations;
create policy "Support participants can read support conversations"
on public.support_conversations for select to authenticated
using (user_id = (select auth.uid()) or private.is_homagram_support_admin());

drop policy if exists "Support participants can read support messages" on public.support_messages;
create policy "Support participants can read support messages"
on public.support_messages for select to authenticated
using (
  private.is_homagram_support_admin()
  or exists (
    select 1 from public.support_conversations sc
    where sc.id = support_messages.conversation_id
      and sc.user_id = (select auth.uid())
  )
);

drop policy if exists "Support participants can send messages" on public.support_messages;
create policy "Support participants can send messages"
on public.support_messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and exists (
    select 1 from public.support_conversations sc
    where sc.id = support_messages.conversation_id
      and (
        private.is_homagram_support_admin()
        or (sc.user_id = (select auth.uid()) and sc.status = 'open')
      )
  )
);

drop policy if exists "Support admin can update conversation status" on public.support_conversations;
create policy "Support admin can update conversation status"
on public.support_conversations for update to authenticated
using (private.is_homagram_support_admin())
with check (private.is_homagram_support_admin());

create or replace function private.get_or_create_support_conversation()
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_conversation_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  insert into public.support_conversations(user_id)
  values (v_user_id)
  on conflict (user_id) do update
    set updated_at = public.support_conversations.updated_at
  returning id into v_conversation_id;

  return v_conversation_id;
end;
$function$;

revoke all on function private.get_or_create_support_conversation() from public, anon;
grant execute on function private.get_or_create_support_conversation() to authenticated;

create or replace function public.get_or_create_support_conversation()
returns uuid
language sql
security invoker
set search_path = ''
as $function$
  select private.get_or_create_support_conversation();
$function$;

revoke all on function public.get_or_create_support_conversation() from public, anon;
grant execute on function public.get_or_create_support_conversation() to authenticated;

-- Private support media bucket; paths are {conversation_id}/{uploader_id}/{file_id}.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'support-media', 'support-media', false, 52428800,
  array[
    'image/jpeg','image/png','image/webp','image/gif',
    'application/pdf','application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain','text/csv','application/zip'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Support participants can upload support media" on storage.objects;
create policy "Support participants can upload support media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'support-media'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1 from public.support_conversations sc
    where sc.id = split_part(name, '/', 1)::uuid
      and (
        private.is_homagram_support_admin()
        or (sc.user_id = (select auth.uid()) and sc.status = 'open')
      )
  )
);

drop policy if exists "Support participants can read support media" on storage.objects;
create policy "Support participants can read support media"
on storage.objects for select to authenticated
using (
  bucket_id = 'support-media'
  and exists (
    select 1 from public.support_conversations sc
    where sc.id = split_part(name, '/', 1)::uuid
      and (
        private.is_homagram_support_admin()
        or sc.user_id = (select auth.uid())
      )
  )
);

drop policy if exists "Uploaders can delete their support media" on storage.objects;
create policy "Uploaders can delete their support media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'support-media'
  and split_part(name, '/', 2) = (select auth.uid())::text
);

-- Extend existing notification types without changing existing notification access rules.
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'follow','post_like','post_comment','comment_reply','post_repost',
    'story_reaction','message_new','support_message','support_reply'
  ));

alter table public.notifications drop constraint if exists notifications_entity_type_check;
alter table public.notifications add constraint notifications_entity_type_check
  check (entity_type in ('profile','post','comment','story','conversation','support'));

create or replace function private.handle_support_message_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner_id uuid;
  v_admin_id uuid;
  v_type text;
  v_message text;
  v_recipient uuid;
begin
  select sc.user_id into v_owner_id
  from public.support_conversations sc
  where sc.id = new.conversation_id;

  select u.id into v_admin_id
  from auth.users u
  where lower(u.email) = 'theslyapex@gmail.com'
    and u.email_confirmed_at is not null
  limit 1;

  if v_admin_id is null then
    return new;
  end if;

  if new.sender_id = v_admin_id then
    v_recipient := v_owner_id;
    v_type := 'support_reply';
    v_message := 'تیم پشتیبانی هماگرام به درخواست شما پاسخ داد.';
  else
    v_recipient := v_admin_id;
    v_type := 'support_message';
    v_message := 'پیام پشتیبانی جدیدی دریافت شد.';
  end if;

  if v_recipient is not null and v_recipient <> new.sender_id then
    insert into public.notifications
      (recipient_id, actor_id, type, entity_id, entity_type, message)
    values
      (v_recipient, new.sender_id, v_type, new.conversation_id, 'support', v_message);
  end if;

  update public.support_conversations
  set last_message_at = new.created_at,
      updated_at = now()
  where id = new.conversation_id;

  return new;
end;
$function$;

revoke all on function private.handle_support_message_notification() from public, anon, authenticated;

drop trigger if exists support_message_notification_created on public.support_messages;
create trigger support_message_notification_created
after insert on public.support_messages
for each row execute function private.handle_support_message_notification();

do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_conversations'
  ) then
    alter publication supabase_realtime add table public.support_conversations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_messages'
  ) then
    alter publication supabase_realtime add table public.support_messages;
  end if;
end;
$publication$;
