create or replace function private.manage_group_member_impl(
  p_conversation_id uuid,p_target_user uuid,p_action text
) returns void language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_actor_role text;
  v_target_role text;
  v_members_can_add boolean;
  v_admins_can_manage boolean;
  v_kind text;
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_target_user is null or p_target_user=v_actor then raise exception 'Invalid target member' using errcode='22023'; end if;
  select c.kind,cm.role,c.members_can_add_members,c.admins_can_manage_members
    into v_kind,v_actor_role,v_members_can_add,v_admins_can_manage
  from public.conversations c join public.conversation_members cm on cm.conversation_id=c.id
  where c.id=p_conversation_id and cm.user_id=v_actor and cm.left_at is null
  for update of c,cm;
  if not found or v_kind<>'group' then raise exception 'Group or active membership not found' using errcode='P0002'; end if;
  select role into v_target_role from public.conversation_members
  where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null for update;
  if p_action='add' then
    if v_target_role is not null then raise exception 'User is already an active member' using errcode='23505'; end if;
    if not exists(select 1 from auth.users where id=p_target_user) then raise exception 'User not found' using errcode='P0002'; end if;
    if not (v_actor_role='owner' or (v_actor_role='admin' and v_admins_can_manage)
      or (v_actor_role='member' and v_members_can_add)) then
      raise exception 'You cannot add members to this group' using errcode='42501';
    end if;
    insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
    values(p_conversation_id,p_target_user,'member',now(),null)
    on conflict(conversation_id,user_id) do update
      set role='member',joined_at=now(),left_at=null
      where public.conversation_members.left_at is not null;
  elsif p_action='remove' then
    if v_target_role is null then raise exception 'Member not found' using errcode='P0002'; end if;
    if not (v_actor_role='owner' or (v_actor_role='admin' and v_admins_can_manage and v_target_role='member')) then
      raise exception 'You cannot remove this member' using errcode='42501';
    end if;
    if v_target_role='owner' then raise exception 'The owner cannot be removed' using errcode='42501'; end if;
    update public.conversation_members set left_at=now()
    where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null;
  elsif p_action='promote' then
    if v_actor_role<>'owner' or v_target_role<>'member' then raise exception 'Only the owner can promote a regular member' using errcode='42501'; end if;
    update public.conversation_members set role='admin' where conversation_id=p_conversation_id and user_id=p_target_user;
  elsif p_action='demote' then
    if v_actor_role<>'owner' or v_target_role<>'admin' then raise exception 'Only the owner can demote an administrator' using errcode='42501'; end if;
    update public.conversation_members set role='member' where conversation_id=p_conversation_id and user_id=p_target_user;
  else
    raise exception 'Unsupported group action' using errcode='22023';
  end if;
end;
$$;

create or replace function private.join_group_by_invite_impl(p_token text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_invite public.channel_invites%rowtype;
  v_hash text;
  v_existing_left_at timestamptz;
  v_existing boolean;
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_token is null or p_token !~ '^[0-9a-fA-F]{64}$' then raise exception 'Invalid invite code' using errcode='22023'; end if;
  v_hash:=encode(extensions.digest(convert_to(lower(p_token),'UTF8'),'sha256'),'hex');
  select * into v_invite from public.channel_invites where token_hash=v_hash for update;
  if not found or v_invite.revoked_at is not null or v_invite.expires_at<=now()
    or v_invite.use_count>=v_invite.max_uses
    or not exists(select 1 from public.conversations c where c.id=v_invite.conversation_id and c.kind='group') then
    raise exception 'Invite code is invalid or expired' using errcode='22023';
  end if;
  select left_at into v_existing_left_at from public.conversation_members
  where conversation_id=v_invite.conversation_id and user_id=v_actor for update;
  v_existing:=found;
  if v_existing and v_existing_left_at is null then return v_invite.conversation_id; end if;
  insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
  values(v_invite.conversation_id,v_actor,'member',now(),null)
  on conflict(conversation_id,user_id) do update
    set role='member',joined_at=now(),left_at=null
    where public.conversation_members.left_at is not null;
  update public.channel_invites set use_count=use_count+1 where id=v_invite.id;
  return v_invite.conversation_id;
end;
$$;

create or replace function private.update_conversation_photo_impl(p_conversation_id uuid,p_photo_path text)
returns void language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_kind text;
  v_role text;
  v_admins_can_change boolean;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_photo_path is not null and (
    split_part(p_photo_path,'/',1)<>p_conversation_id::text
    or split_part(p_photo_path,'/',2)<>v_uid::text
    or split_part(p_photo_path,'/',3)=''
    or p_photo_path like '%..%'
  ) then raise exception 'Invalid conversation photo path' using errcode='22023'; end if;
  select c.kind,cm.role,c.admins_can_change_info into v_kind,v_role,v_admins_can_change
  from public.conversations c join public.conversation_members cm on cm.conversation_id=c.id
  where c.id=p_conversation_id and cm.user_id=v_uid and cm.left_at is null;
  if not found then raise exception 'Active membership not found' using errcode='42501'; end if;
  if v_kind='group' and not (v_role='owner' or (v_role='admin' and v_admins_can_change)) then
    raise exception 'Only authorized group managers can change the photo' using errcode='42501';
  end if;
  if v_kind<>'group' and v_role not in ('owner','admin') then
    raise exception 'Only conversation owners and admins can change the photo' using errcode='42501';
  end if;
  update public.conversations set photo_path=p_photo_path,updated_at=now() where id=p_conversation_id;
end;
$$;

create or replace function public.update_conversation_photo(p_conversation_id uuid,p_photo_path text)
returns void language sql set search_path=''
as $$ select private.update_conversation_photo_impl(p_conversation_id,p_photo_path); $$;
revoke all on function public.update_conversation_photo(uuid,text) from public,anon;
grant execute on function public.update_conversation_photo(uuid,text) to authenticated;
grant execute on function private.update_conversation_photo_impl(uuid,text) to authenticated;
grant execute on function private.manage_group_member_impl(uuid,uuid,text) to authenticated;
grant execute on function private.join_group_by_invite_impl(text) to authenticated;