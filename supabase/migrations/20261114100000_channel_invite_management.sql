create or replace function private.list_channel_invites_impl(p_conversation_id uuid)
returns table (
  id uuid,
  created_at timestamptz,
  expires_at timestamptz,
  max_uses integer,
  use_count integer,
  revoked_at timestamptz,
  invite_status text
)
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

  if not exists (
    select 1
    from public.conversation_members m
    join public.channels ch on ch.conversation_id = m.conversation_id
    where m.conversation_id = p_conversation_id
      and m.user_id = v_actor
      and m.left_at is null
      and m.role in ('owner','admin')
      and ch.is_public = false
  ) then
    raise exception 'Only managers of private channels can view invites' using errcode='42501';
  end if;

  return query
  select
    i.id,
    i.created_at,
    i.expires_at,
    i.max_uses,
    i.use_count,
    i.revoked_at,
    case
      when i.revoked_at is not null then 'revoked'
      when i.expires_at <= now() then 'expired'
      when i.use_count >= i.max_uses then 'exhausted'
      else 'active'
    end
  from public.channel_invites i
  where i.conversation_id = p_conversation_id
  order by i.created_at desc
  limit 50;
end;
$function$;

create or replace function public.list_channel_invites(p_conversation_id uuid)
returns table (
  id uuid,
  created_at timestamptz,
  expires_at timestamptz,
  max_uses integer,
  use_count integer,
  revoked_at timestamptz,
  invite_status text
)
language sql
security invoker
set search_path = ''
as $function$
  select * from private.list_channel_invites_impl(p_conversation_id);
$function$;

revoke all on function private.list_channel_invites_impl(uuid) from public, anon, authenticated;
grant execute on function private.list_channel_invites_impl(uuid) to authenticated;
revoke all on function public.list_channel_invites(uuid) from public, anon;
grant execute on function public.list_channel_invites(uuid) to authenticated;
