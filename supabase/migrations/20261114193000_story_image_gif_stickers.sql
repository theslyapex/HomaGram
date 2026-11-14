-- Private image and animated GIF sticker assets for stories.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'story-stickers',
  'story-stickers',
  false,
  5242880,
  array['image/gif','image/jpeg','image/png','image/webp']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Story sticker owners can upload files" on storage.objects;
create policy "Story sticker owners can upload files"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'story-stickers'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Viewers can read stickers attached to visible stories" on storage.objects;
create policy "Viewers can read stickers attached to visible stories"
on storage.objects for select to authenticated
using (
  bucket_id = 'story-stickers'
  and exists (
    select 1
    from public.stories s
    where s.sticker_data @> jsonb_build_array(jsonb_build_object('path', objects.name))
      and (
        s.author_id = (select auth.uid())
        or (s.expires_at > now() and private.can_view_story(s.author_id))
        or private.story_is_in_visible_highlight(s.id)
      )
  )
);

drop policy if exists "Users can delete their own story sticker files" on storage.objects;
create policy "Users can delete their own story sticker files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'story-stickers'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
