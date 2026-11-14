-- Public/private channel foundation with authenticated RPC-only writes.
create table if not exists public.channels (
  conversation_id uuid primary key references public.conversations(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9_]{3,32}$'),
  description text not null default '' check (char_length(description) <= 500),
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists channels_public_created_idx
  on public.channels(created_at desc) where is_public = true;
alter table public.channels enable row level security;
drop policy if exists "Users can discover public channels or read joined channels" on public.channels;
create policy "Users can discover public channels or read joined channels"
on public.channels for select to authenticated
using (
  is_public or exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = channels.conversation_id
      and cm.user_id = (select auth.uid()) and cm.left_at is null
  )
);

create or replace function public.create_channel(
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
    raise exception 'Channel username must be 3 to 32 characters (a-z, 0-9, underscore)' using errcode='22023';
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

create or replace function public.join_public_channel(p_conversation_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not exists (select 1 from public.channels c where c.conversation_id=p_conversation_id and c.is_public=true) then
    raise exception 'Public channel not found' using errcode='P0002';
  end if;
  insert into public.conversation_members(conversation_id,user_id,role,joined_at,left_at)
  values (p_conversation_id,v_actor,'member',now(),null)
  on conflict (conversation_id,user_id)
  do update set role='member',joined_at=case when public.conversation_members.left_at is null then public.conversation_members.joined_at else now() end,left_at=null;
end;
$function$;

revoke all on function public.create_channel(text,text,text,boolean) from public,anon;
revoke all on function public.join_public_channel(uuid) from public,anon;
grant execute on function public.create_channel(text,text,text,boolean) to authenticated;
grant execute on function public.join_public_channel(uuid) to authenticated;
