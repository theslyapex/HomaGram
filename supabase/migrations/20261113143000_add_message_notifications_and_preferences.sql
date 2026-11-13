alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('follow','post_like','post_comment','comment_reply','post_repost','story_reaction','message_new'));
alter table public.notifications drop constraint if exists notifications_entity_type_check;
alter table public.notifications add constraint notifications_entity_type_check
  check (entity_type in ('profile','post','comment','story','conversation'));

create table if not exists public.user_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  social_enabled boolean not null default true,
  messages_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.user_notification_preferences enable row level security;
drop policy if exists "Users manage their own notification preferences" on public.user_notification_preferences;
create policy "Users manage their own notification preferences"
  on public.user_notification_preferences for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
revoke all on public.user_notification_preferences from anon, authenticated;
grant select, insert, update on public.user_notification_preferences to authenticated;

create or replace function public.handle_social_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recipient uuid;
  v_actor uuid;
  v_entity uuid;
  v_type text;
  v_entity_type text;
  v_message text;
  v_enabled boolean;
begin
  if tg_table_name = 'user_follows' then
    v_actor := new.follower_id; v_recipient := new.following_id;
    v_entity := new.following_id; v_type := 'follow'; v_entity_type := 'profile';
    v_message := 'شما را دنبال کرد.';
  elsif tg_table_name = 'post_likes' then
    v_actor := new.user_id;
    select author_id into v_recipient from public.posts where id = new.post_id;
    v_entity := new.post_id; v_type := 'post_like'; v_entity_type := 'post';
    v_message := 'پسندید.';
  elsif tg_table_name = 'post_reposts' then
    v_actor := new.user_id;
    select author_id into v_recipient from public.posts where id = new.post_id;
    v_entity := new.post_id; v_type := 'post_repost'; v_entity_type := 'post';
    v_message := 'پست شما را بازنشر کرد.';
  elsif tg_table_name = 'post_comments' then
    v_actor := new.user_id; v_entity := new.id; v_entity_type := 'comment';
    if new.parent_id is not null then
      select user_id into v_recipient from public.post_comments
        where id = new.parent_id and post_id = new.post_id;
      v_type := 'comment_reply'; v_message := 'به دیدگاه شما پاسخ داد.';
    else
      select author_id into v_recipient from public.posts where id = new.post_id;
      v_type := 'post_comment'; v_message := 'برای پست شما دیدگاه گذاشت.';
    end if;
  elsif tg_table_name = 'story_reactions' then
    v_actor := new.user_id;
    select author_id into v_recipient from public.stories where id = new.story_id;
    v_entity := new.story_id; v_type := 'story_reaction'; v_entity_type := 'story';
    v_message := 'به استوری شما واکنش نشان داد.';
  else
    return new;
  end if;

  if v_recipient is not null and v_actor is not null and v_actor <> v_recipient then
    select coalesce((select social_enabled from public.user_notification_preferences
      where user_id = v_recipient), true) into v_enabled;
    if v_enabled then
      insert into public.notifications (recipient_id, actor_id, type, entity_id, entity_type, message)
      values (v_recipient, v_actor, v_type, v_entity, v_entity_type, v_message);
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.handle_message_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  member record;
  v_enabled boolean;
begin
  if new.deleted_at is not null then return new; end if;
  for member in
    select user_id, muted_until
    from public.conversation_members
    where conversation_id = new.conversation_id
      and user_id <> new.sender_id
      and left_at is null
  loop
    if member.muted_until is not null and member.muted_until > now() then
      continue;
    end if;
    select coalesce((select messages_enabled from public.user_notification_preferences
      where user_id = member.user_id), true) into v_enabled;
    if v_enabled then
      insert into public.notifications
        (recipient_id, actor_id, type, entity_id, entity_type, message)
      values
        (member.user_id, new.sender_id, 'message_new', new.conversation_id,
         'conversation', 'پیام جدیدی برای شما ارسال کرد.');
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function public.handle_message_notification() from public, anon, authenticated;
drop trigger if exists notify_message_created on public.messages;
create trigger notify_message_created
  after insert on public.messages
  for each row execute function public.handle_message_notification();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
