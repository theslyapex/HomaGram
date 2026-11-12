-- HomaGram social graph and post interactions.
alter table public.profiles add column if not exists avatar_path text;

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Authenticated users can view profile cards"
on public.profiles for select to authenticated using (true);

drop policy if exists "Users can read their own avatars" on storage.objects;
create policy "Authenticated users can view profile avatars"
on storage.objects for select to authenticated using (bucket_id = 'avatars');

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_likes enable row level security;
grant select, insert, delete on public.post_likes to authenticated;
create policy "Likes are visible to authenticated users" on public.post_likes for select to authenticated using (true);
create policy "Users can like posts as themselves" on public.post_likes for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users can remove their own likes" on public.post_likes for delete to authenticated using (user_id = (select auth.uid()));

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.post_comments(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists post_comments_post_created_idx on public.post_comments(post_id, created_at);
alter table public.post_comments enable row level security;
grant select, insert, delete on public.post_comments to authenticated;
create policy "Comments are visible for readable posts" on public.post_comments for select to authenticated
using (exists (select 1 from public.posts p where p.id = post_id));
create policy "Users can comment as themselves" on public.post_comments for insert to authenticated
with check (user_id = (select auth.uid()) and exists (select 1 from public.posts p where p.id = post_id)
and (parent_id is null or exists (select 1 from public.post_comments parent where parent.id = parent_id and parent.post_id = post_id)));
create policy "Users can delete their own comments" on public.post_comments for delete to authenticated using (user_id = (select auth.uid()));

create table if not exists public.user_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint user_follows_no_self check (follower_id <> following_id)
);
create index if not exists user_follows_following_idx on public.user_follows(following_id, created_at desc);
alter table public.user_follows enable row level security;
grant select, insert, delete on public.user_follows to authenticated;
create policy "Follow relationships are visible to authenticated users" on public.user_follows for select to authenticated using (true);
create policy "Users can follow as themselves" on public.user_follows for insert to authenticated with check (follower_id = (select auth.uid()));
create policy "Users can unfollow as themselves" on public.user_follows for delete to authenticated using (follower_id = (select auth.uid()));

create table if not exists public.post_reposts (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_reposts enable row level security;
grant select, insert, delete on public.post_reposts to authenticated;
create policy "Reposts are visible to authenticated users" on public.post_reposts for select to authenticated using (true);
create policy "Users can repost as themselves" on public.post_reposts for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users can remove their own reposts" on public.post_reposts for delete to authenticated using (user_id = (select auth.uid()));

create table if not exists public.saved_posts (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.saved_posts enable row level security;
grant select, insert, delete on public.saved_posts to authenticated;
create policy "Users can view their saved posts" on public.saved_posts for select to authenticated using (user_id = (select auth.uid()));
create policy "Users can save posts as themselves" on public.saved_posts for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users can unsave their own posts" on public.saved_posts for delete to authenticated using (user_id = (select auth.uid()));
