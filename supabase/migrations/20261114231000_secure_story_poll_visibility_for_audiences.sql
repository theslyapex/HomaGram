drop policy if exists "Visible story polls can be read by their audience" on public.story_polls;
create policy "Visible story polls can be read by their audience"
on public.story_polls for select to authenticated
using (
  exists (
    select 1 from public.stories s
    where s.id = story_polls.story_id
      and (
        s.author_id = (select auth.uid())
        or (s.expires_at > now() and private.can_view_story_content(s.id))
        or private.story_is_in_visible_highlight(s.id)
      )
  )
);
