-- Cover story lookups happen when rendering each profile's highlight collection.
create index if not exists story_highlights_cover_story_id_idx
  on public.story_highlights (cover_story_id)
  where cover_story_id is not null;
