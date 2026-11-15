-- Community ownership deletion and platform-level community moderation.

alter table public.conversations
  add column if not exists admin_blocked boolean not null default false,
  add column if not exists admin_block_reason text,
  add column if not exists admin_blocked_at timestamptz,
  add column if not exists admin_blocked_by uuid references auth.users(id) on delete set null;

alter table public.conversations
  drop constraint if exists conversations_admin_block_reason_length;
alter table public.conversations
  add constraint conversations_admin_block_reason_length
  check (admin_block_reason is null or char_length(admin_block_reason) <= 1000);

create index if not exists conversations_community_admin_idx
  on public.conversations(kind, admin_blocked, created_at desc)
  where kind in ('group', 'channel');

-- A platform block is enforced at the database boundary, not just in the UI.
drop policy if exists "Block message inserts in moderated communities" on public.messages;
create policy "Block message inserts in moderated communities"
on public.messages as restrictive
for insert to authenticated
with check (
  not exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and c.admin_blocked = true
  )
);

create or replace function private.delete_owned_community_impl(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_kind text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select c.kind into v_kind
  from public.conversations c
  join public.conversation_members cm on cm.conversation_id = c.id
  where c.id = p_conversation_id
    and c.kind in ('group', 'channel')
    and cm.user_id = v_actor
    and cm.left_at is null
    and cm.role = 'owner'
  for update of c, cm;

  if not found then
    raise exception 'Only the community owner can delete this group or channel' using errcode = '42501';
  end if;

  delete from public.conversations where id = p_conversation_id and kind = v_kind;
end;
$$;

create or replace function public.delete_owned_community(p_conversation_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.delete_owned_community_impl(p_conversation_id);
$$;

revoke all on function private.delete_owned_community_impl(uuid) from public, anon;
revoke all on function public.delete_owned_community(uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.delete_owned_community_impl(uuid) to authenticated;
grant execute on function public.delete_owned_community(uuid) to authenticated;

create or replace function private.admin_list_communities(
  p_kind text default 'all',
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  conversation_id uuid,
  kind text,
  title text,
  owner_id uuid,
  owner_username text,
  owner_display_name text,
  created_at timestamptz,
  is_public boolean,
  slug text,
  description text,
  member_count bigint,
  is_blocked boolean,
  block_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind text := lower(coalesce(p_kind, 'all'));
  v_search text := lower(btrim(coalesce(p_search, '')));
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if v_kind not in ('all', 'group', 'channel') then
    raise exception 'Invalid community type' using errcode = '22023';
  end if;
  if char_length(v_search) > 100 then
    raise exception 'Search query is too long' using errcode = '22023';
  end if;

  return query
  select
    c.id,
    c.kind,
    coalesce(c.title, case when c.kind = 'channel' then 'کانال بدون نام' else 'گروه بدون نام' end),
    owner_cm.user_id,
    p.username,
    p.display_name,
    c.created_at,
    case when c.kind = 'channel' then coalesce(ch.is_public, false) else c.is_public end,
    case when c.kind = 'channel' then ch.slug else c.public_slug end,
    case when c.kind = 'channel' then coalesce(ch.description, '') else coalesce(c.description, '') end,
    (select count(*)::bigint from public.conversation_members m
      where m.conversation_id = c.id and m.left_at is null),
    c.admin_blocked,
    c.admin_block_reason
  from public.conversations c
  left join public.channels ch on ch.conversation_id = c.id
  left join public.conversation_members owner_cm
    on owner_cm.conversation_id = c.id and owner_cm.role = 'owner' and owner_cm.left_at is null
  left join public.profiles p on p.id = owner_cm.user_id
  where c.kind in ('group', 'channel')
    and (v_kind = 'all' or c.kind = v_kind)
    and (
      v_search = ''
      or lower(coalesce(c.title, '')) like '%' || v_search || '%'
      or lower(coalesce(case when c.kind = 'channel' then ch.slug else c.public_slug end, '')) like '%' || v_search || '%'
      or c.id::text like '%' || v_search || '%'
      or coalesce(p.username, '') ilike '%' || v_search || '%'
    )
  order by c.created_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 100))
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.admin_list_communities(
  p_kind text default 'all',
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  conversation_id uuid,
  kind text,
  title text,
  owner_id uuid,
  owner_username text,
  owner_display_name text,
  created_at timestamptz,
  is_public boolean,
  slug text,
  description text,
  member_count bigint,
  is_blocked boolean,
  block_reason text
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.admin_list_communities(p_kind, p_search, p_limit, p_offset);
$$;

create or replace function private.admin_moderate_community(
  p_conversation_id uuid,
  p_action text,
  p_message text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_community public.conversations%rowtype;
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_notice text := btrim(coalesce(p_message, ''));
  v_title text;
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  select * into v_community
  from public.conversations
  where id = p_conversation_id and kind in ('group', 'channel')
  for update;

  if not found then
    raise exception 'Group or channel not found' using errcode = 'P0002';
  end if;

  v_title := coalesce(v_community.title, case when v_community.kind = 'channel' then 'کانال' else 'گروه' end);

  if v_action = 'warn' then
    if char_length(v_notice) not between 8 and 1000 then
      raise exception 'Warning message must contain 8 to 1000 characters' using errcode = '22023';
    end if;

    insert into public.messages(
      conversation_id, sender_id, client_message_id, message_type, body
    ) values (
      p_conversation_id, v_actor, gen_random_uuid(), 'system',
      '⚠️ اخطار مدیریت هماگرام' || E'\n\n' || v_notice
    );

    insert into public.notifications(recipient_id, actor_id, type, entity_id, entity_type, message)
    select cm.user_id, v_actor, 'moderation_notice', p_conversation_id, 'conversation',
      'اخطار مدیریت هماگرام برای ' || v_title || ': ' || left(v_notice, 350)
    from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.left_at is null
      and cm.user_id <> v_actor;

    update public.conversations set updated_at = now() where id = p_conversation_id;

    insert into private.admin_audit_logs(actor_id, action, metadata)
    values (v_actor, 'community_warned', jsonb_build_object(
      'conversation_id', p_conversation_id, 'kind', v_community.kind, 'title', v_title
    ));

  elsif v_action = 'block' then
    update public.conversations
    set admin_blocked = true,
        admin_block_reason = nullif(v_notice, ''),
        admin_blocked_at = now(),
        admin_blocked_by = v_actor,
        updated_at = now()
    where id = p_conversation_id;

    insert into private.admin_audit_logs(actor_id, action, metadata)
    values (v_actor, 'community_blocked', jsonb_build_object(
      'conversation_id', p_conversation_id, 'kind', v_community.kind,
      'title', v_title, 'reason', nullif(v_notice, '')
    ));

  elsif v_action = 'unblock' then
    update public.conversations
    set admin_blocked = false,
        admin_block_reason = null,
        admin_blocked_at = null,
        admin_blocked_by = null,
        updated_at = now()
    where id = p_conversation_id;

    insert into private.admin_audit_logs(actor_id, action, metadata)
    values (v_actor, 'community_unblocked', jsonb_build_object(
      'conversation_id', p_conversation_id, 'kind', v_community.kind, 'title', v_title
    ));

  elsif v_action = 'delete' then
    insert into private.admin_audit_logs(actor_id, action, metadata)
    values (v_actor, 'community_deleted', jsonb_build_object(
      'conversation_id', p_conversation_id, 'kind', v_community.kind,
      'title', v_title, 'member_count',
      (select count(*) from public.conversation_members cm
        where cm.conversation_id = p_conversation_id and cm.left_at is null)
    ));

    delete from public.conversations where id = p_conversation_id;

  else
    raise exception 'Unsupported community moderation action' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.admin_moderate_community(
  p_conversation_id uuid,
  p_action text,
  p_message text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.admin_moderate_community(p_conversation_id, p_action, p_message);
$$;

revoke all on function private.admin_list_communities(text, text, integer, integer) from public, anon;
revoke all on function public.admin_list_communities(text, text, integer, integer) from public, anon;
revoke all on function private.admin_moderate_community(uuid, text, text) from public, anon;
revoke all on function public.admin_moderate_community(uuid, text, text) from public, anon;
grant execute on function private.admin_list_communities(text, text, integer, integer) to authenticated;
grant execute on function public.admin_list_communities(text, text, integer, integer) to authenticated;
grant execute on function private.admin_moderate_community(uuid, text, text) to authenticated;
grant execute on function public.admin_moderate_community(uuid, text, text) to authenticated;
