-- In direct chats, either participant may remove a message for everyone.
-- In groups and channels, removal of another member's message remains admin-only.
create or replace function public.delete_conversation_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid := (select auth.uid()); v_conversation uuid; v_sender uuid; v_role text; v_kind text;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select m.conversation_id,m.sender_id,c.kind into v_conversation,v_sender,v_kind
    from public.messages m join public.conversations c on c.id=m.conversation_id
   where m.id=p_message_id and m.deleted_at is null;
  if v_conversation is null or not private.is_active_conversation_member(v_conversation) then
    raise exception 'Message not found' using errcode='42501';
  end if;
  select role into v_role from public.conversation_members
    where conversation_id=v_conversation and user_id=v_user and left_at is null;
  if v_sender <> v_user and v_kind <> 'direct' and coalesce(v_role,'member') not in ('owner','admin') then
    raise exception 'Only the sender or a group/channel admin can delete this message' using errcode='42501';
  end if;
  update public.messages set deleted_at=now(), deleted_by=v_user, body='' where id=p_message_id;
end;
$function$;