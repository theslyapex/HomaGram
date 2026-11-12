-- Story foundation: private media, 24-hour expiry, audience checks, views and reactions.
create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  media_path text not null unique,
  media_type text not null check (media_type in ('image','video')),
  caption text not null default '' check (char_length(caption) <= 500),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint stories_expiry_after_creation check (expires_at > created_at)
);
create index if not exists stories_active_by_author_idx on public.stories (author_id, expires_at desc);
create index if not exists stories_active_expiry_idx on public.stories (expires_at);

create table if not exists public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);
create index if not exists story_views_viewer_idx on public.story_views (viewer_id, viewed_at desc);

create table if not exists public.story_reactions (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);

alter table public.stories enable row level security;
alter table public.story_views enable row level security;
alter table public.story_reactions enable row level security;

create or replace function private.can_view_story(p_author_id uuid)
returns boolean language sql stable security definer
set search_path = public, auth
as $$
  select p_author_id = auth.uid()
    or not coalesce((select s.is_private from public.account_settings s where s.user_id = p_author_id), false)
    or exists (select 1 from public.user_follows f
      where f.follower_id = auth.uid() and f.following_id = p_author_id);
$$;
revoke all on function private.can_view_story(uuid) from public;
grant execute on function private.can_view_story(uuid) to authenticated;

drop policy if exists "Visible stories can be read by their audience" on public.stories;
create policy "Visible stories can be read by their audience" on public.stories
for select to authenticated using (
  author_id = auth.uid() or (expires_at > now() and private.can_view_story(author_id))
);
drop policy if exists "Users can publish their own stories" on public.stories;
create policy "Users can publish their own stories" on public.stories
for insert to authenticated with check (
  author_id = auth.uid() and expires_at > now()
  and expires_at <= now() + interval '24 hours 5 minutes'
);
drop policy if exists "Users can delete their own stories" on public.stories;
create policy "Users can delete their own stories" on public.stories
for delete to authenticated using (author_id = auth.uid());

drop policy if exists "Story owners and viewers can read view records" on public.story_views;
create policy "Story owners and viewers can read view records" on public.story_views
for select to authenticated using (
  viewer_id = auth.uid()
  or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
);
drop policy if exists "Eligible users can record story views" on public.story_views;
create policy "Eligible users can record story views" on public.story_views
for insert to authenticated with check (
  viewer_id = auth.uid() and exists (
    select 1 from public.stories s where s.id = story_id
      and s.author_id <> auth.uid() and s.expires_at > now()
      and private.can_view_story(s.author_id)
  )
);

drop policy if exists "Story owners and reactors can read reactions" on public.story_reactions;
create policy "Story owners and reactors can read reactions" on public.story_reactions
for select to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
);
drop policy if exists "Eligible users can react to stories" on public.story_reactions;
create policy "Eligible users can react to stories" on public.story_reactions
for insert to authenticated with check (
  user_id = auth.uid() and exists (
    select 1 from public.stories s where s.id = story_id
      and s.author_id <> auth.uid() and s.expires_at > now()
      and private.can_view_story(s.author_id)
  )
);
drop policy if exists "Users can change their story reaction" on public.story_reactions;
create policy "Users can change their story reaction" on public.story_reactions
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "Users can remove their story reaction" on public.story_reactions;
create policy "Users can remove their story reaction" on public.story_reactions
for delete to authenticated using (user_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('story-media','story-media',false,52428800,
  array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime'])
on conflict (id) do update set public=false, file_size_limit=52428800,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Story audience can read story media" on storage.objects;
create policy "Story audience can read story media" on storage.objects
for select to authenticated using (
  bucket_id = 'story-media' and exists (
    select 1 from public.stories s where s.media_path = objects.name
      and (s.author_id = auth.uid()
        or (s.expires_at > now() and private.can_view_story(s.author_id)))
  )
);
drop policy if exists "Users can upload their own story media" on storage.objects;
create policy "Users can upload their own story media" on storage.objects
for insert to authenticated with check (
  bucket_id = 'story-media' and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists "Users can delete their own story media" on storage.objects;
create policy "Users can delete their own story media" on storage.objects
for delete to authenticated using (
  bucket_id = 'story-media' and (storage.foldername(name))[1] = auth.uid()::text
);
