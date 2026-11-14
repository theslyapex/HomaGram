
create table if not exists public.story_countdowns (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null unique references public.stories(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 100),
  target_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint story_countdowns_target_range check (
    target_at > created_at and target_at <= created_at + interval '365 days'
  )
);
create index if not exists story_countdowns_target_at_idx
  on public.story_countdowns(target_at);

alter table public.story_countdowns enable row level security;
revoke all on public.story_countdowns from anon, authenticated;
drop policy if exists "No direct access to story countdowns" on public.story_countdowns;
create policy "No direct access to story countdowns"
on public.story_countdowns for all to anon, authenticated
using (false) with check (false);

create or replace function private.create_story_countdown(
  p_story_id uuid, p_title text, p_target_at timestamptz
) returns uuid
language plpgsql security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_story public.stories%rowtype;
  v_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if char_length(btrim(coalesce(p_title,''))) not between 1 and 100 then
    raise exception 'Countdown title must contain 1 to 100 characters';
  end if;
  if p_target_at is null or p_target_at <= now()
     or p_target_at > now() + interval '365 days' then
    raise exception 'Countdown target must be within the next 365 days';
  end if;
  select * into v_story from public.stories where id=p_story_id for update;
  if not found or v_story.author_id <> v_uid or v_story.expires_at <= now() then
    raise exception 'Story is not eligible for a countdown';
  end if;
  insert into public.story_countdowns(story_id,title,target_at)
  values(p_story_id,btrim(p_title),p_target_at)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function private.get_story_countdowns(p_story_ids uuid[])
returns jsonb
language plpgsql stable security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'story_id',c.story_id,'title',c.title,
    'target_at',c.target_at,'created_at',c.created_at,
    'is_completed',c.target_at <= now()
  ) order by c.created_at),'[]'::jsonb)
  into v_result
  from public.story_countdowns c
  join public.stories s on s.id=c.story_id
  where c.story_id=any(coalesce(p_story_ids,array[]::uuid[]))
    and (
      s.author_id=v_uid
      or (s.expires_at>now() and private.can_view_story(s.author_id))
      or private.story_is_in_visible_highlight(s.id)
    );
  return v_result;
end;
$$;

drop function if exists public.create_story_countdown(uuid,text,timestamptz);
drop function if exists public.get_story_countdowns(uuid[]);
create or replace function public.create_story_countdown(
  p_story_id uuid,p_title text,p_target_at timestamptz
) returns uuid language sql security invoker
set search_path=public,private,auth,pg_temp
as $$ select private.create_story_countdown(p_story_id,p_title,p_target_at); $$;
create or replace function public.get_story_countdowns(p_story_ids uuid[])
returns jsonb language sql stable security invoker
set search_path=public,private,auth,pg_temp
as $$ select private.get_story_countdowns(p_story_ids); $$;

grant usage on schema private to authenticated;
revoke all on function private.create_story_countdown(uuid,text,timestamptz) from public,anon;
revoke all on function private.get_story_countdowns(uuid[]) from public,anon;
grant execute on function private.create_story_countdown(uuid,text,timestamptz) to authenticated;
grant execute on function private.get_story_countdowns(uuid[]) to authenticated;
revoke all on function public.create_story_countdown(uuid,text,timestamptz) from public,anon;
revoke all on function public.get_story_countdowns(uuid[]) from public,anon;
grant execute on function public.create_story_countdown(uuid,text,timestamptz) to authenticated;
grant execute on function public.get_story_countdowns(uuid[]) to authenticated;
