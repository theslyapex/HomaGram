-- Ensure forwarded messages respect target group send rules and block relationships.
create or replace function public.forward_text_message(p_message_id uuid,p_target_conversation_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_source public.messages%rowtype;
  v_sender_name text;
  v_new_id uuid;
  v_allowed boolean;
  v_kind text;
  v_can_send boolean;
  v_role text;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not private.is_active_conversation_member(p_target_conversation_id) then raise exception 'Target conversation is unavailable' using errcode='42501'; end if;
  select c.kind,c.members_can_send_messages,cm.role into v_kind,v_can_send,v_role
    from public.conversations c join public.conversation_members cm on cm.conversation_id=c.id
   where c.id=p_target_conversation_id and cm.user_id=v_user and cm.left_at is null;
  if v_kind='group' and not coalesce(v_can_send,true) and coalesce(v_role,'member')='member' then
    raise exception 'Members cannot send messages in this group' using errcode='42501';
  end if;
  if exists (
    select 1 from public.conversation_members cm join public.user_blocks b on
      (b.blocker_id=cm.user_id and b.blocked_id=v_user) or (b.blocker_id=v_user and b.blocked_id=cm.user_id)
    where cm.conversation_id=p_target_conversation_id and cm.left_at is null and cm.user_id<>v_user
  ) then raise exception 'Messaging is unavailable in this conversation' using errcode='42501'; end if;
  select * into v_source from public.messages where id=p_message_id and deleted_at is null;
  if v_source.id is null or not private.is_active_conversation_member(v_source.conversation_id) then raise exception 'Source message is unavailable' using errcode='42501'; end if;
  if v_source.message_type <> 'text' then raise exception 'Only text messages can currently be forwarded' using errcode='22023'; end if;
  select coalesce(s.allow_message_forwarding,true) into v_allowed from public.account_settings s where s.user_id=v_source.sender_id;
  if not coalesce(v_allowed,true) then raise exception 'The sender has disabled message forwarding' using errcode='42501'; end if;
  select coalesce(p.display_name,p.username,'کاربر') into v_sender_name from public.profiles p where p.id=v_source.sender_id;
  insert into public.messages(conversation_id,sender_id,message_type,body,forwarded_from_sender_id,forwarded_from_display_name)
  values(p_target_conversation_id,v_user,'text',v_source.body,v_source.sender_id,coalesce(v_sender_name,'کاربر'))
  returning id into v_new_id;
  return v_new_id;
end;
$function$;