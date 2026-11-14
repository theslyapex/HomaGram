alter table public.stories
  add column if not exists overlay_font text not null default 'estedad';

alter table public.stories
  drop constraint if exists stories_overlay_color_check;

alter table public.stories
  add constraint stories_overlay_color_check
  check (overlay_color in ('#FFFFFF', '#111827', '#FFE082', '#FF6B6B', '#45D6C5', '#A78BFA', '#F9A8D4'));

alter table public.stories
  add constraint stories_overlay_font_check
  check (overlay_font in ('estedad', 'serif', 'mono'));

comment on column public.stories.overlay_font is
  'Approved typography preset for the story text overlay.';
