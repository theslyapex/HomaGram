-- Persist one editable text overlay on image/video stories.
alter table public.stories
  add column if not exists overlay_text text,
  add column if not exists overlay_x real not null default 0.5,
  add column if not exists overlay_y real not null default 0.5,
  add column if not exists overlay_scale real not null default 1.0,
  add column if not exists overlay_color text not null default '#FFFFFF';

alter table public.stories
  add constraint stories_overlay_text_length_check
  check (overlay_text is null or char_length(overlay_text) between 1 and 180);

alter table public.stories
  add constraint stories_overlay_position_check
  check (overlay_x between 0.0 and 1.0 and overlay_y between 0.0 and 1.0);

alter table public.stories
  add constraint stories_overlay_scale_check
  check (overlay_scale between 0.6 and 2.5);

alter table public.stories
  add constraint stories_overlay_color_check
  check (overlay_color in ('#FFFFFF', '#111827', '#FFE082'));

alter table public.stories
  add constraint stories_overlay_media_type_check
  check (overlay_text is null or media_type in ('image', 'video'));

comment on column public.stories.overlay_text is
  'Optional movable text overlay displayed on image/video stories.';
comment on column public.stories.overlay_x is
  'Horizontal normalized center position for the text overlay (0..1).';
comment on column public.stories.overlay_y is
  'Vertical normalized center position for the text overlay (0..1).';
comment on column public.stories.overlay_scale is
  'Scale multiplier for the text overlay (0.6..2.5).';
comment on column public.stories.overlay_color is
  'Approved text color for the story overlay.';
