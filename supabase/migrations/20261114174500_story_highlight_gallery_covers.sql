alter table public.story_highlights
  add column if not exists cover_image_path text;

alter table public.story_highlights
  drop constraint if exists story_highlights_cover_image_owner_path_check;

alter table public.story_highlights
  add constraint story_highlights_cover_image_owner_path_check
  check (
    cover_image_path is null
    or (
      split_part(cover_image_path, '/', 1) = owner_id::text
      and cover_image_path like owner_id::text || '/highlights/%'
      and position('..' in cover_image_path) = 0
    )
  );