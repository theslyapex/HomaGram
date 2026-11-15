-- Allow a user to have a new support conversation after an administrator closes the previous one.
-- Keep at most one open conversation per user; retain all closed conversations for history.

alter table public.support_conversations
  drop constraint if exists support_conversations_user_id_key;

create unique index if not exists support_conversations_one_open_per_user_idx
  on public.support_conversations(user_id)
  where status = 'open';

create or replace function private.get_or_create_support_conversation()
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_conversation_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  select sc.id into v_conversation_id
  from public.support_conversations sc
  where sc.user_id = v_user_id
    and sc.status = 'open'
  order by sc.created_at desc
  limit 1;

  if v_conversation_id is null then
    insert into public.support_conversations(user_id, status)
    values (v_user_id, 'open')
    returning id into v_conversation_id;
  end if;

  return v_conversation_id;
end;
$function$;

revoke all on function private.get_or_create_support_conversation() from public, anon;
grant execute on function private.get_or_create_support_conversation() to authenticated;
