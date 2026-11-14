alter table public.posts
  add column if not exists cover_path text;

alter table public.posts
  drop constraint if exists posts_cover_requires_video;

alter table public.posts
  add constraint posts_cover_requires_video
  check (cover_path is null or (media_type = 'video' and media_path is not null));

drop policy if exists "Users can read media attached to visible posts" on storage.objects;
drop policy if exists "Users can read post media and reel covers attached to visible posts" on storage.objects;

create policy "Users can read post media and reel covers attached to visible posts"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'post-media'
  and exists (
    select 1
    from public.posts p
    where (p.media_path = name or p.cover_path = name)
      and (p.is_public = true or p.author_id = (select auth.uid()))
  )
);
