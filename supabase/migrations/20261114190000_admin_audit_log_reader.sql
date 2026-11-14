create or replace function private.admin_list_audit_logs(
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  log_id uuid,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  target_user_id uuid,
  target_username text,
  target_display_name text,
  action text,
  metadata jsonb,
  created_at timestamptz
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
  select
    l.id,
    l.actor_id,
    actor.username,
    actor.display_name,
    l.target_user_id,
    target.username,
    target.display_name,
    l.action,
    l.metadata,
    l.created_at
  from private.admin_audit_logs l
  left join public.profiles actor on actor.id = l.actor_id
  left join public.profiles target on target.id = l.target_user_id
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit, 100), 1), 200)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function private.admin_list_audit_logs(integer, integer) from public, anon;
grant execute on function private.admin_list_audit_logs(integer, integer) to authenticated;

create or replace function public.admin_list_audit_logs(
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  log_id uuid,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  target_user_id uuid,
  target_username text,
  target_display_name text,
  action text,
  metadata jsonb,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.admin_list_audit_logs(p_limit, p_offset);
$$;

revoke all on function public.admin_list_audit_logs(integer, integer) from public, anon;
grant execute on function public.admin_list_audit_logs(integer, integer) to authenticated;
