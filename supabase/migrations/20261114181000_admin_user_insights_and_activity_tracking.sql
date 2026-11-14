create table if not exists public.user_activity_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  last_heartbeat_at timestamptz not null default now(),
  ended_at timestamptz,
  total_seconds bigint not null default 0 check (total_seconds >= 0)
);
create index if not exists user_activity_sessions_user_started_idx
  on public.user_activity_sessions(user_id, started_at desc);
alter table public.user_activity_sessions enable row level security;
revoke all on table public.user_activity_sessions from public, anon, authenticated;

create or replace function private.track_user_activity(p_session_id uuid, p_is_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or p_session_id is null then
    raise exception 'Authenticated session required' using errcode = '42501';
  end if;

  if p_is_active then
    insert into public.user_activity_sessions(id, user_id)
    values (p_session_id, v_uid)
    on conflict (id) do update
      set total_seconds = public.user_activity_sessions.total_seconds +
            least(90, greatest(0, floor(extract(epoch from (now() - public.user_activity_sessions.last_heartbeat_at)))::bigint)),
          last_heartbeat_at = now()
      where public.user_activity_sessions.user_id = v_uid
        and public.user_activity_sessions.ended_at is null;
  else
    update public.user_activity_sessions
    set total_seconds = total_seconds +
          least(90, greatest(0, floor(extract(epoch from (now() - last_heartbeat_at)))::bigint)),
        last_heartbeat_at = now(),
        ended_at = now()
    where id = p_session_id
      and user_id = v_uid
      and ended_at is null;
  end if;
end;
$$;
revoke all on function private.track_user_activity(uuid, boolean) from public, anon;
grant execute on function private.track_user_activity(uuid, boolean) to authenticated;

create or replace function public.track_user_activity(p_session_id uuid, p_is_active boolean)
returns void
language sql
security invoker
set search_path = ''
as $$ select private.track_user_activity(p_session_id, p_is_active); $$;
revoke all on function public.track_user_activity(uuid, boolean) from public, anon;
grant execute on function public.track_user_activity(uuid, boolean) to authenticated;

create or replace function private.admin_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user auth.users%rowtype;
  v_profile public.profiles%rowtype;
  v_result jsonb;
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  select * into v_user from auth.users where id = p_user_id;
  if not found then raise exception 'User not found' using errcode = 'P0002'; end if;
  select * into v_profile from public.profiles where id = p_user_id;

  select jsonb_build_object(
    'user_id', v_user.id,
    'username', v_profile.username,
    'display_name', v_profile.display_name,
    'bio', v_profile.bio,
    'website_url', v_profile.website_url,
    'created_at', v_user.created_at,
    'last_sign_in_at', v_user.last_sign_in_at,
    'banned_until', v_user.banned_until,
    'posts', (select count(*) from public.posts p where p.author_id = p_user_id),
    'reels', (select count(*) from public.posts p where p.author_id = p_user_id and p.is_reel),
    'stories', (select count(*) from public.stories s where s.author_id = p_user_id),
    'comments', (select count(*) from public.post_comments c where c.user_id = p_user_id),
    'likes_received', (select count(*) from public.post_likes l join public.posts p on p.id = l.post_id where p.author_id = p_user_id),
    'followers', (select count(*) from public.user_follows f where f.following_id = p_user_id),
    'following', (select count(*) from public.user_follows f where f.follower_id = p_user_id),
    'reports_made', (select count(*) from public.post_reports r where r.reporter_id = p_user_id),
    'reports_received', (select count(*) from public.post_reports r join public.posts p on p.id = r.post_id where p.author_id = p_user_id),
    'messages_sent', (select count(*) from public.messages m where m.sender_id = p_user_id),
    'activity_seconds', (select coalesce(sum(a.total_seconds + case when a.ended_at is null then least(90, greatest(0, floor(extract(epoch from (now() - a.last_heartbeat_at)))::bigint)) else 0 end),0) from public.user_activity_sessions a where a.user_id = p_user_id),
    'reports_submitted', coalesce((
      select jsonb_agg(jsonb_build_object(
        'report_id', r.id, 'reason', r.reason, 'details', r.details,
        'status', r.status, 'created_at', r.created_at, 'post_id', r.post_id,
        'post_caption', p.caption, 'post_author_id', p.author_id
      ) order by r.created_at desc)
      from public.post_reports r left join public.posts p on p.id = r.post_id
      where r.reporter_id = p_user_id
    ), '[]'::jsonb),
    'reports_against', coalesce((
      select jsonb_agg(jsonb_build_object(
        'report_id', r.id, 'reason', r.reason, 'details', r.details,
        'status', r.status, 'created_at', r.created_at, 'post_id', r.post_id,
        'post_caption', p.caption, 'reporter_id', r.reporter_id
      ) order by r.created_at desc)
      from public.post_reports r join public.posts p on p.id = r.post_id
      where p.author_id = p_user_id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function private.admin_user_detail(uuid) from public, anon;
grant execute on function private.admin_user_detail(uuid) to authenticated;

create or replace function public.admin_user_detail(p_user_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select private.admin_user_detail(p_user_id); $$;
revoke all on function public.admin_user_detail(uuid) from public, anon;
grant execute on function public.admin_user_detail(uuid) to authenticated;
