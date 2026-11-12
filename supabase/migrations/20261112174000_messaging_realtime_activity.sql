-- Enable authenticated inbox/chat updates through Supabase Postgres Changes.
alter table public.messages
  alter column client_message_id set default gen_random_uuid();

create or replace function private.bump_conversation_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.conversations
  set updated_at = now()
  where id = new.conversation_id;
  return new;
end;
$function$;

revoke all on function private.bump_conversation_activity() from public, anon, authenticated;

drop trigger if exists messages_bump_conversation_activity on public.messages;
create trigger messages_bump_conversation_activity
after insert or update of body, edited_at, deleted_at
on public.messages
for each row execute function private.bump_conversation_activity();

do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'conversation_members'
  ) then
    alter publication supabase_realtime add table public.conversation_members;
  end if;
end;
$publication$;
