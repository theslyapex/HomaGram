create or replace function public.sync_posts_privacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.posts
  set is_public = not new.is_private, updated_at = now()
  where author_id = new.user_id;
  return new;
end;
$$;
revoke all on function public.sync_posts_privacy() from public, anon, authenticated;
drop trigger if exists sync_posts_privacy_after_update on public.account_settings;
create trigger sync_posts_privacy_after_update
after update of is_private on public.account_settings
for each row
when (old.is_private is distinct from new.is_private)
execute function public.sync_posts_privacy();