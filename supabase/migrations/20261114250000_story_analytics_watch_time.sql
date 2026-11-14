-- Story analytics: cumulative watch time per unique viewer, with owner-only reporting via existing RLS.
alter table public.story_views
  add column if not exists duration_seconds integer not null default 0;

alter table public.story_views
  drop constraint if exists story_views_duration_seconds_range;
alter table public.story_views
  add constraint story_views_duration_seconds_range
  check (duration_seconds between 0 and 3600);

create index if not exists story_views_story_viewed_idx
  on public.story_views (story_id, viewed_at desc);
create index if not exists story_reactions_story_created_idx
  on public.story_reactions (story_id, created_at desc);

create or replace function private.add_story_view_duration(
  p_story_id uuid,
  p_duration_seconds integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_total integer;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  if p_duration_seconds is null or p_duration_seconds < 1
     or p_duration_seconds > 600 then
    raise exception 'Invalid viewing duration';
  end if;

  update public.story_views sv
     set duration_seconds = least(sv.duration_seconds + p_duration_seconds, 3600)
   where sv.story_id = p_story_id
     and sv.viewer_id = v_uid
     and exists (
       select 1 from public.stories s
       where s.id = sv.story_id and s.author_id <> v_uid
     )
  returning sv.duration_seconds into v_total;

  if not found then
    raise exception 'Story view record not found';
  end if;
  return v_total;
end;
$$;

drop function if exists public.record_story_view_duration(uuid, integer);
create function public.record_story_view_duration(
  p_story_id uuid,
  p_duration_seconds integer
)
returns integer
language sql
security invoker
set search_path = ''
as $$
  select private.add_story_view_duration(p_story_id, p_duration_seconds);
$$;

grant usage on schema private to authenticated;
revoke all on function private.add_story_view_duration(uuid, integer) from public, anon;
grant execute on function private.add_story_view_duration(uuid, integer) to authenticated;
revoke all on function public.record_story_view_duration(uuid, integer) from public, anon;
grant execute on function public.record_story_view_duration(uuid, integer) to authenticated;
