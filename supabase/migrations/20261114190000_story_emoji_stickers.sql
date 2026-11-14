alter table public.stories
  add column if not exists sticker_data jsonb not null default '[]'::jsonb;

alter table public.stories
  drop constraint if exists stories_sticker_data_valid;

alter table public.stories
  add constraint stories_sticker_data_valid
  check (
    jsonb_typeof(sticker_data) = 'array'
    and jsonb_array_length(sticker_data) <= 20
  );

comment on column public.stories.sticker_data is
  'Validated emoji sticker overlays for image and video stories; normalized positions and scale are validated by the client.';
