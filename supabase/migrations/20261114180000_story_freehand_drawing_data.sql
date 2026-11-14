alter table public.stories add column if not exists drawing_data jsonb not null default '[]'::jsonb;

alter table public.stories drop constraint if exists stories_drawing_data_check;
alter table public.stories add constraint stories_drawing_data_check check (jsonb_typeof(drawing_data) = 'array' and jsonb_array_length(drawing_data) <= 100);

comment on column public.stories.drawing_data is 'Normalized freehand drawing strokes for image/video stories; points use normalized 0..1 coordinates.';
