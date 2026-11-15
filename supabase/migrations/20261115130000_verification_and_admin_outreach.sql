-- Verified identity requests and administrator support outreach.
create table if not exists public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  applicant_type text not null check (applicant_type in ('individual','organization')),
  category text not null check (char_length(category) between 2 and 80),
  legal_name text not null check (char_length(legal_name) between 2 and 160),
  phone text,
  organization_registration_number text,
  organization_national_id text,
  public_links jsonb not null default '[]'::jsonb check (jsonb_typeof(public_links)='array'),
  explanation text not null check (char_length(explanation) between 20 and 4000),
  evidence_paths text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','under_review','needs_info','approved','rejected')),
  reviewer_id uuid references auth.users(id) on delete set null,
  review_note text check (review_note is null or char_length(review_note)<=2000),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists verification_requests_status_created_idx
 on public.verification_requests(status,created_at desc);
create index if not exists verification_requests_user_created_idx
 on public.verification_requests(user_id,created_at desc);
alter table public.profiles add column if not exists is_verified boolean not null default false;
update public.profiles set is_verified=true where id='2459f67f-2b81-4b89-ab25-0916bd688a5e';
alter table public.verification_requests enable row level security;
revoke all on public.verification_requests from anon, authenticated;
grant select,insert on public.verification_requests to authenticated;
create policy "Applicants can read own verification requests"
 on public.verification_requests for select to authenticated using(user_id=(select auth.uid()));
create policy "Applicants can submit own verification requests"
 on public.verification_requests for insert to authenticated
 with check(user_id=(select auth.uid()) and status='pending' and reviewer_id is null and reviewed_at is null);
create policy "Admins can read verification requests"
 on public.verification_requests for select to authenticated using(private.is_admin());

create or replace function private.admin_set_verified(p_user_id uuid,p_verified boolean,p_note text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_user_id=(select auth.uid()) then
   -- Self-verification is deliberately not allowed.
   raise exception 'Cannot change own verification status' using errcode='42501';
 end if;
 update public.profiles set is_verified=p_verified,updated_at=now() where id=p_user_id;
 if not found then raise exception 'User not found' using errcode='P0002'; end if;
 insert into private.admin_audit_logs(actor_id,target_user_id,action,metadata)
 values((select auth.uid()),p_user_id,case when p_verified then 'user_verified' else 'user_unverified' end,
 jsonb_build_object('note',left(coalesce(p_note,''),1000)));
end $$;
revoke all on function private.admin_set_verified(uuid,boolean,text) from public,anon;
grant execute on function private.admin_set_verified(uuid,boolean,text) to authenticated;
create or replace function public.admin_set_verified(p_user_id uuid,p_verified boolean,p_note text default null)
returns void language sql security invoker set search_path='' as $$
 select private.admin_set_verified(p_user_id,p_verified,p_note);
$$;
revoke all on function public.admin_set_verified(uuid,boolean,text) from public,anon;
grant execute on function public.admin_set_verified(uuid,boolean,text) to authenticated;

create or replace function private.admin_review_verification(p_request_id uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid;
begin
 if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_status not in ('under_review','needs_info','approved','rejected') then raise exception 'Invalid status' using errcode='22023'; end if;
 select user_id into v_user from public.verification_requests where id=p_request_id for update;
 if v_user is null then raise exception 'Request not found' using errcode='P0002'; end if;
 update public.verification_requests set status=p_status,reviewer_id=(select auth.uid()),
 review_note=nullif(left(trim(coalesce(p_note,'')),2000),''),reviewed_at=now(),updated_at=now()
 where id=p_request_id;
 if p_status='approved' then update public.profiles set is_verified=true,updated_at=now() where id=v_user; end if;
 if p_status='rejected' then update public.profiles set is_verified=false,updated_at=now() where id=v_user; end if;
 insert into private.admin_audit_logs(actor_id,target_user_id,action,metadata)
 values((select auth.uid()),v_user,'verification_request_reviewed',jsonb_build_object('request_id',p_request_id,'status',p_status));
 insert into public.notifications(recipient_id,actor_id,type,entity_id,entity_type,message)
 values(v_user,(select auth.uid()),'verification_update',p_request_id,'profile',
 case p_status when 'approved' then 'درخواست تأیید حساب شما پذیرفته شد.' when 'needs_info' then 'برای درخواست تأیید حساب، اطلاعات بیشتری لازم است.' when 'rejected' then 'درخواست تأیید حساب شما پذیرفته نشد.' else 'درخواست تأیید حساب شما در حال بررسی است.' end);
end $$;
revoke all on function private.admin_review_verification(uuid,text,text) from public,anon;
grant execute on function private.admin_review_verification(uuid,text,text) to authenticated;
create or replace function public.admin_review_verification(p_request_id uuid,p_status text,p_note text default null)
returns void language sql security invoker set search_path='' as $$
 select private.admin_review_verification(p_request_id,p_status,p_note);
$$;
revoke all on function public.admin_review_verification(uuid,text,text) from public,anon;
grant execute on function public.admin_review_verification(uuid,text,text) to authenticated;

-- Private evidence bucket; only the applicant and admins can read.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('verification-evidence','verification-evidence',false,10485760,
 array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy "Applicants upload own verification evidence" on storage.objects for insert to authenticated
 with check(bucket_id='verification-evidence' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Applicants and admins read verification evidence" on storage.objects for select to authenticated
 using(bucket_id='verification-evidence' and ((storage.foldername(name))[1]=(select auth.uid())::text or private.is_admin()));

-- Let admins open the existing isolated support thread for any user.
create or replace function private.admin_get_or_create_support_conversation(p_user_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'User not found' using errcode='P0002'; end if;
 insert into public.support_conversations(user_id,status) values(p_user_id,'open')
 on conflict(user_id) do update set status='open',updated_at=now()
 returning id into v_id;
 insert into private.admin_audit_logs(actor_id,target_user_id,action,metadata)
 values((select auth.uid()),p_user_id,'support_conversation_opened',jsonb_build_object('conversation_id',v_id));
 return v_id;
end $$;
revoke all on function private.admin_get_or_create_support_conversation(uuid) from public,anon;
grant execute on function private.admin_get_or_create_support_conversation(uuid) to authenticated;
create or replace function public.admin_get_or_create_support_conversation(p_user_id uuid)
returns uuid language sql security invoker set search_path='' as $$
 select private.admin_get_or_create_support_conversation(p_user_id);
$$;
revoke all on function public.admin_get_or_create_support_conversation(uuid) from public,anon;
grant execute on function public.admin_get_or_create_support_conversation(uuid) to authenticated;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
 check(type in ('follow','post_like','post_comment','comment_reply','post_repost','story_reaction','message_new','support_message','support_reply','verification_update'));
