revoke all on function public.get_close_friends() from public, anon;
revoke all on function public.add_close_friend(uuid) from public, anon;
revoke all on function public.remove_close_friend(uuid) from public, anon;
grant execute on function public.get_close_friends() to authenticated;
grant execute on function public.add_close_friend(uuid) to authenticated;
grant execute on function public.remove_close_friend(uuid) to authenticated;

create or replace function private.remove_close_friend(p_friend_id uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  delete from public.close_friends
  where owner_id = auth.uid() and friend_id = p_friend_id;
end;
$$;
revoke all on function private.remove_close_friend(uuid) from public, anon;
grant execute on function private.remove_close_friend(uuid) to authenticated;
