-- Secure chat media storage and group membership administration.
create table if not exists public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  uploader_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 52428800),
  file_name text not null check (char_length(file_name) between 1 and 255),
  created_at timestamptz not null default now(),
  constraint message_attachments_message_conversation_fk
    foreign key (message_id, conversation_id)
    references public.messages(id, conversation_id) on delete cascade
);

create index if not exists message_attachments_conversation_created_idx
  on public.message_attachments(conversation_id, created_at desc);
create index if not exists message_attachments_message_idx
  on public.message_attachments(message_id);

alter table public.message_attachments enable row level security;

drop policy if exists "Conversation members can read message attachments" on public.message_attachments;
create policy "Conversation members can read message attachments"
on public.message_attachments for select to authenticated
using (
  exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = message_attachments.conversation_id
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
  )
);

drop policy if exists "Senders can attach files to their messages" on public.message_attachments;
create policy "Senders can attach files to their messages"
on public.message_attachments for insert to authenticated
with check (
  uploader_id = (select auth.uid())
  and exists (
    select 1 from public.messages m
    join public.conversation_members cm
      on cm.conversation_id = m.conversation_id
    where m.id = message_attachments.message_id
      and m.conversation_id = message_attachments.conversation_id
      and m.sender_id = (select auth.uid())
      and m.message_type in ('image','video','audio','file')
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
  )
);

drop policy if exists "Senders can remove their own attachment metadata" on public.message_attachments;
create policy "Senders can remove their own attachment metadata"
on public.message_attachments for delete to authenticated
using (uploader_id = (select auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-media', 'chat-media', false, 52428800,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','video/webm','audio/mpeg','audio/mp4','audio/aac','application/pdf']
)
on conflict (id) do update
set public = false,
    file_size_limit = 52428800,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Chat members can upload their own media" on storage.objects;
create policy "Chat members can upload their own media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-media'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and case
    when split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and split_part(name, '/', 3) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then exists (
      select 1 from public.messages m
      join public.conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = split_part(name, '/', 3)::uuid
        and m.conversation_id = split_part(name, '/', 1)::uuid
        and m.sender_id = (select auth.uid())
        and cm.user_id = (select auth.uid())
        and cm.left_at is null
    )
    else false
  end
);

drop policy if exists "Chat members can read attached media" on storage.objects;
create policy "Chat members can read attached media"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-media'
  and exists (
    select 1
    from public.message_attachments a
    join public.conversation_members cm on cm.conversation_id = a.conversation_id
    where a.storage_path = storage.objects.name
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
  )
);

drop policy if exists "Uploaders can delete their chat media" on storage.objects;
create policy "Uploaders can delete their chat media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-media'
  and split_part(name, '/', 2) = (select auth.uid())::text
);

create or replace function public.manage_group_member(
  p_conversation_id uuid,
  p_target_user uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_actor_role text;
  v_target_role text;
  v_kind text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_target_user is null or p_target_user = v_actor then
    raise exception 'Invalid target member' using errcode = '22023';
  end if;
  select c.kind, cm.role into v_kind, v_actor_role
  from public.conversations c
  join public.conversation_members cm on cm.conversation_id = c.id
  where c.id = p_conversation_id
    and cm.user_id = v_actor and cm.left_at is null
  for update of c, cm;
  if not found or v_kind <> 'group' then
    raise exception 'Group or active membership not found' using errcode = 'P0002';
  end if;
  select role into v_target_role
  from public.conversation_members
  where conversation_id = p_conversation_id
    and user_id = p_target_user and left_at is null
  for update;

  if p_action = 'add' then
    if v_actor_role not in ('owner','admin') then
      raise exception 'Only group managers can add members' using errcode = '42501';
    end if;
    if not exists (select 1 from auth.users where id = p_target_user) then
      raise exception 'User not found' using errcode = 'P0002';
    end if;
    insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
    values (p_conversation_id,p_target_user,'member',now(),null)
    on conflict (conversation_id,user_id)
    do update set role='member',joined_at=now(),left_at=null;
  elsif p_action = 'remove' then
    if v_actor_role not in ('owner','admin') or v_target_role is null then
      raise exception 'Not permitted or member not found' using errcode = '42501';
    end if;
    if v_target_role = 'owner' or (v_actor_role = 'admin' and v_target_role = 'admin') then
      raise exception 'Cannot remove this manager' using errcode = '42501';
    end if;
    update public.conversation_members set left_at=now()
    where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null;
  elsif p_action = 'promote' then
    if v_actor_role <> 'owner' or v_target_role <> 'member' then
      raise exception 'Only the owner can promote a regular member' using errcode = '42501';
    end if;
    update public.conversation_members set role='admin'
    where conversation_id=p_conversation_id and user_id=p_target_user;
  elsif p_action = 'demote' then
    if v_actor_role <> 'owner' or v_target_role <> 'admin' then
      raise exception 'Only the owner can demote an administrator' using errcode = '42501';
    end if;
    update public.conversation_members set role='member'
    where conversation_id=p_conversation_id and user_id=p_target_user;
  else
    raise exception 'Unsupported group action' using errcode = '22023';
  end if;
end;
$function$;

create or replace function public.update_group_title(
  p_conversation_id uuid,
  p_title text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception 'Title must contain 1 to 100 characters' using errcode = '22023';
  end if;
  update public.conversations c
  set title=btrim(p_title), updated_at=now()
  where c.id=p_conversation_id and c.kind='group'
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id=c.id and cm.user_id=v_actor
        and cm.left_at is null and cm.role in ('owner','admin')
    );
  if not found then
    raise exception 'Not permitted or group not found' using errcode = '42501';
  end if;
end;
$function$;

revoke all on function public.manage_group_member(uuid,uuid,text) from public, anon;
revoke all on function public.update_group_title(uuid,text) from public, anon;
grant execute on function public.manage_group_member(uuid,uuid,text) to authenticated;
grant execute on function public.update_group_title(uuid,text) to authenticated;

do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='message_attachments'
  ) then
    alter publication supabase_realtime add table public.message_attachments;
  end if;
end;
$publication$;
