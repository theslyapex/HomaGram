alter table public.account_settings
  add column if not exists show_followers boolean not null default true,
  add column if not exists show_following boolean not null default true,
  add column if not exists show_profile_visitors boolean not null default true;

drop policy if exists "Follow relationships are visible to authenticated users"
  on public.user_follows;

create policy "Follow relationships respect both users privacy choices"
  on public.user_follows
  for select
  to authenticated
  using (
    (select auth.uid()) = follower_id
    or (select auth.uid()) = following_id
    or (
      exists (
        select 1
        from public.account_settings follower_settings
        where follower_settings.user_id = user_follows.follower_id
          and follower_settings.show_following = true
      )
      and exists (
        select 1
        from public.account_settings followed_settings
        where followed_settings.user_id = user_follows.following_id
          and followed_settings.show_followers = true
      )
    )
  );
