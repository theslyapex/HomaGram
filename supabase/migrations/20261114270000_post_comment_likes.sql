-- Secure per-user likes for post comments.
create table if not exists public.post_comment_likes (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.post_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (comment_id, user_id)
);
create index if not exists post_comment_likes_comment_idx on public.post_comment_likes(comment_id);
alter table public.post_comment_likes enable row level security;
grant select, insert, delete on public.post_comment_likes to authenticated;
drop policy if exists "Comment likes visible for readable posts" on public.post_comment_likes;
create policy "Comment likes visible for readable posts"
on public.post_comment_likes for select to authenticated
using (exists (
  select 1 from public.post_comments c join public.posts p on p.id = c.post_id
  where c.id = post_comment_likes.comment_id
));
drop policy if exists "Users can like comments as themselves" on public.post_comment_likes;
create policy "Users can like comments as themselves"
on public.post_comment_likes for insert to authenticated
with check (user_id = (select auth.uid()) and exists (
  select 1 from public.post_comments c join public.posts p on p.id = c.post_id
  where c.id = post_comment_likes.comment_id
));
drop policy if exists "Users can remove their own comment likes" on public.post_comment_likes;
create policy "Users can remove their own comment likes"
on public.post_comment_likes for delete to authenticated
using (user_id = (select auth.uid()));
