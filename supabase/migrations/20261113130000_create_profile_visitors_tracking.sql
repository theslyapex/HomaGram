create table if not exists public.profile_views (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  constraint profile_views_not_self check (profile_id <> viewer_id),
  constraint profile_views_profile_viewer_unique unique (profile_id, viewer_id)
);

create index if not exists profile_views_profile_viewed_at_idx
  on public.profile_views (profile_id, viewed_at desc);
create index if not exists profile_views_viewer_id_idx
  on public.profile_views (viewer_id);

alter table public.profile_views enable row level security;

revoke all on public.profile_views from anon, public;
grant select, insert, update on public.profile_views to authenticated;

drop policy if exists "Users can record profile visits" on public.profile_views;
create policy "Users can record profile visits"
  on public.profile_views for insert to authenticated
  with check (
    (select auth.uid()) = viewer_id
    and profile_id <> (select auth.uid())
  );

drop policy if exists "Visitors can refresh their own profile visit" on public.profile_views;
create policy "Visitors can refresh their own profile visit"
  on public.profile_views for update to authenticated
  using ((select auth.uid()) = viewer_id)
  with check (
    (select auth.uid()) = viewer_id
    and profile_id <> (select auth.uid())
  );

drop policy if exists "Users can read permitted profile visits" on public.profile_views;
create policy "Users can read permitted profile visits"
  on public.profile_views for select to authenticated
  using (
    (select auth.uid()) = viewer_id
    or (
      (select auth.uid()) = profile_id
      and exists (
        select 1 from public.account_settings s
        where s.user_id = profile_views.profile_id
          and s.show_profile_visitors = true
      )
    )
  );
