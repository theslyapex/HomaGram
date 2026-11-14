-- Keep API-facing channel RPCs SECURITY INVOKER; privileged work stays in private helpers.
create or replace function private.create_channel_impl(
  p_title text, p_slug text, p_description text default '', p_is_public boolean default true
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_id uuid;
  v_slug text := lower(btrim(coalesce(p_slug,'')));
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception 'Channel title must contain 1 to 100 characters' using errcode='22023';
  end if;
  if v_slug !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'Channel username must be 3 to 32 characters' using errcode='22023';
  end if;
  if char_length(coalesce(p_description,'')) > 500 then
    raise exception 'Description is too long' using errcode='22023';
  end if;
  insert into public.conversations(kind,title,created_by)
  values ('channel',btrim(p_title),v_actor) returning id into v_id;
  insert into public.channels(conversation_id,slug,description,is_public)
  values (v_id,v_slug,btrim(coalesce(p_description,'')),coalesce(p_is_public,true));
  insert into public.conversation_members(conversation_id,user_id,role)
  values (v_id,v_actor,'owner');
  return v_id;
end;
$function$;

create or replace function private.join_public_channel_impl(p_conversation_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not exists (
    select 1 from public.channels c
    where c.conversation_id=p_conversation_id and c.is_public=true
  ) then
    raise exception 'Public channel not found' using errcode='P0002';
  end if;
  insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
  values (p_conversation_id,v_actor,'member',now(),null)
  on conflict (conversation_id,user_id)
  do update set role='member',
    joined_at=case when public.conversation_members.left_at is null
      then public.conversation_members.joined_at else now() end,
    left_at=null;
end;
$function$;

create or replace function public.create_channel(
  p_title text, p_slug text, p_description text default '', p_is_public boolean default true
) returns uuid language sql set search_path = ''
as $function$
  select private.create_channel_impl(p_title,p_slug,p_description,p_is_public);
$function$;

create or replace function public.join_public_channel(p_conversation_id uuid)
returns void language sql set search_path = ''
as $function$
  select private.join_public_channel_impl(p_conversation_id);
$function$;

revoke all on function private.create_channel_impl(text,text,text,boolean) from public, anon;
revoke all on function private.join_public_channel_impl(uuid) from public, anon;
revoke all on function private.manage_channel_member_impl(uuid,uuid,text) from public, anon;
revoke all on function private.update_channel_details_impl(uuid,text,text,text) from public, anon;
grant execute on function private.create_channel_impl(text,text,text,boolean) to authenticated;
grant execute on function private.join_public_channel_impl(uuid) to authenticated;
grant execute on function private.manage_channel_member_impl(uuid,uuid,text) to authenticated;
grant execute on function private.update_channel_details_impl(uuid,text,text,text) to authenticated;

revoke all on function public.create_channel(text,text,text,boolean) from public, anon;
revoke all on function public.join_public_channel(uuid) from public, anon;
grant execute on function public.create_channel(text,text,text,boolean) to authenticated;
grant execute on function public.join_public_channel(uuid) to authenticated;
