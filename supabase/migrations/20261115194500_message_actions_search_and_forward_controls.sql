-- Message actions: starring, moderated pins/deletes, forwarding provenance and privacy.
alter table public.messages
  add column if not exists deleted_by uuid references auth.users(id) on delete set null,
  add column if not exists forwarded_from_sender_id uuid references auth.users(id) on delete set null,
  add column if not exists forwarded_from_display_name text;
alter table public.account_settings
  add column if not exists allow_message_forwarding boolean not null default true;
grant update (allow_message_forwarding) on public.account_settings to authenticated;

create table if not exists public.message_stars (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create table if not exists public.conversation_pins (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  pinned_by uuid not null references auth.users(id) on delete cascade,
  pinned_at timestamptz not null default now(),
  primary key (conversation_id, message_id)
);
alter table public.message_stars enable row level security;
alter table public.conversation_pins enable row level security;
revoke all on public.message_stars, public.conversation_pins from anon, authenticated;
grant select, insert, delete on public.message_stars to authenticated;
grant select on public.conversation_pins to authenticated;
drop policy if exists "Users read their own starred messages" on public.message_stars;
create policy "Users read their own starred messages" on public.message_stars
for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "Users star messages in their conversations" on public.message_stars;
create policy "Users star messages in their conversations" on public.message_stars
for insert to authenticated with check (
  user_id = (select auth.uid()) and exists (
    select 1 from public.messages m
    where m.id = message_id and private.is_active_conversation_member(m.conversation_id)
  )
);
drop policy if exists "Users unstar their own messages" on public.message_stars;
create policy "Users unstar their own messages" on public.message_stars
for delete to authenticated using (user_id = (select auth.uid()));
drop policy if exists "Members read conversation pins" on public.conversation_pins;
create policy "Members read conversation pins" on public.conversation_pins
for select to authenticated using (private.is_active_conversation_member(conversation_id));

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
  if new.body is distinct from old.body then
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

create or replace function public.toggle_message_star(p_message_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid := (select auth.uid()); v_conversation uuid; v_exists boolean;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select m.conversation_id into v_conversation from public.messages m where m.id=p_message_id;
  if v_conversation is null or not private.is_active_conversation_member(v_conversation) then raise exception 'Message not found' using errcode='42501'; end if;
  select exists(select 1 from public.message_stars s where s.message_id=p_message_id and s.user_id=v_user) into v_exists;
  if v_exists then delete from public.message_stars where message_id=p_message_id and user_id=v_user; return false; end if;
  insert into public.message_stars(message_id,user_id) values(p_message_id,v_user) on conflict do nothing; return true;
end;
$function$;

create or replace function public.pin_conversation_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid := (select auth.uid()); v_conversation uuid; v_role text;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select m.conversation_id into v_conversation from public.messages m where m.id=p_message_id and m.deleted_at is null;
  if v_conversation is null or not private.is_active_conversation_member(v_conversation) then raise exception 'Message not found' using errcode='42501'; end if;
  select cm.role into v_role from public.conversation_members cm where cm.conversation_id=v_conversation and cm.user_id=v_user and cm.left_at is null;
  if (select c.kind from public.conversations c where c.id=v_conversation) <> 'direct' and coalesce(v_role,'member') not in ('owner','admin') then
    raise exception 'Only group or channel admins can pin messages' using errcode='42501';
  end if;
  insert into public.conversation_pins(conversation_id,message_id,pinned_by) values(v_conversation,p_message_id,v_user) on conflict do nothing;
end;
$function$;

create or replace function public.unpin_conversation_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid := (select auth.uid()); v_conversation uuid; v_role text;
begin
  select conversation_id into v_conversation from public.messages where id=p_message_id;
  if v_user is null or v_conversation is null or not private.is_active_conversation_member(v_conversation) then raise exception 'Message not found' using errcode='42501'; end if;
  select role into v_role from public.conversation_members where conversation_id=v_conversation and user_id=v_user and left_at is null;
  if (select kind from public.conversations where id=v_conversation) <> 'direct' and coalesce(v_role,'member') not in ('owner','admin') then
    raise exception 'Only group or channel admins can unpin messages' using errcode='42501';
  end if;
  delete from public.conversation_pins where conversation_id=v_conversation and message_id=p_message_id;
end;
$function$;

create or replace function public.delete_conversation_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid := (select auth.uid()); v_conversation uuid; v_sender uuid; v_role text;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select conversation_id,sender_id into v_conversation,v_sender from public.messages where id=p_message_id and deleted_at is null;
  if v_conversation is null or not private.is_active_conversation_member(v_conversation) then raise exception 'Message not found' using errcode='42501'; end if;
  select role into v_role from public.conversation_members where conversation_id=v_conversation and user_id=v_user and left_at is null;
  if v_sender <> v_user and ((select kind from public.conversations where id=v_conversation) = 'direct' or coalesce(v_role,'member') not in ('owner','admin')) then
    raise exception 'Only the sender or a group/channel admin can delete this message' using errcode='42501';
  end if;
  update public.messages set deleted_at=now(), deleted_by=v_user, body='' where id=p_message_id;
end;
$function$;

create or replace function public.forward_text_message(p_message_id uuid,p_target_conversation_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid := (select auth.uid()); v_source public.messages%rowtype; v_sender_name text; v_new_id uuid; v_allowed boolean;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not private.is_active_conversation_member(p_target_conversation_id) then raise exception 'Target conversation is unavailable' using errcode='42501'; end if;
  select * into v_source from public.messages where id=p_message_id and deleted_at is null;
  if v_source.id is null or not private.is_active_conversation_member(v_source.conversation_id) then raise exception 'Source message is unavailable' using errcode='42501'; end if;
  if v_source.message_type <> 'text' then raise exception 'Only text messages can currently be forwarded' using errcode='22023'; end if;
  select coalesce(s.allow_message_forwarding,true) into v_allowed from public.account_settings s where s.user_id=v_source.sender_id;
  if not coalesce(v_allowed,true) then raise exception 'The sender has disabled message forwarding' using errcode='42501'; end if;
  select coalesce(p.display_name,p.username,'کاربر') into v_sender_name from public.profiles p where p.id=v_source.sender_id;
  insert into public.messages(conversation_id,sender_id,message_type,body,forwarded_from_sender_id,forwarded_from_display_name)
  values(p_target_conversation_id,v_user,'text',v_source.body,v_source.sender_id,coalesce(v_sender_name,'کاربر')) returning id into v_new_id;
  return v_new_id;
end;
$function$;

revoke all on function public.toggle_message_star(uuid) from public,anon;
revoke all on function public.pin_conversation_message(uuid) from public,anon;
revoke all on function public.unpin_conversation_message(uuid) from public,anon;
revoke all on function public.delete_conversation_message(uuid) from public,anon;
revoke all on function public.forward_text_message(uuid,uuid) from public,anon;
grant execute on function public.toggle_message_star(uuid) to authenticated;
grant execute on function public.pin_conversation_message(uuid) to authenticated;
grant execute on function public.unpin_conversation_message(uuid) to authenticated;
grant execute on function public.delete_conversation_message(uuid) to authenticated;
grant execute on function public.forward_text_message(uuid,uuid) to authenticated;
