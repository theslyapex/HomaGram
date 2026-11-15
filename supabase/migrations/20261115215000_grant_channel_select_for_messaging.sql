-- The message INSERT policy checks channel membership and permissions through
-- public.channels. The table already has a restrictive SELECT RLS policy for
-- public channels and users who are members; grant the table privilege needed
-- for that policy to be evaluated without exposing private channel rows.
grant select on public.channels to authenticated;
