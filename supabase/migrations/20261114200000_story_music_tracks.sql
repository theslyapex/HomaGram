-- Private user-selected soundtrack files for stories.
alter table public.stories
  add column if not exists music_path text,
  add column if not exists music_start_ms integer not null default 0,
  add column if not exists music_volume numeric(3,2) not null default 0.75;

alter table public.stories
  drop constraint if exists stories_music_start_ms_valid,
  add constraint stories_music_start_ms_valid check (music_start_ms between 0 and 600000),
  drop constraint if exists stories_music_volume_valid,
  add constraint stories_music_volume_valid check (music_volume between 0 and 1);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'story-audio',
  'story-audio',
  false,
  15728640,
  array['audio/mpeg','audio/mp4','audio/aac','audio/wav','audio/x-wav']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Story music owners can upload files" on storage.objects;
create policy "Story music owners can upload files"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'story-audio'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Viewers can read music attached to visible stories" on storage.objects;
create policy "Viewers can read music attached to visible stories"
on storage.objects for select to authenticated
using (
  bucket_id = 'story-audio'
  and exists (
    select 1
    from public.stories s
    where s.music_path = objects.name
      and (
        s.author_id = (select auth.uid())
        or (s.expires_at > now() and private.can_view_story(s.author_id))
        or private.story_is_in_visible_highlight(s.id)
      )
  )
);

drop policy if exists "Users can delete their own story music files" on storage.objects;
create policy "Users can delete their own story music files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'story-audio'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
