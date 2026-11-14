-- Reels are public vertical videos backed by the existing post-media bucket and social interactions.
alter table public.posts
  add column if not exists is_reel boolean not null default false;

alter table public.posts
  drop constraint if exists posts_reel_requires_video;
alter table public.posts
  add constraint posts_reel_requires_video
  check (not is_reel or (media_path is not null and media_type = 'video'));

create index if not exists posts_public_reels_created_idx
  on public.posts (created_at desc)
  where is_reel = true and is_public = true;

create index if not exists posts_author_reels_created_idx
  on public.posts (author_id, created_at desc)
  where is_reel = true;
