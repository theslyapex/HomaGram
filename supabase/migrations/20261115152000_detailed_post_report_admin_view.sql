create or replace function private.admin_list_post_reports_detailed(
  p_limit integer default 50,p_offset integer default 0
)
returns table(
  report_id uuid,post_id uuid,reporter_id uuid,reason text,details text,
  rights_owner text,rights_holder_name text,status text,created_at timestamptz,
  review_note text,post_author_id uuid,post_caption text,media_path text,
  cover_path text,media_type text,is_reel boolean,author_username text,
  author_display_name text
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  return query
  select r.id,r.post_id,r.reporter_id,r.reason,r.details,r.rights_owner,
    r.rights_holder_name,r.status,r.created_at,r.review_note,p.author_id,
    p.caption,p.media_path,p.cover_path,p.media_type,p.is_reel,
    coalesce(pr.username,p.author_username),coalesce(pr.display_name,p.author_display_name)
  from public.post_reports r
  left join public.posts p on p.id=r.post_id
  left join public.profiles pr on pr.id=p.author_id
  order by case when r.status='pending' then 0 else 1 end,r.created_at desc
  limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;
revoke all on function private.admin_list_post_reports_detailed(integer,integer) from public,anon;
grant execute on function private.admin_list_post_reports_detailed(integer,integer) to authenticated;
create or replace function public.admin_list_post_reports_detailed(
  p_limit integer default 50,p_offset integer default 0
)
returns table(
  report_id uuid,post_id uuid,reporter_id uuid,reason text,details text,
  rights_owner text,rights_holder_name text,status text,created_at timestamptz,
  review_note text,post_author_id uuid,post_caption text,media_path text,
  cover_path text,media_type text,is_reel boolean,author_username text,
  author_display_name text
)
language sql stable security invoker set search_path=''
as $$ select * from private.admin_list_post_reports_detailed(p_limit,p_offset); $$;
revoke all on function public.admin_list_post_reports_detailed(integer,integer) from public,anon;
grant execute on function public.admin_list_post_reports_detailed(integer,integer) to authenticated;
