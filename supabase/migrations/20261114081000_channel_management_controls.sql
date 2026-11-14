-- Channel owner/admin controls, kept behind private SECURITY DEFINER implementations.
create or replace function private.manage_channel_member_impl(
  p_conversation_id uuid, p_target_user uuid, p_action text
) returns void
language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_actor_role text;
  v_target_role text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;
  if p_target_user is null or p_target_user = v_actor then
    raise exception 'Invalid target member' using errcode='22023';
  end if;

  select cm.role into v_actor_role
  from public.conversation_members cm
  join public.conversations c on c.id = cm.conversation_id
  join public.channels ch on ch.conversation_id = c.id
  where cm.conversation_id = p_conversation_id
    and cm.user_id = v_actor and cm.left_at is null
  for update of cm;

  if not found then
    raise exception 'Channel manager membership not found' using errcode='P0002';
  end if;

  select role into v_target_role
  from public.conversation_members
  where conversation_id = p_conversation_id
    and user_id = p_target_user and left_at is null
  for update;

  if p_action = 'add' then
    if v_actor_role not in ('owner','admin') then
      raise exception 'Only channel managers can add members' using errcode='42501';
    end if;
    if not exists (select 1 from auth.users where id = p_target_user) then
      raise exception 'User not found' using errcode='P0002';
    end if;
    insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
    values (p_conversation_id,p_target_user,'member',now(),null)
    on conflict (conversation_id,user_id)
    do update set role='member',joined_at=now(),left_at=null;
  elsif p_action = 'remove' then
    if v_actor_role not in ('owner','admin') or v_target_role is null then
      raise exception 'Not permitted or member not found' using errcode='42501';
    end if;
    if v_target_role = 'owner' or (v_actor_role = 'admin' and v_target_role = 'admin') then
      raise exception 'Cannot remove this channel manager' using errcode='42501';
    end if;
    update public.conversation_members set left_at=now()
    where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null;
  elsif p_action = 'promote' then
    if v_actor_role <> 'owner' or v_target_role <> 'member' then
      raise exception 'Only the owner can promote a regular member' using errcode='42501';
    end if;
    update public.conversation_members set role='admin'
    where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null;
  elsif p_action = 'demote' then
    if v_actor_role <> 'owner' or v_target_role <> 'admin' then
      raise exception 'Only the owner can demote an administrator' using errcode='42501';
    end if;
    update public.conversation_members set role='member'
    where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null;
  else
    raise exception 'Unsupported channel action' using errcode='22023';
  end if;
end;
$function$;

create or replace function private.update_channel_details_impl(
  p_conversation_id uuid, p_title text, p_slug text, p_description text
) returns void
language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_slug text := lower(btrim(coalesce(p_slug,'')));
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception 'Title must contain 1 to 100 characters' using errcode='22023';
  end if;
  if v_slug !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'Channel username must be 3 to 32 characters' using errcode='22023';
  end if;
  if char_length(coalesce(p_description,'')) > 500 then
    raise exception 'Description is too long' using errcode='22023';
  end if;

  update public.conversations c
  set title=btrim(p_title), updated_at=now()
  where c.id=p_conversation_id and c.kind='channel'
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id=c.id and cm.user_id=v_actor
        and cm.left_at is null and cm.role in ('owner','admin')
    );
  if not found then
    raise exception 'Not permitted or channel not found' using errcode='42501';
  end if;

  update public.channels
  set slug=v_slug, description=btrim(coalesce(p_description,''))
  where conversation_id=p_conversation_id;
end;
$function$;

create or replace function public.manage_channel_member(
  p_conversation_id uuid, p_target_user uuid, p_action text
) returns void language sql set search_path = ''
as $function$
  select private.manage_channel_member_impl(p_conversation_id,p_target_user,p_action);
$function$;

create or replace function public.update_channel_details(
  p_conversation_id uuid, p_title text, p_slug text, p_description text
) returns void language sql set search_path = ''
as $function$
  select private.update_channel_details_impl(p_conversation_id,p_title,p_slug,p_description);
$function$;

revoke all on function public.manage_channel_member(uuid,uuid,text) from public, anon;
revoke all on function public.update_channel_details(uuid,text,text,text) from public, anon;
grant execute on function public.manage_channel_member(uuid,uuid,text) to authenticated;
grant execute on function public.update_channel_details(uuid,text,text,text) to authenticated;
