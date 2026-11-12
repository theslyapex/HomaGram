-- Keep story visibility consistent with user blocking in both row and media policies.
create or replace function private.can_view_story(p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    p_author_id = auth.uid()
    or (
      not exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = p_author_id)
           or (b.blocker_id = p_author_id and b.blocked_id = auth.uid())
      )
      and (
        not coalesce(
          (select s.is_private from public.account_settings s where s.user_id = p_author_id),
          false
        )
        or exists (
          select 1 from public.user_follows f
          where f.follower_id = auth.uid()
            and f.following_id = p_author_id
        )
      )
    );
$$;
revoke all on function private.can_view_story(uuid) from public;
grant execute on function private.can_view_story(uuid) to authenticated;
