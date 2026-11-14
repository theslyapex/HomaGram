create schema if not exists private;

create table if not exists private.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
alter table private.admin_users enable row level security;
revoke all on table private.admin_users from public, anon, authenticated;
grant select, insert, update, delete on table private.admin_users to service_role;

create table if not exists private.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  target_user_id uuid references auth.users(id) on delete set null,
  action text not null check (char_length(action) between 1 and 80),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);
alter table private.admin_audit_logs enable row level security;
revoke all on table private.admin_audit_logs from public, anon, authenticated;
grant select, insert on table private.admin_audit_logs to service_role;
create index if not exists admin_audit_logs_created_idx
  on private.admin_audit_logs(created_at desc);
create index if not exists admin_audit_logs_target_created_idx
  on private.admin_audit_logs(target_user_id, created_at desc);

grant usage on schema private to authenticated;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.admin_users a
    where a.user_id = (select auth.uid())
  );
$$;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;

create or replace function public.is_current_user_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.is_admin();
$$;
revoke all on function public.is_current_user_admin() from public, anon;
grant execute on function public.is_current_user_admin() to authenticated;

alter table public.post_reports
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'reviewed', 'dismissed', 'actioned')),
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text
    check (review_note is null or char_length(review_note) <= 1000);

create index if not exists post_reports_status_created_idx
  on public.post_reports(status, created_at desc);

drop policy if exists "Admins can read post reports" on public.post_reports;
create policy "Admins can read post reports"
  on public.post_reports for select to authenticated
  using (private.is_admin());

drop policy if exists "Admins can review post reports" on public.post_reports;
create policy "Admins can review post reports"
  on public.post_reports for update to authenticated
  using (private.is_admin())
  with check (private.is_admin());

grant select, update on public.post_reports to authenticated;

create or replace function private.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'users', (select count(*) from auth.users),
    'posts', (select count(*) from public.posts),
    'stories', (select count(*) from public.stories),
    'reels', (select count(*) from public.posts where is_reel),
    'messages', (select count(*) from public.messages),
    'groups', (select count(*) from public.conversations where kind = 'group'),
    'channels', (select count(*) from public.channels),
    'pending_post_reports', (select count(*) from public.post_reports where status = 'pending'),
    'open_support_conversations', (select count(*) from public.support_conversations where status = 'open')
  );
end;
$$;
revoke all on function private.admin_dashboard_stats() from public, anon;
grant execute on function private.admin_dashboard_stats() to authenticated;

create or replace function public.admin_dashboard_stats()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.admin_dashboard_stats();
$$;
revoke all on function public.admin_dashboard_stats() from public, anon;
grant execute on function public.admin_dashboard_stats() to authenticated;

create or replace function private.admin_list_users(
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  created_at timestamptz,
  banned_until timestamptz,
  is_banned boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  return query
  select u.id,
         p.username,
         p.display_name,
         u.created_at,
         u.banned_until,
         coalesce(u.banned_until > now(), false)
  from auth.users u
  left join public.profiles p on p.id = u.id
  where v_search is null
     or coalesce(p.username, '') ilike '%' || v_search || '%'
     or coalesce(p.display_name, '') ilike '%' || v_search || '%'
  order by u.created_at desc
  limit v_limit offset v_offset;
end;
$$;
revoke all on function private.admin_list_users(text, integer, integer) from public, anon;
grant execute on function private.admin_list_users(text, integer, integer) to authenticated;

create or replace function public.admin_list_users(
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  created_at timestamptz,
  banned_until timestamptz,
  is_banned boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.admin_list_users(p_search, p_limit, p_offset);
$$;
revoke all on function public.admin_list_users(text, integer, integer) from public, anon;
grant execute on function public.admin_list_users(text, integer, integer) to authenticated;

create or replace function private.admin_list_post_reports(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  report_id uuid,
  post_id uuid,
  reporter_id uuid,
  reason text,
  details text,
  status text,
  created_at timestamptz,
  reviewed_at timestamptz,
  review_note text,
  post_author_id uuid,
  post_caption text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  return query
  select r.id, r.post_id, r.reporter_id, r.reason, r.details, r.status,
         r.created_at, r.reviewed_at, r.review_note, p.author_id, p.caption
  from public.post_reports r
  left join public.posts p on p.id = r.post_id
  order by case when r.status = 'pending' then 0 else 1 end, r.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
revoke all on function private.admin_list_post_reports(integer, integer) from public, anon;
grant execute on function private.admin_list_post_reports(integer, integer) to authenticated;

create or replace function public.admin_list_post_reports(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  report_id uuid,
  post_id uuid,
  reporter_id uuid,
  reason text,
  details text,
  status text,
  created_at timestamptz,
  reviewed_at timestamptz,
  review_note text,
  post_author_id uuid,
  post_caption text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.admin_list_post_reports(p_limit, p_offset);
$$;
revoke all on function public.admin_list_post_reports(integer, integer) from public, anon;
grant execute on function public.admin_list_post_reports(integer, integer) to authenticated;

create or replace function private.admin_review_post_report(
  p_report_id uuid,
  p_status text,
  p_review_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_target uuid;
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_status not in ('reviewed', 'dismissed', 'actioned') then
    raise exception 'Invalid report status' using errcode = '22023';
  end if;
  if p_review_note is not null and char_length(p_review_note) > 1000 then
    raise exception 'Review note is too long' using errcode = '22023';
  end if;

  update public.post_reports
  set status = p_status,
      reviewed_by = v_actor,
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_review_note, '')), '')
  where id = p_report_id
  returning post_id into v_target;

  if v_target is null then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;

  insert into private.admin_audit_logs(actor_id, action, metadata)
  values (
    v_actor,
    'post_report_reviewed',
    jsonb_build_object('report_id', p_report_id, 'status', p_status)
  );
end;
$$;
revoke all on function private.admin_review_post_report(uuid, text, text) from public, anon;
grant execute on function private.admin_review_post_report(uuid, text, text) to authenticated;

create or replace function public.admin_review_post_report(
  p_report_id uuid,
  p_status text,
  p_review_note text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.admin_review_post_report(p_report_id, p_status, p_review_note);
$$;
revoke all on function public.admin_review_post_report(uuid, text, text) from public, anon;
grant execute on function public.admin_review_post_report(uuid, text, text) to authenticated;
