-- Conversation-scoped online presence and non-exposed privileged group RPC implementations.
create table if not exists public.user_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_online boolean not null default false,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.user_presence enable row level security;
grant select, insert, update on public.user_presence to authenticated;

drop policy if exists "Users can read presence of conversation contacts" on public.user_presence;
create policy "Users can read presence of conversation contacts"
on public.user_presence for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.conversation_members mine
    join public.conversation_members theirs on theirs.conversation_id=mine.conversation_id
    where mine.user_id=(select auth.uid()) and mine.left_at is null
      and theirs.user_id=user_presence.user_id and theirs.left_at is null
  )
);
drop policy if exists "Users can publish their own presence" on public.user_presence;
create policy "Users can publish their own presence"
on public.user_presence for insert to authenticated
with check (user_id=(select auth.uid()));
drop policy if exists "Users can update their own presence" on public.user_presence;
create policy "Users can update their own presence"
on public.user_presence for update to authenticated
using (user_id=(select auth.uid()))
with check (user_id=(select auth.uid()));

create index if not exists conversation_members_active_user_conversation_idx
on public.conversation_members(user_id,conversation_id) where left_at is null;

do $publication$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='user_presence') then
    alter publication supabase_realtime add table public.user_presence;
  end if;
end;
$publication$;

create or replace function private.manage_group_member_impl(
  p_conversation_id uuid,p_target_user uuid,p_action text
)
returns void language plpgsql security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_actor_role text;
  v_target_role text;
  v_kind text;
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_target_user is null or p_target_user=v_actor then raise exception 'Invalid target member' using errcode='22023'; end if;
  select c.kind,cm.role into v_kind,v_actor_role
  from public.conversations c join public.conversation_members cm on cm.conversation_id=c.id
  where c.id=p_conversation_id and cm.user_id=v_actor and cm.left_at is null
  for update of c,cm;
  if not found or v_kind<>'group' then raise exception 'Group or active membership not found' using errcode='P0002'; end if;
  select role into v_target_role from public.conversation_members
  where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null for update;
  if p_action='add' then
    if v_actor_role not in ('owner','admin') then raise exception 'Only group managers can add members' using errcode='42501'; end if;
    if not exists(select 1 from auth.users where id=p_target_user) then raise exception 'User not found' using errcode='P0002'; end if;
    insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
    values(p_conversation_id,p_target_user,'member',now(),null)
    on conflict(conversation_id,user_id) do update set role='member',joined_at=now(),left_at=null;
  elsif p_action='remove' then
    if v_actor_role not in ('owner','admin') or v_target_role is null then raise exception 'Not permitted or member not found' using errcode='42501'; end if;
    if v_target_role='owner' or (v_actor_role='admin' and v_target_role='admin') then raise exception 'Cannot remove this manager' using errcode='42501'; end if;
    update public.conversation_members set left_at=now()
    where conversation_id=p_conversation_id and user_id=p_target_user and left_at is null;
  elsif p_action='promote' then
    if v_actor_role<>'owner' or v_target_role<>'member' then raise exception 'Only the owner can promote a regular member' using errcode='42501'; end if;
    update public.conversation_members set role='admin' where conversation_id=p_conversation_id and user_id=p_target_user;
  elsif p_action='demote' then
    if v_actor_role<>'owner' or v_target_role<>'admin' then raise exception 'Only the owner can demote an administrator' using errcode='42501'; end if;
    update public.conversation_members set role='member' where conversation_id=p_conversation_id and user_id=p_target_user;
  else
    raise exception 'Unsupported group action' using errcode='22023';
  end if;
end;
$function$;

create or replace function private.update_group_title_impl(p_conversation_id uuid,p_title text)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then raise exception 'Title must contain 1 to 100 characters' using errcode='22023'; end if;
  update public.conversations c set title=btrim(p_title),updated_at=now()
  where c.id=p_conversation_id and c.kind='group'
    and exists(select 1 from public.conversation_members cm where cm.conversation_id=c.id
      and cm.user_id=v_actor and cm.left_at is null and cm.role in ('owner','admin'));
  if not found then raise exception 'Not permitted or group not found' using errcode='42501'; end if;
end;
$function$;

revoke all on function private.manage_group_member_impl(uuid,uuid,text) from public,anon;
revoke all on function private.update_group_title_impl(uuid,text) from public,anon;
grant execute on function private.manage_group_member_impl(uuid,uuid,text) to authenticated;
grant execute on function private.update_group_title_impl(uuid,text) to authenticated;
grant usage on schema private to authenticated;

create or replace function public.manage_group_member(p_conversation_id uuid,p_target_user uuid,p_action text)
returns void language sql security invoker set search_path=''
as $function$ select private.manage_group_member_impl(p_conversation_id,p_target_user,p_action); $function$;
create or replace function public.update_group_title(p_conversation_id uuid,p_title text)
returns void language sql security invoker set search_path=''
as $function$ select private.update_group_title_impl(p_conversation_id,p_title); $function$;

revoke all on function public.manage_group_member(uuid,uuid,text) from public,anon;
revoke all on function public.update_group_title(uuid,text) from public,anon;
grant execute on function public.manage_group_member(uuid,uuid,text) to authenticated;
grant execute on function public.update_group_title(uuid,text) to authenticated;
