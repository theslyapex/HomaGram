-- Channel management audit trail.
create table if not exists public.channel_audit_logs (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in (
    'channel_created','member_added','member_removed','member_role_changed',
    'channel_permissions_changed','channel_details_changed','ownership_transferred',
    'invite_created','invite_revoked'
  )),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists channel_audit_logs_conversation_created_idx
  on public.channel_audit_logs (conversation_id, created_at desc);

alter table public.channel_audit_logs enable row level security;
revoke all on public.channel_audit_logs from public, anon, authenticated;
grant select on public.channel_audit_logs to authenticated;

drop policy if exists "Channel managers can read audit history" on public.channel_audit_logs;
create policy "Channel managers can read audit history"
on public.channel_audit_logs for select to authenticated
using (
  exists (
    select 1
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
    where cm.conversation_id = channel_audit_logs.conversation_id
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
      and cm.role in ('owner','admin')
      and c.kind = 'channel'
  )
);

create or replace function private.capture_channel_audit_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conversation_id uuid;
  v_actor uuid := (select auth.uid());
  v_action text;
  v_target uuid;
  v_metadata jsonb := '{}'::jsonb;
begin
  if tg_table_name = 'conversation_members' then
    v_conversation_id := coalesce(new.conversation_id, old.conversation_id);
    if not exists (
      select 1 from public.conversations c
      where c.id = v_conversation_id and c.kind = 'channel'
    ) then
      return new;
    end if;

    if tg_op = 'INSERT' then
      if new.left_at is null then
        v_action := 'member_added';
        v_target := new.user_id;
        v_metadata := jsonb_build_object('role', new.role);
      else
        return new;
      end if;
    elsif tg_op = 'UPDATE' then
      v_target := new.user_id;
      if old.left_at is null and new.left_at is not null then
        v_action := 'member_removed';
      elsif old.role is distinct from new.role then
        v_action := 'member_role_changed';
        v_metadata := jsonb_build_object('old_role', old.role, 'new_role', new.role);
      else
        return new;
      end if;
    end if;

  elsif tg_table_name = 'channels' then
    v_conversation_id := coalesce(new.conversation_id, old.conversation_id);
    if tg_op = 'INSERT' then
      v_action := 'channel_created';
      v_metadata := jsonb_build_object('is_public', new.is_public, 'slug', new.slug);
    elsif tg_op = 'UPDATE' then
      if old.members_can_post is distinct from new.members_can_post
         or old.members_can_send_media is distinct from new.members_can_send_media then
        v_action := 'channel_permissions_changed';
        v_metadata := jsonb_build_object(
          'members_can_post', new.members_can_post,
          'members_can_send_media', new.members_can_send_media
        );
      elsif old.slug is distinct from new.slug or old.description is distinct from new.description
         or old.is_public is distinct from new.is_public then
        v_action := 'channel_details_changed';
        v_metadata := jsonb_build_object(
          'slug', new.slug,
          'description_changed', old.description is distinct from new.description,
          'is_public', new.is_public
        );
      else
        return new;
      end if;
    end if;

  elsif tg_table_name = 'conversations' then
    if new.kind <> 'channel' then return new; end if;
    v_conversation_id := new.id;
    if old.created_by is distinct from new.created_by then
      v_action := 'ownership_transferred';
      v_target := new.created_by;
      v_metadata := jsonb_build_object('previous_owner_id', old.created_by, 'new_owner_id', new.created_by);
    elsif old.title is distinct from new.title then
      v_action := 'channel_details_changed';
      v_metadata := jsonb_build_object('title', new.title);
    else
      return new;
    end if;

  elsif tg_table_name = 'channel_invites' then
    v_conversation_id := coalesce(new.conversation_id, old.conversation_id);
    if tg_op = 'INSERT' then
      v_action := 'invite_created';
      v_metadata := jsonb_build_object('expires_at', new.expires_at, 'max_uses', new.max_uses);
    elsif tg_op = 'UPDATE' and old.revoked_at is null and new.revoked_at is not null then
      v_action := 'invite_revoked';
      v_metadata := jsonb_build_object('invite_id', new.id);
    else
      return new;
    end if;
  end if;

  if v_action is not null then
    insert into public.channel_audit_logs (
      conversation_id, actor_id, target_user_id, action, metadata
    ) values (
      v_conversation_id, v_actor, v_target, v_action, v_metadata
    );
  end if;

  return new;
end;
$$;

revoke all on function private.capture_channel_audit_event() from public, anon, authenticated;

drop trigger if exists channel_audit_members on public.conversation_members;
create trigger channel_audit_members
after insert or update of role, left_at on public.conversation_members
for each row execute function private.capture_channel_audit_event();

drop trigger if exists channel_audit_channels on public.channels;
create trigger channel_audit_channels
after insert or update of slug, description, is_public, members_can_post, members_can_send_media
on public.channels for each row execute function private.capture_channel_audit_event();

drop trigger if exists channel_audit_conversations on public.conversations;
create trigger channel_audit_conversations
after update of title, created_by on public.conversations
for each row execute function private.capture_channel_audit_event();

drop trigger if exists channel_audit_invites on public.channel_invites;
create trigger channel_audit_invites
after insert or update of revoked_at on public.channel_invites
for each row execute function private.capture_channel_audit_event();
