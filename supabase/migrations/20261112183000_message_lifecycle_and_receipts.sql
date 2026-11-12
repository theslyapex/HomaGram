-- Message lifecycle hardening, delivery receipts and reaction realtime.

create or replace function private.guard_message_updates()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
     or new.conversation_id is distinct from old.conversation_id
     or new.sender_id is distinct from old.sender_id
     or new.client_message_id is distinct from old.client_message_id
     or new.message_type is distinct from old.message_type
     or new.reply_to_id is distinct from old.reply_to_id
     or new.forwarded_from_message_id is distinct from old.forwarded_from_message_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Message identity and routing fields are immutable'
      using errcode = '42501';
  end if;

  if old.deleted_at is not null then
    raise exception 'Deleted messages cannot be changed'
      using errcode = '42501';
  end if;

  if new.body is distinct from old.body then
    if char_length(new.body) > 10000 then
      raise exception 'Message is too long' using errcode = '22023';
    end if;
    new.edited_at := now();
  end if;

  if new.deleted_at is not null then
    new.deleted_at := coalesce(new.deleted_at, now());
    new.body := '';
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function private.guard_message_updates() from public, anon, authenticated;

drop trigger if exists messages_guard_updates on public.messages;
create trigger messages_guard_updates
before update on public.messages
for each row execute function private.guard_message_updates();

create or replace function private.create_message_receipts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.message_receipts(message_id, user_id, delivered_at, read_at)
  select new.id, cm.user_id, now(),
         case when cm.user_id = new.sender_id then now() else null end
  from public.conversation_members cm
  where cm.conversation_id = new.conversation_id
    and cm.left_at is null
  on conflict (message_id, user_id) do nothing;

  return new;
end;
$function$;

revoke all on function private.create_message_receipts() from public, anon, authenticated;

drop trigger if exists messages_create_receipts on public.messages;
create trigger messages_create_receipts
after insert on public.messages
for each row execute function private.create_message_receipts();

create or replace function private.guard_receipt_updates()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.message_id is distinct from old.message_id
     or new.user_id is distinct from old.user_id
     or new.delivered_at is distinct from old.delivered_at then
    raise exception 'Receipt identity and delivery time are immutable'
      using errcode = '42501';
  end if;
  if old.read_at is not null and new.read_at is distinct from old.read_at then
    raise exception 'Read receipt cannot be reverted'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_receipt_updates() from public, anon, authenticated;

drop trigger if exists message_receipts_guard_updates on public.message_receipts;
create trigger message_receipts_guard_updates
before update on public.message_receipts
for each row execute function private.guard_receipt_updates();

do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='message_receipts'
  ) then
    alter publication supabase_realtime add table public.message_receipts;
  end if;
end;
$publication$;
