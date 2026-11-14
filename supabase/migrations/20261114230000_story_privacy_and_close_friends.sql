-- Per-story audience controls and Close Friends access.
alter table public.stories
  add column if not exists audience text not null default 'everyone'
  check (audience in ('everyone','followers','close_friends'));

create table if not exists public.close_friends (
  owner_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  constraint close_friends_no_self check (owner_id <> friend_id)
);
create index if not exists close_friends_friend_idx
  on public.close_friends(friend_id, owner_id);

alter table public.close_friends enable row level security;
revoke all on public.close_friends from anon, authenticated;
drop policy if exists "No direct access to close friends" on public.close_friends;
create policy "No direct access to close friends"
  on public.close_friends for all to anon, authenticated
  using (false) with check (false);

create or replace function private.can_view_story_content(p_story_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_story public.stories%rowtype;
  v_private boolean;
  v_blocked boolean;
  v_follows boolean;
  v_close_friend boolean;
begin
  if v_uid is null then return false; end if;
  select * into v_story from public.stories where id = p_story_id;
  if not found then return false; end if;
  if v_story.author_id = v_uid then return true; end if;

  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = v_uid and b.blocked_id = v_story.author_id)
       or (b.blocker_id = v_story.author_id and b.blocked_id = v_uid)
  ) into v_blocked;
  if v_blocked then return false; end if;

  select coalesce(s.is_private, false)
    into v_private
    from public.account_settings s
    where s.user_id = v_story.author_id;
  v_private := coalesce(v_private, false);

  select exists (
    select 1 from public.user_follows f
    where f.follower_id = v_uid and f.following_id = v_story.author_id
  ) into v_follows;

  if v_private and not v_follows then return false; end if;

  if v_story.audience = 'everyone' then
    return true;
  elsif v_story.audience = 'followers' then
    return v_follows;
  elsif v_story.audience = 'close_friends' then
    select exists (
      select 1 from public.close_friends cf
      where cf.owner_id = v_story.author_id and cf.friend_id = v_uid
    ) into v_close_friend;
    return v_close_friend;
  end if;
  return false;
end;
$$;
revoke all on function private.can_view_story_content(uuid) from public, anon;
grant execute on function private.can_view_story_content(uuid) to authenticated;

create or replace function private.story_is_in_visible_highlight(p_story_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.story_highlight_items hi
    join public.story_highlights h on h.id = hi.highlight_id
    join public.stories s on s.id = hi.story_id
    where hi.story_id = p_story_id
      and h.owner_id = s.author_id
      and private.can_view_story_content(s.id)
  );
$$;
revoke all on function private.story_is_in_visible_highlight(uuid) from public, anon;
grant execute on function private.story_is_in_visible_highlight(uuid) to authenticated;

create or replace function private.highlight_is_visible(p_highlight_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.story_highlight_items hi
    join public.stories s on s.id = hi.story_id
    where hi.highlight_id = p_highlight_id
      and private.can_view_story_content(s.id)
  );
$$;
revoke all on function private.highlight_is_visible(uuid) from public, anon;
grant execute on function private.highlight_is_visible(uuid) to authenticated;

drop policy if exists "Visible stories can be read by their audience" on public.stories;
create policy "Visible stories can be read by their audience"
  on public.stories for select to authenticated
  using (
    author_id = (select auth.uid())
    or (expires_at > now() and private.can_view_story_content(id))
    or private.story_is_in_visible_highlight(id)
  );

drop policy if exists "Eligible users can record story views" on public.story_views;
create policy "Eligible users can record story views"
  on public.story_views for insert to authenticated
  with check (
    viewer_id = (select auth.uid())
    and exists (
      select 1 from public.stories s
      where s.id = story_views.story_id
        and s.author_id <> (select auth.uid())
        and s.expires_at > now()
        and private.can_view_story_content(s.id)
    )
  );

drop policy if exists "Eligible users can react to stories" on public.story_reactions;
create policy "Eligible users can react to stories"
  on public.story_reactions for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.stories s
      where s.id = story_reactions.story_id
        and s.author_id <> (select auth.uid())
        and s.expires_at > now()
        and private.can_view_story_content(s.id)
    )
  );

drop policy if exists "Visible story highlights can be read" on public.story_highlights;
create policy "Visible story highlights can be read"
  on public.story_highlights for select to authenticated
  using (
    owner_id = (select auth.uid())
    or private.highlight_is_visible(id)
  );

drop policy if exists "Visible story highlight items can be read" on public.story_highlight_items;
create policy "Visible story highlight items can be read"
  on public.story_highlight_items for select to authenticated
  using (
    exists (
      select 1 from public.story_highlights h
      where h.id = story_highlight_items.highlight_id
        and h.owner_id = (select auth.uid())
    )
    or private.can_view_story_content(story_id)
  );

drop policy if exists "Story audience can read story media" on storage.objects;
create policy "Story audience can read story media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'story-media'
    and exists (
      select 1 from public.stories s
      where s.media_path = objects.name
        and (
          s.author_id = (select auth.uid())
          or (s.expires_at > now() and private.can_view_story_content(s.id))
          or private.story_is_in_visible_highlight(s.id)
        )
    )
  );

drop policy if exists "Viewers can read stickers attached to visible stories" on storage.objects;
create policy "Viewers can read stickers attached to visible stories"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'story-stickers'
    and exists (
      select 1 from public.stories s
      where s.sticker_data @> jsonb_build_array(jsonb_build_object('path', objects.name))
        and (
          s.author_id = (select auth.uid())
          or (s.expires_at > now() and private.can_view_story_content(s.id))
          or private.story_is_in_visible_highlight(s.id)
        )
    )
  );

drop policy if exists "Viewers can read music attached to visible stories" on storage.objects;
create policy "Viewers can read music attached to visible stories"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'story-audio'
    and exists (
      select 1 from public.stories s
      where s.music_path = objects.name
        and (
          s.author_id = (select auth.uid())
          or (s.expires_at > now() and private.can_view_story_content(s.id))
          or private.story_is_in_visible_highlight(s.id)
        )
    )
  );

-- Existing story widgets must use the same audience decision as the story itself.
create or replace function private.get_story_polls(p_story_ids uuid[])
returns jsonb language plpgsql stable security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id, 'story_id', p.story_id, 'question', p.question,
      'options', p.options,
      'counts', (
        select coalesce(jsonb_agg(
          (select count(*) from public.story_poll_votes v
           where v.poll_id = p.id and v.option_index = (o.ordinality - 1))
          order by o.ordinality
        ), '[]'::jsonb)
        from jsonb_array_elements_text(p.options) with ordinality o(value, ordinality)
      ),
      'total_votes', (select count(*) from public.story_poll_votes v where v.poll_id = p.id),
      'my_option', (select v.option_index from public.story_poll_votes v
                    where v.poll_id = p.id and v.user_id = v_uid limit 1)
    ) order by p.created_at
  ), '[]'::jsonb) into v_result
  from public.story_polls p join public.stories s on s.id = p.story_id
  where p.story_id = any(coalesce(p_story_ids, array[]::uuid[]))
    and (
      s.author_id = v_uid
      or (s.expires_at > now() and private.can_view_story_content(s.id))
      or private.story_is_in_visible_highlight(s.id)
    );
  return v_result;
end;
$$;

create or replace function private.submit_story_poll_vote(p_poll_id uuid, p_option_index integer)
returns jsonb language plpgsql security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_poll public.story_polls%rowtype;
  v_story public.stories%rowtype;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select p.* into v_poll from public.story_polls p where p.id = p_poll_id for update;
  if not found then raise exception 'Poll not found'; end if;
  select s.* into v_story from public.stories s where s.id = v_poll.story_id;
  if v_story.author_id = v_uid or v_story.expires_at <= now()
     or not private.can_view_story_content(v_story.id) then
    raise exception 'You cannot vote in this poll';
  end if;
  if p_option_index < 0 or p_option_index >= jsonb_array_length(v_poll.options) then
    raise exception 'Invalid poll option';
  end if;
  insert into public.story_poll_votes(poll_id, user_id, option_index)
  values (p_poll_id, v_uid, p_option_index)
  on conflict (poll_id, user_id)
  do update set option_index = excluded.option_index, created_at = now();
  v_result := private.get_story_polls(array[v_story.id]);
  return coalesce(v_result -> 0, '{}'::jsonb);
end;
$$;

create or replace function private.get_story_questions(p_story_ids uuid[])
returns jsonb language plpgsql stable security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'story_id',q.story_id,'prompt',q.prompt,
    'response_count',(select count(*) from public.story_question_responses r where r.question_id=q.id),
    'my_response',(select r.response from public.story_question_responses r where r.question_id=q.id and r.user_id=v_uid limit 1),
    'responses',case when s.author_id=v_uid then (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',r.id,'user_id',r.user_id,'response',r.response,'created_at',r.created_at,
        'username',coalesce(p.username,'user'),'display_name',coalesce(p.display_name,'کاربر')
      ) order by r.created_at desc),'[]'::jsonb)
      from public.story_question_responses r
      left join public.profiles p on p.id=r.user_id
      where r.question_id=q.id
    ) else '[]'::jsonb end
  ) order by q.created_at),'[]'::jsonb) into v_result
  from public.story_questions q join public.stories s on s.id=q.story_id
  where q.story_id=any(coalesce(p_story_ids,array[]::uuid[]))
    and (s.author_id=v_uid
      or (s.expires_at>now() and private.can_view_story_content(s.id))
      or private.story_is_in_visible_highlight(s.id));
  return v_result;
end;
$$;

create or replace function private.submit_story_question_response(p_question_id uuid, p_response text)
returns jsonb language plpgsql security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_q public.story_questions%rowtype;
  v_story public.stories%rowtype;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if char_length(btrim(coalesce(p_response,''))) not between 1 and 1000 then
    raise exception 'Response must contain 1 to 1000 characters';
  end if;
  select * into v_q from public.story_questions where id=p_question_id;
  if not found then raise exception 'Question not found'; end if;
  select * into v_story from public.stories where id=v_q.story_id;
  if v_story.author_id=v_uid or v_story.expires_at<=now()
     or not private.can_view_story_content(v_story.id) then
    raise exception 'You cannot respond to this question';
  end if;
  insert into public.story_question_responses(question_id,user_id,response)
  values (p_question_id,v_uid,btrim(p_response))
  on conflict(question_id,user_id) do update
    set response=excluded.response,updated_at=now();
  v_result:=private.get_story_questions(array[v_q.story_id]);
  return coalesce(v_result->0,'{}'::jsonb);
end;
$$;

create or replace function private.get_story_countdowns(p_story_ids uuid[])
returns jsonb language plpgsql stable security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'story_id',c.story_id,'title',c.title,
    'target_at',c.target_at,'created_at',c.created_at,
    'is_completed',c.target_at <= now()
  ) order by c.created_at),'[]'::jsonb)
  into v_result
  from public.story_countdowns c
  join public.stories s on s.id=c.story_id
  where c.story_id=any(coalesce(p_story_ids,array[]::uuid[]))
    and (s.author_id=v_uid
      or (s.expires_at>now() and private.can_view_story_content(s.id))
      or private.story_is_in_visible_highlight(s.id));
  return v_result;
end;
$$;

-- Close Friends management is RPC-only; clients never receive direct table access.
create or replace function private.get_close_friends()
returns table(friend_id uuid, created_at timestamptz)
language sql stable security definer
set search_path = ''
as $$
  select cf.friend_id, cf.created_at
  from public.close_friends cf
  where cf.owner_id = auth.uid()
  order by cf.created_at desc;
$$;

create or replace function private.add_close_friend(p_friend_id uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_friend_id is null or p_friend_id = auth.uid() then
    raise exception 'Invalid Close Friend';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_friend_id) then
    raise exception 'User not found';
  end if;
  insert into public.close_friends(owner_id, friend_id)
  values (auth.uid(), p_friend_id)
  on conflict (owner_id, friend_id) do nothing;
end;
$$;

create or replace function private.remove_close_friend(p_friend_id uuid)
returns void language sql security definer
set search_path = ''
as $$
  delete from public.close_friends
  where owner_id = auth.uid() and friend_id = p_friend_id;
$$;

drop function if exists public.get_close_friends();
drop function if exists public.add_close_friend(uuid);
drop function if exists public.remove_close_friend(uuid);

create or replace function public.get_close_friends()
returns table(friend_id uuid, created_at timestamptz)
language sql stable security invoker
set search_path = public, private, auth
as $$ select * from private.get_close_friends(); $$;

create or replace function public.add_close_friend(p_friend_id uuid)
returns void language sql security invoker
set search_path = public, private, auth
as $$ select private.add_close_friend(p_friend_id); $$;

create or replace function public.remove_close_friend(p_friend_id uuid)
returns void language sql security invoker
set search_path = public, private, auth
as $$ select private.remove_close_friend(p_friend_id); $$;

grant usage on schema private to authenticated;
revoke all on function private.get_close_friends() from public, anon;
revoke all on function private.add_close_friend(uuid) from public, anon;
revoke all on function private.remove_close_friend(uuid) from public, anon;
grant execute on function private.get_close_friends() to authenticated;
grant execute on function private.add_close_friend(uuid) to authenticated;
grant execute on function private.remove_close_friend(uuid) to authenticated;

revoke all on function private.get_story_polls(uuid[]) from public, anon;
revoke all on function private.submit_story_poll_vote(uuid, integer) from public, anon;
revoke all on function private.get_story_questions(uuid[]) from public, anon;
revoke all on function private.submit_story_question_response(uuid, text) from public, anon;
revoke all on function private.get_story_countdowns(uuid[]) from public, anon;
grant execute on function private.get_story_polls(uuid[]) to authenticated;
grant execute on function private.submit_story_poll_vote(uuid, integer) to authenticated;
grant execute on function private.get_story_questions(uuid[]) to authenticated;
grant execute on function private.submit_story_question_response(uuid, text) to authenticated;
grant execute on function private.get_story_countdowns(uuid[]) to authenticated;
