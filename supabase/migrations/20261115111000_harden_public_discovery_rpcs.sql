-- Keep privileged discovery operations out of the exposed public schema.
create or replace function private.create_public_group_impl(
  p_title text, p_slug text, p_description text default '', p_member_ids uuid[] default '{}'::uuid[]
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_members uuid[];
  v_count integer;
  v_conversation_id uuid;
begin
  if v_actor is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception 'Group title must contain 1 to 100 characters' using errcode = '22023';
  end if;
  if v_slug !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'Public group username must be 3 to 32 characters' using errcode = '22023';
  end if;
  if char_length(coalesce(p_description, '')) > 500 then
    raise exception 'Description is too long' using errcode = '22023';
  end if;
  select coalesce(array_agg(x order by x), '{}'::uuid[]) into v_members
  from (
    select distinct member_id as x from unnest(coalesce(p_member_ids, '{}'::uuid[])) as member_id
    where member_id is not null and member_id <> v_actor
  ) members;
  v_count := coalesce(array_length(v_members, 1), 0);
  if v_count > 99 then raise exception 'A group can include at most 100 people at creation' using errcode = '22023'; end if;
  if exists (
    select 1 from unnest(v_members) requested(user_id)
    left join auth.users u on u.id = requested.user_id where u.id is null
  ) then raise exception 'One or more selected users do not exist' using errcode = '22023'; end if;
  insert into public.conversations(kind, title, description, created_by, is_public, public_slug)
  values ('group', btrim(p_title), btrim(coalesce(p_description, '')), v_actor, true, v_slug)
  returning id into v_conversation_id;
  insert into public.conversation_members(conversation_id, user_id, role)
  values (v_conversation_id, v_actor, 'owner');
  if v_count > 0 then
    insert into public.conversation_members(conversation_id, user_id, role)
    select v_conversation_id, member_id, 'member' from unnest(v_members) as member_id;
  end if;
  return v_conversation_id;
end;
$function$;

create or replace function private.join_public_group_impl(p_conversation_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if not exists (select 1 from public.conversations c
    where c.id = p_conversation_id and c.kind = 'group' and c.is_public = true) then
    raise exception 'Public group not found' using errcode = 'P0002';
  end if;
  insert into public.conversation_members(conversation_id, user_id, role, joined_at, left_at)
  values (p_conversation_id, v_actor, 'member', now(), null)
  on conflict (conversation_id, user_id) do update set
    role = case when public.conversation_members.left_at is null then public.conversation_members.role else 'member' end,
    joined_at = case when public.conversation_members.left_at is null then public.conversation_members.joined_at else now() end,
    left_at = null;
end;
$function$;

create or replace function private.search_public_communities_impl(
  p_query text default '', p_kind text default 'all', p_limit integer default 30, p_offset integer default 0
)
returns table (
  conversation_id uuid, kind text, title text, slug text, description text,
  member_count bigint, is_member boolean, created_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_query text := translate(lower(btrim(coalesce(p_query, ''))), '%_', '');
  v_kind text := lower(coalesce(p_kind, 'all'));
begin
  if v_actor is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if char_length(v_query) > 80 then raise exception 'Search query is too long' using errcode = '22023'; end if;
  if v_kind not in ('all', 'group', 'channel') then raise exception 'Invalid community type' using errcode = '22023'; end if;
  return query
  select c.id, c.kind, coalesce(c.title, ''),
    case when c.kind = 'channel' then ch.slug else c.public_slug end,
    case when c.kind = 'channel' then ch.description else c.description end,
    count(cm.user_id)::bigint, coalesce(bool_or(cm.user_id = v_actor), false), c.created_at
  from public.conversations c
  left join public.channels ch on ch.conversation_id = c.id
  left join public.conversation_members cm on cm.conversation_id = c.id and cm.left_at is null
  where ((c.kind = 'group' and c.is_public = true and c.public_slug is not null)
      or (c.kind = 'channel' and ch.is_public = true))
    and (v_kind = 'all' or c.kind = v_kind)
    and (v_query = '' or c.title ilike '%' || v_query || '%'
      or (case when c.kind = 'channel' then ch.slug else c.public_slug end) ilike '%' || v_query || '%'
      or (case when c.kind = 'channel' then ch.description else c.description end) ilike '%' || v_query || '%')
  group by c.id, c.kind, c.title, c.created_at, ch.slug, ch.description, c.public_slug, c.description
  order by count(cm.user_id) desc, c.created_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 50)) offset greatest(coalesce(p_offset, 0), 0);
end;
$function$;

create or replace function private.update_group_discovery_settings_impl(
  p_conversation_id uuid, p_is_public boolean, p_slug text default null, p_description text default ''
) returns void language plpgsql security definer set search_path = ''
as $function$
declare v_actor uuid := (select auth.uid()); v_slug text := lower(btrim(coalesce(p_slug, '')));
begin
  if v_actor is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_is_public and v_slug !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'Public group username must be 3 to 32 characters' using errcode = '22023';
  end if;
  if char_length(coalesce(p_description, '')) > 500 then raise exception 'Description is too long' using errcode = '22023'; end if;
  update public.conversations c
  set is_public = coalesce(p_is_public, false),
      public_slug = case when coalesce(p_is_public, false) then v_slug else null end,
      description = btrim(coalesce(p_description, '')), updated_at = now()
  where c.id = p_conversation_id and c.kind = 'group'
    and exists (select 1 from public.conversation_members cm
      where cm.conversation_id = c.id and cm.user_id = v_actor and cm.left_at is null and cm.role = 'owner');
  if not found then raise exception 'Only the group owner can change public discovery settings' using errcode = '42501'; end if;
end;
$function$;

create or replace function public.create_public_group(
  p_title text, p_slug text, p_description text default '', p_member_ids uuid[] default '{}'::uuid[]
) returns uuid language sql set search_path = ''
as $$ select private.create_public_group_impl(p_title, p_slug, p_description, p_member_ids); $$;

create or replace function public.join_public_group(p_conversation_id uuid)
returns void language sql set search_path = ''
as $$ select private.join_public_group_impl(p_conversation_id); $$;

create or replace function public.search_public_communities(
  p_query text default '', p_kind text default 'all', p_limit integer default 30, p_offset integer default 0
)
returns table (
  conversation_id uuid, kind text, title text, slug text, description text,
  member_count bigint, is_member boolean, created_at timestamptz
)
language sql stable set search_path = ''
as $$ select * from private.search_public_communities_impl(p_query, p_kind, p_limit, p_offset); $$;

create or replace function public.update_group_discovery_settings(
  p_conversation_id uuid, p_is_public boolean, p_slug text default null, p_description text default ''
) returns void language sql set search_path = ''
as $$ select private.update_group_discovery_settings_impl(p_conversation_id, p_is_public, p_slug, p_description); $$;

grant usage on schema private to authenticated;
revoke all on function private.create_public_group_impl(text, text, text, uuid[]) from public, anon;
revoke all on function private.join_public_group_impl(uuid) from public, anon;
revoke all on function private.search_public_communities_impl(text, text, integer, integer) from public, anon;
revoke all on function private.update_group_discovery_settings_impl(uuid, boolean, text, text) from public, anon;
grant execute on function private.create_public_group_impl(text, text, text, uuid[]) to authenticated;
grant execute on function private.join_public_group_impl(uuid) to authenticated;
grant execute on function private.search_public_communities_impl(text, text, integer, integer) to authenticated;
grant execute on function private.update_group_discovery_settings_impl(uuid, boolean, text, text) to authenticated;

revoke all on function public.create_public_group(text, text, text, uuid[]) from public, anon;
revoke all on function public.join_public_group(uuid) from public, anon;
revoke all on function public.search_public_communities(text, text, integer, integer) from public, anon;
revoke all on function public.update_group_discovery_settings(uuid, boolean, text, text) from public, anon;
grant execute on function public.create_public_group(text, text, text, uuid[]) to authenticated;
grant execute on function public.join_public_group(uuid) to authenticated;
grant execute on function public.search_public_communities(text, text, integer, integer) to authenticated;
grant execute on function public.update_group_discovery_settings(uuid, boolean, text, text) to authenticated;
