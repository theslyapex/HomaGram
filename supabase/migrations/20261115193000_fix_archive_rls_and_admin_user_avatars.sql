-- Allow signed-in active members to update only their own archive timestamp.
grant update (archived_at) on table public.conversation_members to authenticated;

drop policy if exists "Members can update own conversation archive state" on public.conversation_members;
create policy "Members can update own conversation archive state"
on public.conversation_members
for update to authenticated
using (
  user_id = (select auth.uid())
  and left_at is null
)
with check (
  user_id = (select auth.uid())
  and left_at is null
);

-- Include avatar paths in the admin-only user listing so the client can
-- generate short-lived signed URLs from the private avatars bucket.
drop function if exists public.admin_list_users(text, integer, integer);
drop function if exists private.admin_list_users(text, integer, integer);

create function private.admin_list_users(
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  user_id uuid,
  username text,
  display_name text,
  avatar_path text,
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
         p.avatar_path,
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

create function public.admin_list_users(
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  user_id uuid,
  username text,
  display_name text,
  avatar_path text,
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

revoke all on function private.admin_list_users(text, integer, integer) from public, anon;
revoke all on function public.admin_list_users(text, integer, integer) from public, anon;
grant execute on function private.admin_list_users(text, integer, integer) to authenticated;
grant execute on function public.admin_list_users(text, integer, integer) to authenticated;
