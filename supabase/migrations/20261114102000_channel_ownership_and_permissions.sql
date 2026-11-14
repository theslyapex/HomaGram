alter table public.channels
  add column if not exists members_can_post boolean not null default true,
  add column if not exists members_can_send_media boolean not null default true;

create unique index if not exists conversation_members_one_active_channel_owner
  on public.conversation_members(conversation_id)
  where role = 'owner' and left_at is null;

drop policy if exists "Active members can send messages as themselves" on public.messages;

create policy "Active members can send messages as themselves"
on public.messages
for insert
to authenticated
with check (
  sender_id = (select auth.uid())
  and message_type <> 'system'
  and exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = messages.conversation_id
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
  )
  and (
    not exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id and c.kind = 'channel'
    )
    or exists (
      select 1
      from public.conversation_members cm
      join public.channels ch on ch.conversation_id = cm.conversation_id
      where cm.conversation_id = messages.conversation_id
        and cm.user_id = (select auth.uid())
        and cm.left_at is null
        and (
          cm.role in ('owner','admin')
          or (
            (messages.message_type in ('image','video','audio','file') and ch.members_can_send_media)
            or
            (messages.message_type not in ('image','video','audio','file') and ch.members_can_post)
          )
        )
    )
  )
  and not exists (
    select 1
    from public.conversation_members cm
    join public.user_blocks b
      on (
        (b.blocker_id = cm.user_id and b.blocked_id = (select auth.uid()))
        or
        (b.blocker_id = (select auth.uid()) and b.blocked_id = cm.user_id)
      )
    where cm.conversation_id = messages.conversation_id
      and cm.left_at is null
      and cm.user_id <> (select auth.uid())
  )
);

create or replace function private.update_channel_member_permissions_impl(
  p_conversation_id uuid,
  p_members_can_post boolean,
  p_members_can_send_media boolean
) returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;
  if p_members_can_post is null or p_members_can_send_media is null then
    raise exception 'Permission values are required' using errcode='22023';
  end if;

  if not exists (
    select 1
    from public.conversation_members cm
    join public.channels ch on ch.conversation_id = cm.conversation_id
    where cm.conversation_id = p_conversation_id
      and cm.user_id = v_actor
      and cm.left_at is null
      and cm.role in ('owner','admin')
  ) then
    raise exception 'Only channel managers can change member permissions' using errcode='42501';
  end if;

  update public.channels
  set members_can_post = p_members_can_post,
      members_can_send_media = p_members_can_send_media
  where conversation_id = p_conversation_id;
end;
$function$;

create or replace function public.update_channel_member_permissions(
  p_conversation_id uuid,
  p_members_can_post boolean,
  p_members_can_send_media boolean
) returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.update_channel_member_permissions_impl(
    p_conversation_id, p_members_can_post, p_members_can_send_media
  );
$function$;

create or replace function private.transfer_channel_ownership_impl(
  p_conversation_id uuid,
  p_new_owner uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_actor_role text;
  v_target_role text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;
  if p_new_owner is null or p_new_owner = v_actor then
    raise exception 'Choose another active channel member' using errcode='22023';
  end if;

  select cm.role into v_actor_role
  from public.conversation_members cm
  join public.conversations c on c.id = cm.conversation_id
  where cm.conversation_id = p_conversation_id
    and cm.user_id = v_actor
    and cm.left_at is null
    and c.kind = 'channel'
  for update of cm;

  if not found or v_actor_role <> 'owner' then
    raise exception 'Only the current channel owner can transfer ownership' using errcode='42501';
  end if;

  select cm.role into v_target_role
  from public.conversation_members cm
  where cm.conversation_id = p_conversation_id
    and cm.user_id = p_new_owner
    and cm.left_at is null
  for update;

  if not found or v_target_role not in ('member','admin') then
    raise exception 'New owner must be an active member or administrator' using errcode='22023';
  end if;

  update public.conversation_members
  set role = 'admin'
  where conversation_id = p_conversation_id
    and user_id = v_actor
    and left_at is null
    and role = 'owner';

  update public.conversation_members
  set role = 'owner'
  where conversation_id = p_conversation_id
    and user_id = p_new_owner
    and left_at is null;

  update public.conversations
  set created_by = p_new_owner,
      updated_at = now()
  where id = p_conversation_id
    and kind = 'channel';
end;
$function$;

create or replace function public.transfer_channel_ownership(
  p_conversation_id uuid,
  p_new_owner uuid
) returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.transfer_channel_ownership_impl(p_conversation_id, p_new_owner);
$function$;

revoke all on function private.update_channel_member_permissions_impl(uuid,boolean,boolean) from public, anon, authenticated;
revoke all on function private.transfer_channel_ownership_impl(uuid,uuid) from public, anon, authenticated;
grant execute on function private.update_channel_member_permissions_impl(uuid,boolean,boolean) to authenticated;
grant execute on function private.transfer_channel_ownership_impl(uuid,uuid) to authenticated;

revoke all on function public.update_channel_member_permissions(uuid,boolean,boolean) from public, anon;
revoke all on function public.transfer_channel_ownership(uuid,uuid) from public, anon;
grant execute on function public.update_channel_member_permissions(uuid,boolean,boolean) to authenticated;
grant execute on function public.transfer_channel_ownership(uuid,uuid) to authenticated;
