-- Story highlights: collections of the owner's own archived or active stories.
create table if not exists public.story_highlights (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 30),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.story_highlight_items (
  highlight_id uuid not null references public.story_highlights(id) on delete cascade,
  story_id uuid not null references public.stories(id) on delete cascade,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  primary key (highlight_id, story_id)
);

create index if not exists story_highlights_owner_created_idx
  on public.story_highlights (owner_id, created_at desc);
create index if not exists story_highlight_items_story_idx
  on public.story_highlight_items (story_id);

alter table public.story_highlights enable row level security;
alter table public.story_highlight_items enable row level security;

grant select, insert, update, delete on public.story_highlights to authenticated;
grant select, insert, update, delete on public.story_highlight_items to authenticated;

drop policy if exists "Visible story highlights can be read" on public.story_highlights;
create policy "Visible story highlights can be read"
on public.story_highlights for select to authenticated
using (owner_id = (select auth.uid()) or private.can_view_story(owner_id));

drop policy if exists "Owners create story highlights" on public.story_highlights;
create policy "Owners create story highlights"
on public.story_highlights for insert to authenticated
with check (owner_id = (select auth.uid()));

drop policy if exists "Owners update story highlights" on public.story_highlights;
create policy "Owners update story highlights"
on public.story_highlights for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists "Owners delete story highlights" on public.story_highlights;
create policy "Owners delete story highlights"
on public.story_highlights for delete to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists "Visible story highlight items can be read" on public.story_highlight_items;
create policy "Visible story highlight items can be read"
on public.story_highlight_items for select to authenticated
using (
  exists (
    select 1 from public.story_highlights h
    where h.id = highlight_id
      and (h.owner_id = (select auth.uid()) or private.can_view_story(h.owner_id))
  )
);

drop policy if exists "Owners add their own stories to highlights" on public.story_highlight_items;
create policy "Owners add their own stories to highlights"
on public.story_highlight_items for insert to authenticated
with check (
  exists (
    select 1 from public.story_highlights h
    where h.id = highlight_id and h.owner_id = (select auth.uid())
  )
  and exists (
    select 1 from public.stories s
    where s.id = story_id and s.author_id = (select auth.uid())
  )
);

drop policy if exists "Owners remove stories from highlights" on public.story_highlight_items;
create policy "Owners remove stories from highlights"
on public.story_highlight_items for delete to authenticated
using (
  exists (
    select 1 from public.story_highlights h
    where h.id = highlight_id and h.owner_id = (select auth.uid())
  )
);

create or replace function private.story_is_in_visible_highlight(p_story_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.story_highlight_items hi
    join public.story_highlights h on h.id = hi.highlight_id
    where hi.story_id = p_story_id
      and private.can_view_story(h.owner_id)
  );
$$;

revoke all on function private.story_is_in_visible_highlight(uuid) from public, anon;
grant execute on function private.story_is_in_visible_highlight(uuid) to authenticated;

drop policy if exists "Visible stories can be read by their audience" on public.stories;
create policy "Visible stories can be read by their audience"
on public.stories for select to authenticated
using (
  author_id = (select auth.uid())
  or (
    expires_at > now()
    and private.can_view_story(author_id)
  )
  or private.story_is_in_visible_highlight(id)
);

drop policy if exists "Story audience can read story media" on storage.objects;
create policy "Story audience can read story media"
on storage.objects for select to authenticated
using (
  bucket_id = 'story-media'
  and exists (
    select 1 from public.stories s
    where s.media_path = objects.name
      and (
        s.author_id = (select auth.uid())
        or (s.expires_at > now() and private.can_view_story(s.author_id))
        or private.story_is_in_visible_highlight(s.id)
      )
  )
);
