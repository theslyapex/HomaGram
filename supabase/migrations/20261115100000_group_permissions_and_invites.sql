alter table public.conversations
  add column if not exists members_can_send_messages boolean not null default true,
  add column if not exists members_can_send_media boolean not null default true,
  add column if not exists members_can_add_members boolean not null default false,
  add column if not exists admins_can_change_info boolean not null default true,
  add column if not exists admins_can_manage_members boolean not null default true;

create or replace function private.manage_group_member_impl(
  p_conversation_id uuid, p_target_user uuid, p_action text
) returns void
language plpgsql security definer set search_path = ''
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
  if p_target_user is null or p_target_user = v_actor then raise exception 'Invalid target member' using errcode='22023'; end if;
  select c.kind, cm.role, c.members_can_add_members, c.admins_can_manage_members
    into v_kind, v_actor_role, v_members_can_add, v_admins_can_manage
  from public.conversations c
  join public.conversation_members cm on cm.conversation_id=c.id
  where c.id=p_conversation_id and cm.user_id=v_actor and cm.left_at is null
  for update of c, cm;
  if not found or v_kind <> 'group' then raise exception 'Group or active membership not found' using errcode='P0002'; end if;
  select role into v_target_role from public.conversation_members
  where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null for update;
  if p_action='add' then
    if not exists(select 1 from auth.users where id=p_target_user) then raise exception 'User not found' using errcode='P0002'; end if;
    if not (v_actor_role='owner' or (v_actor_role='admin' and v_admins_can_manage) or (v_actor_role='member' and v_members_can_add)) then
      raise exception 'You cannot add members to this group' using errcode='42501';
    end if;
    insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
    values(p_conversation_id,p_target_user,'member',now(),null)
    on conflict(conversation_id,user_id) do update set role='member',joined_at=now(),left_at=null;
  elsif p_action='remove' then
    if v_target_role is null then raise exception 'Member not found' using errcode='P0002'; end if;
    if not (v_actor_role='owner' or (v_actor_role='admin' and v_admins_can_manage and v_target_role='member')) then
      raise exception 'You cannot remove this member' using errcode='42501';
    end if;
    if v_target_role='owner' then raise exception 'The owner cannot be removed' using errcode='42501'; end if;
    update public.conversation_members set left_at=now()
    where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null;
  elsif p_action='promote' then
    if v_actor_role <> 'owner' or v_target_role <> 'member' then raise exception 'Only the owner can promote a regular member' using errcode='42501'; end if;
    update public.conversation_members set role='admin' where conversation_id=p_conversation_id and user_id=p_target_user;
  elsif p_action='demote' then
    if v_actor_role <> 'owner' or v_target_role <> 'admin' then raise exception 'Only the owner can demote an administrator' using errcode='42501'; end if;
    update public.conversation_members set role='member' where conversation_id=p_conversation_id and user_id=p_target_user;
  else
    raise exception 'Unsupported group action' using errcode='22023';
  end if;
end;
$$;

create or replace function private.update_group_permissions_impl(
  p_conversation_id uuid,p_members_can_send_messages boolean,p_members_can_send_media boolean,
  p_members_can_add_members boolean,p_admins_can_change_info boolean,p_admins_can_manage_members boolean
) returns void language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  update public.conversations c
  set members_can_send_messages=coalesce(p_members_can_send_messages,true),
      members_can_send_media=coalesce(p_members_can_send_media,true),
      members_can_add_members=coalesce(p_members_can_add_members,false),
      admins_can_change_info=coalesce(p_admins_can_change_info,true),
      admins_can_manage_members=coalesce(p_admins_can_manage_members,true),
      updated_at=now()
  where c.id=p_conversation_id and c.kind='group'
    and exists(select 1 from public.conversation_members cm where cm.conversation_id=c.id
      and cm.user_id=v_actor and cm.left_at is null and cm.role='owner');
  if not found then raise exception 'Only the group owner can change permissions' using errcode='42501'; end if;
end;
$$;

create or replace function private.create_group_invite_impl(
  p_conversation_id uuid,p_expires_in_hours integer default 168,p_max_uses integer default 100
) returns text language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid()); v_token text;
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_expires_in_hours not between 1 and 720 then raise exception 'Invite expiry must be between 1 and 720 hours' using errcode='22023'; end if;
  if p_max_uses not between 1 and 500 then raise exception 'Invite use limit must be between 1 and 500' using errcode='22023'; end if;
  if not exists(select 1 from public.conversation_members m join public.conversations c on c.id=m.conversation_id
    where m.conversation_id=p_conversation_id and m.user_id=v_actor and m.left_at is null
      and (m.role='owner' or (m.role='admin' and c.admins_can_manage_members)) and c.kind='group') then
    raise exception 'Only authorized group managers can create invites' using errcode='42501';
  end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.channel_invites(conversation_id,token_hash,created_by,expires_at,max_uses)
  values(p_conversation_id,encode(extensions.digest(convert_to(lower(v_token),'UTF8'),'sha256'),'hex'),
    v_actor,now()+make_interval(hours=>p_expires_in_hours),p_max_uses);
  return v_token;
end;
$$;

create or replace function private.list_group_invites_impl(p_conversation_id uuid)
returns table(id uuid,created_at timestamptz,expires_at timestamptz,max_uses integer,use_count integer,revoked_at timestamptz,invite_status text)
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not exists(select 1 from public.conversation_members m join public.conversations c on c.id=m.conversation_id
    where m.conversation_id=p_conversation_id and m.user_id=v_actor and m.left_at is null
      and (m.role='owner' or (m.role='admin' and c.admins_can_manage_members)) and c.kind='group') then
    raise exception 'Not permitted to view group invites' using errcode='42501';
  end if;
  return query select i.id,i.created_at,i.expires_at,i.max_uses,i.use_count,i.revoked_at,
    case when i.revoked_at is not null then 'revoked' when i.expires_at<=now() then 'expired'
      when i.use_count>=i.max_uses then 'exhausted' else 'active' end
  from public.channel_invites i where i.conversation_id=p_conversation_id order by i.created_at desc limit 50;
end;
$$;

create or replace function private.revoke_group_invite_impl(p_invite_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  update public.channel_invites i set revoked_at=now()
  where i.id=p_invite_id and i.revoked_at is null
    and exists(select 1 from public.conversation_members m join public.conversations c on c.id=m.conversation_id
      where m.conversation_id=i.conversation_id and m.user_id=v_actor and m.left_at is null
        and (m.role='owner' or (m.role='admin' and c.admins_can_manage_members)) and c.kind='group');
  if not found then raise exception 'Invite not found or permission denied' using errcode='42501'; end if;
end;
$$;

create or replace function private.join_group_by_invite_impl(p_token text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid()); v_invite public.channel_invites%rowtype; v_hash text;
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
  insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
  values(v_invite.conversation_id,v_actor,'member',now(),null)
  on conflict(conversation_id,user_id) do update set role='member',joined_at=now(),left_at=null;
  update public.channel_invites set use_count=use_count+1 where id=v_invite.id;
  return v_invite.conversation_id;
end;
$$;

create or replace function private.update_group_details_impl(p_conversation_id uuid,p_title text,p_description text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then raise exception 'Title must contain 1 to 100 characters' using errcode='22023'; end if;
  if char_length(coalesce(p_description,''))>500 then raise exception 'Description is too long' using errcode='22023'; end if;
  update public.conversations c set title=btrim(p_title),description=btrim(coalesce(p_description,'')),updated_at=now()
  where c.id=p_conversation_id and c.kind='group'
    and exists(select 1 from public.conversation_members cm where cm.conversation_id=c.id and cm.user_id=v_actor
      and cm.left_at is null and (cm.role='owner' or (cm.role='admin' and c.admins_can_change_info)));
  if not found then raise exception 'Not permitted or group not found' using errcode='42501'; end if;
end;
$$;

create or replace function public.update_group_permissions(
  p_conversation_id uuid,p_members_can_send_messages boolean,p_members_can_send_media boolean,
  p_members_can_add_members boolean,p_admins_can_change_info boolean,p_admins_can_manage_members boolean
) returns void language sql set search_path=''
as $$ select private.update_group_permissions_impl(p_conversation_id,p_members_can_send_messages,
  p_members_can_send_media,p_members_can_add_members,p_admins_can_change_info,p_admins_can_manage_members); $$;
create or replace function public.create_group_invite(p_conversation_id uuid,p_expires_in_hours integer default 168,p_max_uses integer default 100)
returns text language sql set search_path='' as $$ select private.create_group_invite_impl(p_conversation_id,p_expires_in_hours,p_max_uses); $$;
create or replace function public.list_group_invites(p_conversation_id uuid)
returns table(id uuid,created_at timestamptz,expires_at timestamptz,max_uses integer,use_count integer,revoked_at timestamptz,invite_status text)
language sql set search_path='' as $$ select * from private.list_group_invites_impl(p_conversation_id); $$;
create or replace function public.revoke_group_invite(p_invite_id uuid)
returns void language sql set search_path='' as $$ select private.revoke_group_invite_impl(p_invite_id); $$;
create or replace function public.join_group_by_invite(p_token text)
returns uuid language sql set search_path='' as $$ select private.join_group_by_invite_impl(p_token); $$;
create or replace function public.update_group_details(p_conversation_id uuid,p_title text,p_description text)
returns void language sql set search_path='' as $$ select private.update_group_details_impl(p_conversation_id,p_title,p_description); $$;

drop policy if exists "Active members can send messages as themselves" on public.messages;
create policy "Active members can send messages as themselves" on public.messages
for insert to authenticated with check (
  sender_id=(select auth.uid()) and message_type<>'system'
  and exists(select 1 from public.conversation_members cm where cm.conversation_id=messages.conversation_id
    and cm.user_id=(select auth.uid()) and cm.left_at is null)
  and (
    not exists(select 1 from public.conversations c where c.id=messages.conversation_id and c.kind='channel')
    or exists(select 1 from public.conversation_members cm join public.channels ch on ch.conversation_id=cm.conversation_id
      where cm.conversation_id=messages.conversation_id and cm.user_id=(select auth.uid()) and cm.left_at is null
        and (cm.role in ('owner','admin')
          or ((messages.message_type=any(array['image','video','audio','file'])) and ch.members_can_send_media)
          or ((messages.message_type<>all(array['image','video','audio','file'])) and ch.members_can_post)))
  )
  and (
    not exists(select 1 from public.conversations c where c.id=messages.conversation_id and c.kind='group')
    or exists(select 1 from public.conversation_members cm join public.conversations c on c.id=cm.conversation_id
      where cm.conversation_id=messages.conversation_id and cm.user_id=(select auth.uid()) and cm.left_at is null
        and (cm.role in ('owner','admin')
          or ((messages.message_type=any(array['image','video','audio','file'])) and c.members_can_send_media)
          or ((messages.message_type<>all(array['image','video','audio','file'])) and c.members_can_send_messages)))
  )
  and not exists(select 1 from public.conversation_members cm join public.user_blocks b on
    ((b.blocker_id=cm.user_id and b.blocked_id=(select auth.uid()))
     or (b.blocker_id=(select auth.uid()) and b.blocked_id=cm.user_id))
    where cm.conversation_id=messages.conversation_id and cm.left_at is null and cm.user_id<>(select auth.uid()))
);

revoke all on function public.update_group_permissions(uuid,boolean,boolean,boolean,boolean,boolean) from public,anon;
revoke all on function public.create_group_invite(uuid,integer,integer) from public,anon;
revoke all on function public.list_group_invites(uuid) from public,anon;
revoke all on function public.revoke_group_invite(uuid) from public,anon;
revoke all on function public.join_group_by_invite(text) from public,anon;
grant execute on function public.update_group_permissions(uuid,boolean,boolean,boolean,boolean,boolean) to authenticated;
grant execute on function public.create_group_invite(uuid,integer,integer) to authenticated;
grant execute on function public.list_group_invites(uuid) to authenticated;
grant execute on function public.revoke_group_invite(uuid) to authenticated;
grant execute on function public.join_group_by_invite(text) to authenticated;
grant execute on function private.update_group_permissions_impl(uuid,boolean,boolean,boolean,boolean,boolean) to authenticated;
grant execute on function private.create_group_invite_impl(uuid,integer,integer) to authenticated;
grant execute on function private.list_group_invites_impl(uuid) to authenticated;
grant execute on function private.revoke_group_invite_impl(uuid) to authenticated;
grant execute on function private.join_group_by_invite_impl(text) to authenticated;
grant execute on function private.manage_group_member_impl(uuid,uuid,text) to authenticated;
grant execute on function private.update_group_details_impl(uuid,text,text) to authenticated;
