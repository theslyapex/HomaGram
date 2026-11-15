-- Expanded user content reports and administrator content inventory.
alter table public.post_reports
  drop constraint if exists post_reports_reason_check;
alter table public.post_reports
  add constraint post_reports_reason_check
  check (reason in (
    'spam','harassment','misinformation','inappropriate','other',
    'copied_content','copyright_claim','violence','political_insult','illegal_content'
  ));

alter table public.post_reports
  add column if not exists rights_owner text,
  add column if not exists rights_holder_name text;
alter table public.post_reports
  drop constraint if exists post_reports_rights_owner_check;
alter table public.post_reports
  add constraint post_reports_rights_owner_check
  check (rights_owner is null or rights_owner in ('self','third_party'));

create index if not exists posts_created_at_moderation_idx
  on public.posts(created_at desc);
create index if not exists profiles_updated_at_moderation_idx
  on public.profiles(updated_at desc);

create or replace function private.admin_list_moderation_content(
  p_content_type text default 'all',
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  content_type text, content_id uuid, author_id uuid, username text,
  display_name text, caption text, media_path text, cover_path text,
  media_type text, created_at timestamptz, bio text, avatar_path text,
  is_verified boolean
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_content_type not in ('all','post','reel','profile') then
    raise exception 'Invalid content type' using errcode = '22023';
  end if;
  return query
  select x.content_type,x.content_id,x.author_id,x.username,x.display_name,
         x.caption,x.media_path,x.cover_path,x.media_type,x.created_at,
         x.bio,x.avatar_path,x.is_verified
  from (
    select case when p.is_reel then 'reel'::text else 'post'::text end,
      p.id,p.author_id,coalesce(pr.username,p.author_username),
      coalesce(pr.display_name,p.author_display_name),p.caption,p.media_path,
      p.cover_path,p.media_type,p.created_at,pr.bio,pr.avatar_path,
      coalesce(pr.is_verified,false)
    from public.posts p left join public.profiles pr on pr.id=p.author_id
    union all
    select 'profile'::text,pr.id,pr.id,pr.username,pr.display_name,
      pr.bio,null::text,null::text,null::text,pr.updated_at,pr.bio,
      pr.avatar_path,coalesce(pr.is_verified,false)
    from public.profiles pr
  ) x(content_type,content_id,author_id,username,display_name,caption,
      media_path,cover_path,media_type,created_at,bio,avatar_path,is_verified)
  where p_content_type='all' or x.content_type=p_content_type
  order by x.created_at desc nulls last
  limit least(greatest(coalesce(p_limit,50),1),100)
  offset greatest(coalesce(p_offset,0),0);
end;
$$;
revoke all on function private.admin_list_moderation_content(text,integer,integer) from public,anon;
grant execute on function private.admin_list_moderation_content(text,integer,integer) to authenticated;

create or replace function public.admin_list_moderation_content(
  p_content_type text default 'all', p_limit integer default 50, p_offset integer default 0
)
returns table (
  content_type text, content_id uuid, author_id uuid, username text,
  display_name text, caption text, media_path text, cover_path text,
  media_type text, created_at timestamptz, bio text, avatar_path text,
  is_verified boolean
)
language sql stable security invoker set search_path = ''
as $$ select * from private.admin_list_moderation_content(p_content_type,p_limit,p_offset); $$;
revoke all on function public.admin_list_moderation_content(text,integer,integer) from public,anon;
grant execute on function public.admin_list_moderation_content(text,integer,integer) to authenticated;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
 check(type in (
  'follow','post_like','post_comment','comment_reply','post_repost',
  'story_reaction','message_new','support_message','support_reply',
  'verification_update','moderation_notice'
 ));
