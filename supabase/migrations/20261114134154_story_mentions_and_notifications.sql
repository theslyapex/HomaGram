create table if not exists public.story_mentions (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  mentioned_user_id uuid not null references public.profiles(id) on delete cascade,
  mentioned_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint story_mentions_unique unique (story_id, mentioned_user_id),
  constraint story_mentions_not_self check (mentioned_user_id <> mentioned_by)
);

create index if not exists story_mentions_user_created_idx
  on public.story_mentions (mentioned_user_id, created_at desc);
create index if not exists story_mentions_story_idx
  on public.story_mentions (story_id);

alter table public.story_mentions enable row level security;
drop policy if exists "Users can read story mentions involving them" on public.story_mentions;
create policy "Users can read story mentions involving them"
on public.story_mentions for select to authenticated
using (
  mentioned_user_id = (select auth.uid())
  or mentioned_by = (select auth.uid())
);

grant select on public.story_mentions to authenticated;
revoke all on public.story_mentions from anon;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check
  check (type = any (array[
    'follow','post_like','post_comment','comment_reply','post_repost',
    'story_reaction','message_new','support_message','support_reply','story_mention'
  ]::text[]));

create or replace function private.sync_story_mentions()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_text text;
  v_match text[];
  v_user_id uuid;
  v_username text;
  v_inserted integer;
begin
  v_text := concat_ws(E'\\n', new.caption, new.text_content, new.overlay_text);

  for v_match in
    select regexp_matches(v_text, '(^|[^a-zA-Z0-9_])@([a-z0-9_]{3,24})', 'gi')
  loop
    v_username := lower(v_match[2]);
    select p.id into v_user_id
      from public.profiles p
      where lower(p.username) = v_username
      limit 1;

    if v_user_id is not null and v_user_id <> new.author_id then
      insert into public.story_mentions(story_id, mentioned_user_id, mentioned_by)
      values (new.id, v_user_id, new.author_id)
      on conflict (story_id, mentioned_user_id) do nothing;

      get diagnostics v_inserted = row_count;
      if v_inserted > 0 and coalesce((
        select pref.social_enabled
        from public.user_notification_preferences pref
        where pref.user_id = v_user_id
      ), true) then
        insert into public.notifications(
          recipient_id, actor_id, type, entity_id, entity_type, message
        ) values (
          v_user_id, new.author_id, 'story_mention', new.id, 'story',
          'شما را در یک استوری منشن کرد.'
        );
      end if;
    end if;
    v_user_id := null;
  end loop;

  return new;
end;
$$;

revoke all on function private.sync_story_mentions() from public, anon, authenticated;
drop trigger if exists story_mentions_after_insert on public.stories;
create trigger story_mentions_after_insert
after insert on public.stories
for each row execute function private.sync_story_mentions();
