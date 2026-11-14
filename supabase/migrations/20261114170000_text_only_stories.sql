-- Support text-only stories while preserving existing image/video rows.
alter table public.stories
  alter column media_path drop not null;

alter table public.stories
  drop constraint if exists stories_media_type_check;

alter table public.stories
  add constraint stories_media_type_check
  check (media_type in ('image', 'video', 'text'));

alter table public.stories
  add column if not exists text_content text,
  add column if not exists background_key text not null default 'aurora';

alter table public.stories
  add constraint stories_text_content_length_check
  check (text_content is null or char_length(text_content) <= 1000);

alter table public.stories
  add constraint stories_background_key_check
  check (background_key in ('aurora', 'sunset', 'ocean', 'forest', 'midnight', 'rose'));

alter table public.stories
  add constraint stories_content_by_type_check
  check (
    (media_type = 'text'
      and media_path is null
      and text_content is not null
      and char_length(btrim(text_content)) between 1 and 1000)
    or
    (media_type in ('image', 'video')
      and media_path is not null
      and text_content is null)
  );

comment on column public.stories.text_content is
  'Body for text-only stories; null for image/video stories.';
comment on column public.stories.background_key is
  'Preset background identifier for text-only stories.';
