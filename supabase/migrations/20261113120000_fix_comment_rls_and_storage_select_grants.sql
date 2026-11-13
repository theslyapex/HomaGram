-- Fix storage policy evaluation and prevent recursive comment RLS.
-- RLS remains enabled; the existing attachment SELECT policy limits rows to active conversation members.
grant select on table public.message_attachments to authenticated;

-- Enforce that a reply points to a comment on the same post without querying
-- post_comments from its own RLS policy (which caused infinite recursion).
alter table public.post_comments
  add constraint post_comments_id_post_id_key unique (id, post_id);

alter table public.post_comments
  drop constraint post_comments_parent_id_fkey;

alter table public.post_comments
  add constraint post_comments_parent_same_post_fkey
  foreign key (parent_id, post_id)
  references public.post_comments (id, post_id)
  on delete cascade;

drop policy if exists "Users can comment as themselves" on public.post_comments;

create policy "Users can comment as themselves"
on public.post_comments
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.posts p
    where p.id = post_comments.post_id
  )
);
