create table if not exists public.story_questions (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null unique references public.stories(id) on delete cascade,
  prompt text not null check (char_length(btrim(prompt)) between 1 and 180),
  created_at timestamptz not null default now()
);
create table if not exists public.story_question_responses (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.story_questions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  response text not null check (char_length(btrim(response)) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(question_id, user_id)
);
alter table public.story_questions enable row level security;
alter table public.story_question_responses enable row level security;
revoke all on public.story_questions from anon, authenticated;
revoke all on public.story_question_responses from anon, authenticated;

create or replace function private.create_story_question(p_story_id uuid, p_prompt text)
returns uuid language plpgsql security definer set search_path=public,private,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_story public.stories%rowtype; v_id uuid;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 if char_length(btrim(coalesce(p_prompt,''))) not between 1 and 180 then raise exception 'Invalid prompt'; end if;
 select * into v_story from public.stories where id=p_story_id for update;
 if not found or v_story.author_id<>v_uid or v_story.expires_at<=now() then raise exception 'Story is not eligible'; end if;
 insert into public.story_questions(story_id,prompt) values(p_story_id,btrim(p_prompt)) returning id into v_id;
 return v_id;
end; $$;

create or replace function private.get_story_questions(p_story_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path=public,private,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id,'story_id',q.story_id,'prompt',q.prompt,
  'response_count',(select count(*) from public.story_question_responses r where r.question_id=q.id),
  'my_response',(select r.response from public.story_question_responses r where r.question_id=q.id and r.user_id=v_uid limit 1),
  'responses',case when s.author_id=v_uid then (
   select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'user_id',r.user_id,'response',r.response,'created_at',r.created_at,
    'username',coalesce(p.username,'user'),'display_name',coalesce(p.display_name,'کاربر')) order by r.created_at desc),'[]'::jsonb)
   from public.story_question_responses r left join public.profiles p on p.id=r.user_id where r.question_id=q.id
  ) else '[]'::jsonb end
 ) order by q.created_at),'[]'::jsonb) into v_result
 from public.story_questions q join public.stories s on s.id=q.story_id
 where q.story_id=any(coalesce(p_story_ids,array[]::uuid[]))
 and (s.author_id=v_uid or (s.expires_at>now() and private.can_view_story(s.author_id)) or private.story_is_in_visible_highlight(s.id));
 return v_result;
end; $$;

create or replace function private.submit_story_question_response(p_question_id uuid,p_response text)
returns jsonb language plpgsql security definer set search_path=public,private,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_q public.story_questions%rowtype; v_story public.stories%rowtype; v_result jsonb;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 if char_length(btrim(coalesce(p_response,''))) not between 1 and 1000 then raise exception 'Invalid response'; end if;
 select * into v_q from public.story_questions where id=p_question_id;
 if not found then raise exception 'Question not found'; end if;
 select * into v_story from public.stories where id=v_q.story_id;
 if v_story.author_id=v_uid or v_story.expires_at<=now() or not private.can_view_story(v_story.author_id) then raise exception 'Cannot respond'; end if;
 insert into public.story_question_responses(question_id,user_id,response) values(p_question_id,v_uid,btrim(p_response))
 on conflict(question_id,user_id) do update set response=excluded.response,updated_at=now();
 v_result:=private.get_story_questions(array[v_q.story_id]);
 return coalesce(v_result->0,'{}'::jsonb);
end; $$;

drop function if exists public.create_story_question(uuid,text);
drop function if exists public.get_story_questions(uuid[]);
drop function if exists public.submit_story_question_response(uuid,text);
create or replace function public.create_story_question(p_story_id uuid,p_prompt text)
returns uuid language sql security invoker set search_path=public,private,auth,pg_temp as $$ select private.create_story_question(p_story_id,p_prompt); $$;
create or replace function public.get_story_questions(p_story_ids uuid[])
returns jsonb language sql stable security invoker set search_path=public,private,auth,pg_temp as $$ select private.get_story_questions(p_story_ids); $$;
create or replace function public.submit_story_question_response(p_question_id uuid,p_response text)
returns jsonb language sql security invoker set search_path=public,private,auth,pg_temp as $$ select private.submit_story_question_response(p_question_id,p_response); $$;
grant usage on schema private to authenticated;
revoke all on function private.create_story_question(uuid,text) from public,anon;
revoke all on function private.get_story_questions(uuid[]) from public,anon;
revoke all on function private.submit_story_question_response(uuid,text) from public,anon;
grant execute on function private.create_story_question(uuid,text) to authenticated;
grant execute on function private.get_story_questions(uuid[]) to authenticated;
grant execute on function private.submit_story_question_response(uuid,text) to authenticated;
revoke all on function public.create_story_question(uuid,text) from public,anon;
revoke all on function public.get_story_questions(uuid[]) from public,anon;
revoke all on function public.submit_story_question_response(uuid,text) from public,anon;
grant execute on function public.create_story_question(uuid,text) to authenticated;
grant execute on function public.get_story_questions(uuid[]) to authenticated;
grant execute on function public.submit_story_question_response(uuid,text) to authenticated;
