alter table public.stories
  drop constraint if exists stories_overlay_font_check;

alter table public.stories
  add constraint stories_overlay_font_check
  check (overlay_font in (
    'estedad', 'serif', 'mono',
    'vazirmatn', 'cairo', 'amiri', 'markazi', 'lalezar'
  ));

comment on column public.stories.overlay_font is
  'Approved Persian-ready typography preset for the story text overlay.';
