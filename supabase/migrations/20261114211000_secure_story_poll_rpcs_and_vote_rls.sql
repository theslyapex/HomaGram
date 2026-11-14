-- Keep privileged poll logic outside the exposed API schema.
create or replace function private.create_story_poll(
  p_story_id uuid, p_question text, p_options jsonb
)
returns uuid language plpgsql security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_story public.stories%rowtype;
  v_option text;
  v_seen text[] := array[]::text[];
  v_question text := btrim(coalesce(p_question, ''));
  v_poll_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if char_length(v_question) not between 1 and 160 then
    raise exception 'Poll question must contain 1 to 160 characters';
  end if;
  if jsonb_typeof(p_options) <> 'array'
     or jsonb_array_length(p_options) not between 2 and 4 then
    raise exception 'A poll must contain between 2 and 4 options';
  end if;
  for v_option in select value from jsonb_array_elements_text(p_options)
  loop
    v_option := btrim(v_option);
    if char_length(v_option) not between 1 and 60
       or lower(v_option) = any(v_seen) then
      raise exception 'Poll options must be unique and contain 1 to 60 characters';
    end if;
    v_seen := array_append(v_seen, lower(v_option));
  end loop;
  select * into v_story from public.stories where id = p_story_id for update;
  if not found or v_story.author_id <> v_uid
     or v_story.expires_at <= now()
     or v_story.media_type not in ('image', 'video') then
    raise exception 'Story is not eligible for a poll';
  end if;
  insert into public.story_polls(story_id, question, options)
  values (
    p_story_id, v_question,
    (select jsonb_agg(to_jsonb(btrim(value)) order by ordinality)
     from jsonb_array_elements_text(p_options) with ordinality)
  ) returning id into v_poll_id;
  return v_poll_id;
end;
$$;

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
      or (s.expires_at > now() and private.can_view_story(s.author_id))
      or private.story_is_in_visible_highlight(s.id)
    );
  return v_result;
end;
$$;

create or replace function private.submit_story_poll_vote(
  p_poll_id uuid, p_option_index integer
)
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
  select p.* into v_poll from public.story_polls p
  where p.id = p_poll_id for update;
  if not found then raise exception 'Poll not found'; end if;
  select s.* into v_story from public.stories s where s.id = v_poll.story_id;
  if v_story.author_id = v_uid or v_story.expires_at <= now()
     or not private.can_view_story(v_story.author_id) then
    raise exception 'You cannot vote in this poll';
  end if;
  if p_option_index < 0 or p_option_index >= jsonb_array_length(v_poll.options) then
    raise exception 'Invalid poll option';
  end if;
  insert into public.story_poll_votes(poll_id, user_id, option_index)
  values (p_poll_id, v_uid, p_option_index)
  on conflict (poll_id, user_id)
  do update set option_index = excluded.option_index, created_at = now();
  v_result := private.get_story_polls(array[v_poll.story_id]);
  return coalesce(v_result -> 0, '{}'::jsonb);
end;
$$;

revoke all on function public.create_story_poll(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.get_story_polls(uuid[]) from public, anon, authenticated;
revoke all on function public.submit_story_poll_vote(uuid, integer) from public, anon, authenticated;
drop function if exists public.create_story_poll(uuid, text, jsonb);
drop function if exists public.get_story_polls(uuid[]);
drop function if exists public.submit_story_poll_vote(uuid, integer);

create or replace function public.create_story_poll(
  p_story_id uuid, p_question text, p_options jsonb
)
returns uuid language sql security invoker
set search_path = public, private, auth, pg_temp
as $$ select private.create_story_poll(p_story_id, p_question, p_options); $$;

create or replace function public.get_story_polls(p_story_ids uuid[])
returns jsonb language sql stable security invoker
set search_path = public, private, auth, pg_temp
as $$ select private.get_story_polls(p_story_ids); $$;

create or replace function public.submit_story_poll_vote(
  p_poll_id uuid, p_option_index integer
)
returns jsonb language sql security invoker
set search_path = public, private, auth, pg_temp
as $$ select private.submit_story_poll_vote(p_poll_id, p_option_index); $$;

grant usage on schema private to authenticated;
revoke all on function private.create_story_poll(uuid, text, jsonb) from public, anon;
revoke all on function private.get_story_polls(uuid[]) from public, anon;
revoke all on function private.submit_story_poll_vote(uuid, integer) from public, anon;
grant execute on function private.create_story_poll(uuid, text, jsonb) to authenticated;
grant execute on function private.get_story_polls(uuid[]) to authenticated;
grant execute on function private.submit_story_poll_vote(uuid, integer) to authenticated;

drop policy if exists "Users can read their own story poll votes" on public.story_poll_votes;
create policy "Users can read their own story poll votes"
on public.story_poll_votes for select to authenticated
using (user_id = (select auth.uid()));
grant select on public.story_poll_votes to authenticated;
create index if not exists story_poll_votes_user_id_idx
  on public.story_poll_votes (user_id);