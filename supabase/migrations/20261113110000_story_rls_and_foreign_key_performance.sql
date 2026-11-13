-- Improve foreign-key lookup performance and avoid per-row auth.uid() evaluation
-- in story row-level security policies. Authorization semantics remain unchanged.

create index if not exists message_attachments_message_conversation_idx
  on public.message_attachments (message_id, conversation_id);

create index if not exists message_attachments_uploader_id_idx
  on public.message_attachments (uploader_id);

create index if not exists post_comments_parent_id_idx
  on public.post_comments (parent_id);

create index if not exists post_comments_user_id_idx
  on public.post_comments (user_id);

create index if not exists post_likes_user_id_idx
  on public.post_likes (user_id);

create index if not exists post_reports_reporter_id_idx
  on public.post_reports (reporter_id);

create index if not exists post_reposts_user_id_idx
  on public.post_reposts (user_id);

create index if not exists saved_posts_user_id_idx
  on public.saved_posts (user_id);

create index if not exists story_reactions_user_id_idx
  on public.story_reactions (user_id);

drop policy if exists "Users can delete their own stories" on public.stories;
create policy "Users can delete their own stories"
  on public.stories for delete to authenticated
  using (author_id = (select auth.uid()));

drop policy if exists "Users can publish their own stories" on public.stories;
create policy "Users can publish their own stories"
  on public.stories for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and expires_at > now()
    and expires_at <= (now() + interval '24 hours 5 minutes')
  );

drop policy if exists "Visible stories can be read by their audience" on public.stories;
create policy "Visible stories can be read by their audience"
  on public.stories for select to authenticated
  using (
    author_id = (select auth.uid())
    or (expires_at > now() and private.can_view_story(author_id))
  );

drop policy if exists "Users can change their story reaction" on public.story_reactions;
create policy "Users can change their story reaction"
  on public.story_reactions for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can remove their story reaction" on public.story_reactions;
create policy "Users can remove their story reaction"
  on public.story_reactions for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Eligible users can react to stories" on public.story_reactions;
create policy "Eligible users can react to stories"
  on public.story_reactions for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.stories s
      where s.id = story_reactions.story_id
        and s.author_id <> (select auth.uid())
        and s.expires_at > now()
        and private.can_view_story(s.author_id)
    )
  );

drop policy if exists "Story owners and reactors can read reactions" on public.story_reactions;
create policy "Story owners and reactors can read reactions"
  on public.story_reactions for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.stories s
      where s.id = story_reactions.story_id
        and s.author_id = (select auth.uid())
    )
  );

drop policy if exists "Eligible users can record story views" on public.story_views;
create policy "Eligible users can record story views"
  on public.story_views for insert to authenticated
  with check (
    viewer_id = (select auth.uid())
    and exists (
      select 1
      from public.stories s
      where s.id = story_views.story_id
        and s.author_id <> (select auth.uid())
        and s.expires_at > now()
        and private.can_view_story(s.author_id)
    )
  );

drop policy if exists "Story owners and viewers can read view records" on public.story_views;
create policy "Story owners and viewers can read view records"
  on public.story_views for select to authenticated
  using (
    viewer_id = (select auth.uid())
    or exists (
      select 1 from public.stories s
      where s.id = story_views.story_id
        and s.author_id = (select auth.uid())
    )
  );
