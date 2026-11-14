-- Explicit client privileges are still constrained by the RLS policies.
grant select, insert, delete on table public.stories to authenticated;
grant select, insert on table public.story_views to authenticated;
grant select, insert, update, delete on table public.story_reactions to authenticated;
