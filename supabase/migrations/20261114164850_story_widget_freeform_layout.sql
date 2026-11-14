alter table public.stories
  add column if not exists widget_layout jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.stories'::regclass
      and conname = 'stories_widget_layout_object_check'
  ) then
    alter table public.stories
      add constraint stories_widget_layout_object_check
      check (jsonb_typeof(widget_layout) = 'object');
  end if;
end
$$;
