create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  author_username text not null,
  author_display_name text not null,
  caption text not null default '',
  media_path text,
  media_type text check (media_type in ('image','video') or media_type is null),
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint posts_caption_length check (char_length(caption) <= 2200),
  constraint posts_media_consistency check ((media_path is null and media_type is null) or (media_path is not null and media_type is not null)),
  constraint posts_content_required check (char_length(trim(caption)) > 0 or media_path is not null)
);
create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_author_created_at_idx on public.posts (author_id, created_at desc);
alter table public.posts enable row level security;
grant select, insert, delete on public.posts to authenticated;
create policy "Users can read public posts and their own posts" on public.posts for select to authenticated using (is_public = true or author_id = (select auth.uid()));
create policy "Users can create their own posts" on public.posts for insert to authenticated with check (author_id = (select auth.uid()) and char_length(trim(caption)) <= 2200);
create policy "Users can delete their own posts" on public.posts for delete to authenticated using (author_id = (select auth.uid()));
create or replace function public.set_post_visibility()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.author_id <> (select auth.uid()) then raise exception 'invalid post author'; end if;
  select not s.is_private into new.is_public from public.account_settings s where s.user_id = new.author_id;
  if new.is_public is null then new.is_public := false; end if;
  return new;
end;
$$;
revoke all on function public.set_post_visibility() from public, anon, authenticated;
drop trigger if exists set_post_visibility_before_insert on public.posts;
create trigger set_post_visibility_before_insert before insert on public.posts for each row execute function public.set_post_visibility();
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('post-media','post-media',false,52428800,array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime'])
on conflict (id) do update set public=false,file_size_limit=52428800,allowed_mime_types=array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime'];
create policy "Users can upload their own post media" on storage.objects for insert to authenticated with check (bucket_id='post-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Users can read media attached to visible posts" on storage.objects for select to authenticated using (bucket_id='post-media' and exists (select 1 from public.posts p where p.media_path = name and (p.is_public = true or p.author_id = (select auth.uid()))));
create policy "Users can delete their own post media" on storage.objects for delete to authenticated using (bucket_id='post-media' and (storage.foldername(name))[1]=(select auth.uid())::text);