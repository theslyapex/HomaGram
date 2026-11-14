create table if not exists public.message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in ('spam','harassment','threat','privacy','inappropriate','other')),
  details text check (details is null or char_length(details) <= 1000),
  status text not null default 'pending' check (status in ('pending','reviewed','dismissed','actioned')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text check (review_note is null or char_length(review_note) <= 1000),
  created_at timestamptz not null default now(),
  unique(message_id, reporter_id)
);
create index if not exists message_reports_status_created_idx
  on public.message_reports(status, created_at desc);
alter table public.message_reports enable row level security;
revoke all on public.message_reports from public, anon, authenticated;

create or replace function private.report_message(
  p_message_id uuid,
  p_reason text,
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_conversation_id uuid;
  v_sender_id uuid;
  v_report_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_reason not in ('spam','harassment','threat','privacy','inappropriate','other') then
    raise exception 'Invalid report reason' using errcode='22023';
  end if;
  if p_details is not null and char_length(p_details) > 1000 then
    raise exception 'Report details too long' using errcode='22023';
  end if;

  select m.conversation_id, m.sender_id
    into v_conversation_id, v_sender_id
  from public.messages m
  where m.id = p_message_id and m.deleted_at is null;

  if v_conversation_id is null then raise exception 'Message not found' using errcode='P0002'; end if;
  if v_sender_id = v_uid then raise exception 'You cannot report your own message' using errcode='42501'; end if;
  if not private.is_active_conversation_member(v_conversation_id) then
    raise exception 'Conversation membership required' using errcode='42501';
  end if;

  insert into public.message_reports(message_id, conversation_id, reporter_id, reason, details)
  values (p_message_id, v_conversation_id, v_uid, p_reason, nullif(trim(coalesce(p_details,'')), ''))
  returning id into v_report_id;
  return v_report_id;
exception
  when unique_violation then
    raise exception 'You have already reported this message' using errcode='23505';
end;
$$;
revoke all on function private.report_message(uuid,text,text) from public, anon;
grant execute on function private.report_message(uuid,text,text) to authenticated;

create or replace function public.report_message(
  p_message_id uuid,
  p_reason text,
  p_details text default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select private.report_message(p_message_id,p_reason,p_details); $$;
revoke all on function public.report_message(uuid,text,text) from public, anon;
grant execute on function public.report_message(uuid,text,text) to authenticated;

create or replace function private.admin_list_message_reports(p_limit integer default 50,p_offset integer default 0)
returns table(
  report_id uuid, message_id uuid, conversation_id uuid, reporter_id uuid,
  sender_id uuid, reason text, details text, status text, created_at timestamptz,
  message_body text, review_note text
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  return query
  select r.id,r.message_id,r.conversation_id,r.reporter_id,m.sender_id,r.reason,r.details,r.status,r.created_at,m.body,r.review_note
  from public.message_reports r join public.messages m on m.id=r.message_id
  order by case when r.status='pending' then 0 else 1 end,r.created_at desc
  limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;
revoke all on function private.admin_list_message_reports(integer,integer) from public,anon;
grant execute on function private.admin_list_message_reports(integer,integer) to authenticated;
create or replace function public.admin_list_message_reports(p_limit integer default 50,p_offset integer default 0)
returns table(
  report_id uuid, message_id uuid, conversation_id uuid, reporter_id uuid,
  sender_id uuid, reason text, details text, status text, created_at timestamptz,
  message_body text, review_note text
)
language sql stable security invoker set search_path=''
as $$ select * from private.admin_list_message_reports(p_limit,p_offset); $$;
revoke all on function public.admin_list_message_reports(integer,integer) from public,anon;
grant execute on function public.admin_list_message_reports(integer,integer) to authenticated;

create or replace function private.admin_review_message_report(p_report_id uuid,p_status text,p_review_note text default null)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_status not in ('reviewed','dismissed','actioned') then raise exception 'Invalid status' using errcode='22023'; end if;
  update public.message_reports set status=p_status,reviewed_by=auth.uid(),reviewed_at=now(),
    review_note=nullif(trim(coalesce(p_review_note,'')),'') where id=p_report_id;
  if not found then raise exception 'Report not found' using errcode='P0002'; end if;
  insert into private.admin_audit_logs(actor_id,action,metadata)
  values(auth.uid(),'message_report_reviewed',jsonb_build_object('report_id',p_report_id,'status',p_status));
end;
$$;
revoke all on function private.admin_review_message_report(uuid,text,text) from public,anon;
grant execute on function private.admin_review_message_report(uuid,text,text) to authenticated;
create or replace function public.admin_review_message_report(p_report_id uuid,p_status text,p_review_note text default null)
returns void language sql security invoker set search_path=''
as $$ select private.admin_review_message_report(p_report_id,p_status,p_review_note); $$;
revoke all on function public.admin_review_message_report(uuid,text,text) from public,anon;
grant execute on function public.admin_review_message_report(uuid,text,text) to authenticated;
