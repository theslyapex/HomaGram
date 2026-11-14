create table if not exists public.channel_invites (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.channels(conversation_id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  max_uses integer not null default 100 check (max_uses between 1 and 500),
  use_count integer not null default 0 check (use_count >= 0),
  revoked_at timestamptz
);

create index if not exists channel_invites_conversation_idx
  on public.channel_invites(conversation_id, created_at desc);

alter table public.channel_invites enable row level security;
revoke all on public.channel_invites from public, anon, authenticated;

create or replace function private.create_channel_invite_impl(
  p_conversation_id uuid,
  p_expires_in_hours integer default 168,
  p_max_uses integer default 100
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_token text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;
  if p_expires_in_hours not between 1 and 720 then
    raise exception 'Invite expiry must be between 1 and 720 hours' using errcode='22023';
  end if;
  if p_max_uses not between 1 and 500 then
    raise exception 'Invite use limit must be between 1 and 500' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id
    where m.conversation_id = p_conversation_id
      and m.user_id = v_actor
      and m.left_at is null
      and m.role in ('owner','admin')
      and c.kind = 'channel'
  ) then
    raise exception 'Only channel owners and admins can create invites' using errcode='42501';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.channel_invites(
    conversation_id, token_hash, created_by, expires_at, max_uses
  ) values (
    p_conversation_id,
    encode(extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex'),
    v_actor,
    now() + make_interval(hours => p_expires_in_hours),
    p_max_uses
  );
  return v_token;
end;
$function$;

create or replace function private.join_channel_by_invite_impl(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_invite public.channel_invites%rowtype;
  v_hash text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;
  if p_token is null or p_token !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'Invalid invite code' using errcode='22023';
  end if;

  v_hash := encode(extensions.digest(convert_to(lower(p_token), 'UTF8'), 'sha256'), 'hex');
  select * into v_invite
  from public.channel_invites
  where token_hash = v_hash
  for update;

  if not found
    or v_invite.revoked_at is not null
    or v_invite.expires_at <= now()
    or v_invite.use_count >= v_invite.max_uses then
    raise exception 'Invite code is invalid or expired' using errcode='22023';
  end if;

  if not exists (
    select 1 from public.channels ch
    where ch.conversation_id = v_invite.conversation_id
      and ch.is_public = false
  ) then
    raise exception 'Invite is not for a private channel' using errcode='22023';
  end if;

  update public.conversation_members
  set left_at = null, joined_at = now()
  where conversation_id = v_invite.conversation_id
    and user_id = v_actor;

  if not found then
    insert into public.conversation_members(conversation_id, user_id, role)
    values (v_invite.conversation_id, v_actor, 'member');
  end if;

  update public.channel_invites
  set use_count = use_count + 1
  where id = v_invite.id;

  return v_invite.conversation_id;
end;
$function$;

create or replace function private.revoke_channel_invite_impl(p_invite_id uuid)
returns void
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
  update public.channel_invites i
  set revoked_at = now()
  where i.id = p_invite_id
    and i.revoked_at is null
    and exists (
      select 1 from public.conversation_members m
      where m.conversation_id = i.conversation_id
        and m.user_id = v_actor
        and m.left_at is null
        and m.role in ('owner','admin')
    );
  if not found then
    raise exception 'Invite not found or permission denied' using errcode='42501';
  end if;
end;
$function$;

create or replace function public.create_channel_invite(
  p_conversation_id uuid,
  p_expires_in_hours integer default 168,
  p_max_uses integer default 100
)
returns text
language sql
security invoker
set search_path = ''
as $function$
  select private.create_channel_invite_impl(
    p_conversation_id, p_expires_in_hours, p_max_uses
  );
$function$;

create or replace function public.join_channel_by_invite(p_token text)
returns uuid
language sql
security invoker
set search_path = ''
as $function$
  select private.join_channel_by_invite_impl(p_token);
$function$;

create or replace function public.revoke_channel_invite(p_invite_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.revoke_channel_invite_impl(p_invite_id);
$function$;

revoke all on function private.create_channel_invite_impl(uuid,integer,integer) from public, anon, authenticated;
revoke all on function private.join_channel_by_invite_impl(text) from public, anon, authenticated;
revoke all on function private.revoke_channel_invite_impl(uuid) from public, anon, authenticated;
grant execute on function private.create_channel_invite_impl(uuid,integer,integer) to authenticated;
grant execute on function private.join_channel_by_invite_impl(text) to authenticated;
grant execute on function private.revoke_channel_invite_impl(uuid) to authenticated;

revoke all on function public.create_channel_invite(uuid,integer,integer) from public, anon;
revoke all on function public.join_channel_by_invite(text) from public, anon;
revoke all on function public.revoke_channel_invite(uuid) from public, anon;
grant execute on function public.create_channel_invite(uuid,integer,integer) to authenticated;
grant execute on function public.join_channel_by_invite(text) to authenticated;
grant execute on function public.revoke_channel_invite(uuid) to authenticated;
