-- Add explicit highlight covers and user-controlled ordering.
alter table public.story_highlights
  add column if not exists cover_story_id uuid
    references public.stories(id) on delete set null,
  add column if not exists position integer not null default 0
    check (position >= 0);

create index if not exists story_highlights_owner_position_idx
  on public.story_highlights (owner_id, position, created_at);

-- A cover may only point to a story owned by the same authenticated user.
drop policy if exists "Owners update story highlights" on public.story_highlights;
create policy "Owners update story highlights"
on public.story_highlights for update to authenticated
using (owner_id = (select auth.uid()))
with check (
  owner_id = (select auth.uid())
  and (
    cover_story_id is null
    or exists (
      select 1 from public.stories s
      where s.id = cover_story_id
        and s.author_id = (select auth.uid())
    )
  )
);

-- Reordering runs as the caller and remains subject to the table's RLS policies.
create or replace function public.reorder_story_highlights(p_highlight_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  expected_count integer;
  supplied_count integer;
  distinct_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select count(*)::integer into expected_count
  from public.story_highlights h
  where h.owner_id = (select auth.uid());

  supplied_count := coalesce(cardinality(p_highlight_ids), 0);
  select count(distinct item_id)::integer into distinct_count
  from unnest(coalesce(p_highlight_ids, array[]::uuid[])) as input(item_id);

  if supplied_count <> expected_count or distinct_count <> supplied_count then
    raise exception 'Invalid highlight ordering';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_highlight_ids, array[]::uuid[])) as input(item_id)
    left join public.story_highlights h
      on h.id = input.item_id and h.owner_id = (select auth.uid())
    where h.id is null
  ) then
    raise exception 'Invalid highlight ordering';
  end if;

  update public.story_highlights h
  set position = ordered.ordinality::integer - 1
  from unnest(coalesce(p_highlight_ids, array[]::uuid[]))
       with ordinality as ordered(item_id, ordinality)
  where h.id = ordered.item_id
    and h.owner_id = (select auth.uid());
end;
$$;

revoke all on function public.reorder_story_highlights(uuid[]) from public, anon;
grant execute on function public.reorder_story_highlights(uuid[]) to authenticated;
