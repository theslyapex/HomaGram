create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create or replace function private.can_view_follow_relationship(
  p_follower_id uuid,
  p_following_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and (
      auth.uid() = p_follower_id
      or auth.uid() = p_following_id
      or (
        exists (
          select 1
          from public.account_settings follower_settings
          where follower_settings.user_id = p_follower_id
            and follower_settings.show_following = true
        )
        and exists (
          select 1
          from public.account_settings followed_settings
          where followed_settings.user_id = p_following_id
            and followed_settings.show_followers = true
        )
      )
    );
$$;

revoke all on function private.can_view_follow_relationship(uuid, uuid) from public, anon;
grant execute on function private.can_view_follow_relationship(uuid, uuid) to authenticated;

drop policy if exists "Follow relationships respect both users privacy choices"
  on public.user_follows;

create policy "Follow relationships respect both users privacy choices"
  on public.user_follows
  for select
  to authenticated
  using (
    private.can_view_follow_relationship(follower_id, following_id)
  );
