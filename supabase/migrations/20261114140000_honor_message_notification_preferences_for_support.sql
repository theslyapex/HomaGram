-- Keep support-message notifications consistent with the user's message preference.
-- The conversation activity timestamp is still updated even when notifications are disabled.

create or replace function private.handle_support_message_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner_id uuid;
  v_admin_id uuid;
  v_type text;
  v_message text;
  v_recipient uuid;
  v_messages_enabled boolean;
begin
  select sc.user_id into v_owner_id
  from public.support_conversations sc
  where sc.id = new.conversation_id;

  select u.id into v_admin_id
  from auth.users u
  where lower(u.email) = 'theslyapex@gmail.com'
    and u.email_confirmed_at is not null
  limit 1;

  if v_admin_id is null then
    return new;
  end if;

  if new.sender_id = v_admin_id then
    v_recipient := v_owner_id;
    v_type := 'support_reply';
    v_message := 'تیم پشتیبانی هماگرام به درخواست شما پاسخ داد.';
  else
    v_recipient := v_admin_id;
    v_type := 'support_message';
    v_message := 'پیام پشتیبانی جدیدی دریافت شد.';
  end if;

  if v_recipient is not null and v_recipient <> new.sender_id then
    select coalesce(
      (select p.messages_enabled
       from public.user_notification_preferences p
       where p.user_id = v_recipient),
      true
    ) into v_messages_enabled;

    if v_messages_enabled then
      insert into public.notifications
        (recipient_id, actor_id, type, entity_id, entity_type, message)
      values
        (v_recipient, new.sender_id, v_type, new.conversation_id, 'support', v_message);
    end if;
  end if;

  update public.support_conversations
  set last_message_at = new.created_at,
      updated_at = now()
  where id = new.conversation_id;

  return new;
end;
$function$;

revoke all on function private.handle_support_message_notification() from public, anon, authenticated;
