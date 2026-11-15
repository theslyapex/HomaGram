-- Permit the authorized delete RPC to tombstone another member's message.
-- Text edits remain sender-only and are limited to two hours.
create or replace function private.guard_message_updates()
returns trigger language plpgsql security invoker set search_path = ''
as $function$
begin
  if new.id is distinct from old.id or new.conversation_id is distinct from old.conversation_id
     or new.sender_id is distinct from old.sender_id or new.client_message_id is distinct from old.client_message_id
     or new.message_type is distinct from old.message_type or new.reply_to_id is distinct from old.reply_to_id
     or new.forwarded_from_message_id is distinct from old.forwarded_from_message_id
     or new.forwarded_from_sender_id is distinct from old.forwarded_from_sender_id
     or new.forwarded_from_display_name is distinct from old.forwarded_from_display_name
     or new.created_at is distinct from old.created_at then
    raise exception 'Message identity and routing fields are immutable' using errcode = '42501';
  end if;
  if old.deleted_at is not null then raise exception 'Deleted messages cannot be changed' using errcode = '42501'; end if;
  if new.body is distinct from old.body and new.deleted_at is null then
    if old.sender_id <> (select auth.uid()) then raise exception 'Only the sender can edit this message' using errcode = '42501'; end if;
    if old.created_at < now() - interval '2 hours' then raise exception 'Messages can only be edited within two hours' using errcode = '42501'; end if;
    if char_length(new.body) > 10000 then raise exception 'Message is too long' using errcode = '22023'; end if;
    new.edited_at := now();
  end if;
  if new.deleted_at is not null then
    new.deleted_at := coalesce(new.deleted_at, now()); new.body := '';
    new.deleted_by := coalesce(new.deleted_by, (select auth.uid()));
  end if;
  new.updated_at := now(); return new;
end;
$function$;