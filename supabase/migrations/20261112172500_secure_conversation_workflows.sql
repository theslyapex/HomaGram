-- Secure conversation creation and membership lifecycle.
-- All writes happen through authenticated, narrowly-scoped RPC functions.

alter table public.conversations
  add column if not exists direct_key text;

create unique index if not exists conversations_direct_key_uidx
  on public.conversations(direct_key)
  where direct_key is not null;

create or replace function public.create_direct_conversation(p_target_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_key text;
  v_conversation_id uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_target_user is null or p_target_user = v_actor then
    raise exception 'Invalid target user' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_target_user) then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = v_actor and b.blocked_id = p_target_user)
       or (b.blocker_id = p_target_user and b.blocked_id = v_actor)
  ) then
    raise exception 'This conversation is unavailable' using errcode = '42501';
  end if;

  v_key := least(v_actor, p_target_user)::text || ':' ||
           greatest(v_actor, p_target_user)::text;

  insert into public.conversations(kind, created_by, direct_key)
  values ('direct', v_actor, v_key)
  on conflict (direct_key) where direct_key is not null
  do update set updated_at = public.conversations.updated_at
  returning id into v_conversation_id;

  insert into public.conversation_members(conversation_id, user_id, role)
  values (v_conversation_id, v_actor, 'member'),
         (v_conversation_id, p_target_user, 'member')
  on conflict (conversation_id, user_id)
  do update set left_at = null, joined_at = case
    when public.conversation_members.left_at is null
      then public.conversation_members.joined_at
    else now()
  end;

  return v_conversation_id;
end;
$function$;

create or replace function public.create_group_conversation(
  p_title text,
  p_member_ids uuid[] default '{}'::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_members uuid[];
  v_count integer;
  v_conversation_id uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception 'Group title must contain 1 to 100 characters' using errcode = '22023';
  end if;

  select coalesce(array_agg(x order by x), '{}'::uuid[])
    into v_members
  from (
    select distinct member_id as x
    from unnest(coalesce(p_member_ids, '{}'::uuid[])) as member_id
    where member_id is not null and member_id <> v_actor
  ) members;

  v_count := coalesce(array_length(v_members, 1), 0);
  if v_count > 99 then
    raise exception 'A group can include at most 100 people at creation' using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(v_members) requested(user_id)
    left join auth.users u on u.id = requested.user_id
    where u.id is null
  ) then
    raise exception 'One or more selected users do not exist' using errcode = '22023';
  end if;

  insert into public.conversations(kind, title, created_by)
  values ('group', btrim(p_title), v_actor)
  returning id into v_conversation_id;

  insert into public.conversation_members(conversation_id, user_id, role)
  values (v_conversation_id, v_actor, 'owner');

  if v_count > 0 then
    insert into public.conversation_members(conversation_id, user_id, role)
    select v_conversation_id, member_id, 'member'
    from unnest(v_members) as member_id;
  end if;

  return v_conversation_id;
end;
$function$;

create or replace function public.leave_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_role text;
  v_next_owner uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select cm.role into v_role
  from public.conversation_members cm
  where cm.conversation_id = p_conversation_id
    and cm.user_id = v_actor
    and cm.left_at is null
  for update;

  if not found then
    raise exception 'Active membership not found' using errcode = 'P0002';
  end if;

  if v_role = 'owner' then
    select cm.user_id into v_next_owner
    from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.user_id <> v_actor
      and cm.left_at is null
    order by case cm.role when 'admin' then 0 else 1 end, cm.joined_at, cm.user_id
    limit 1;

    if v_next_owner is not null then
      update public.conversation_members
      set role = 'owner'
      where conversation_id = p_conversation_id and user_id = v_next_owner;
    end if;
  end if;

  update public.conversation_members
  set left_at = now()
  where conversation_id = p_conversation_id
    and user_id = v_actor
    and left_at is null;
end;
$function$;

revoke all on function public.create_direct_conversation(uuid) from public, anon;
revoke all on function public.create_group_conversation(text, uuid[]) from public, anon;
revoke all on function public.leave_conversation(uuid) from public, anon;
grant execute on function public.create_direct_conversation(uuid) to authenticated;
grant execute on function public.create_group_conversation(text, uuid[]) to authenticated;
grant execute on function public.leave_conversation(uuid) to authenticated;
