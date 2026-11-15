alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
 type = any(array['follow','post_like','post_comment','comment_reply','post_repost','story_reaction','message_new','support_message','support_reply','verification_update','moderation_notice','report_reviewed']::text[])
);
alter table public.notifications drop constraint if exists notifications_entity_type_check;
alter table public.notifications add constraint notifications_entity_type_check check (
 entity_type = any(array['profile','post','comment','story','conversation','support','report']::text[])
);

create or replace function private.admin_review_post_report(p_report_id uuid,p_status text,p_review_note text default null)
returns void language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid := auth.uid();
 v_reporter uuid;
 v_post uuid;
 v_previous_status text;
 v_message text;
begin
 if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_status not in ('reviewed','dismissed','actioned') then raise exception 'Invalid report status' using errcode='22023'; end if;
 if p_review_note is not null and char_length(p_review_note)>1000 then raise exception 'Review note is too long' using errcode='22023'; end if;
 select reporter_id,post_id,status into v_reporter,v_post,v_previous_status
 from public.post_reports where id=p_report_id for update;
 if not found then raise exception 'Report not found' using errcode='P0002'; end if;
 update public.post_reports set status=p_status,reviewed_by=v_actor,reviewed_at=now(),
 review_note=nullif(trim(coalesce(p_review_note,'')),'') where id=p_report_id;
 insert into private.admin_audit_logs(actor_id,action,metadata)
 values(v_actor,'post_report_reviewed',jsonb_build_object('report_id',p_report_id,'status',p_status));
 if v_previous_status='pending' then
  v_message := case when p_status='actioned'
   then 'گزارش شما بررسی شد و اقدام لازم انجام گرفت. از همراهی و کمک شما برای حفظ فضای امن هماگرام سپاسگزاریم.'
   when p_status='dismissed'
   then 'گزارش شما بررسی شد. پس از ارزیابی، تخلفی مطابق با این گزارش احراز نشد. از اینکه برای بهبود فضای هماگرام همراه ما هستید، سپاسگزاریم.'
   else 'گزارش شما بررسی شد. از دقت، همراهی و همکاری شما برای بهتر و امن‌تر ماندن فضای هماگرام سپاسگزاریم.'
  end;
  insert into public.notifications(recipient_id,actor_id,type,entity_id,entity_type,message)
  values(v_reporter,v_actor,'report_reviewed',p_report_id,'report',v_message);
 end if;
end;
$$;
revoke all on function private.admin_review_post_report(uuid,text,text) from public,anon;
grant execute on function private.admin_review_post_report(uuid,text,text) to authenticated;

create or replace function private.admin_review_message_report(p_report_id uuid,p_status text,p_review_note text default null)
returns void language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid := auth.uid();
 v_reporter uuid;
 v_message_id uuid;
 v_previous_status text;
 v_message text;
begin
 if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_status not in ('reviewed','dismissed','actioned') then raise exception 'Invalid status' using errcode='22023'; end if;
 if p_review_note is not null and char_length(p_review_note)>1000 then raise exception 'Review note is too long' using errcode='22023'; end if;
 select reporter_id,message_id,status into v_reporter,v_message_id,v_previous_status
 from public.message_reports where id=p_report_id for update;
 if not found then raise exception 'Report not found' using errcode='P0002'; end if;
 update public.message_reports set status=p_status,reviewed_by=v_actor,reviewed_at=now(),
 review_note=nullif(trim(coalesce(p_review_note,'')),'') where id=p_report_id;
 insert into private.admin_audit_logs(actor_id,action,metadata)
 values(v_actor,'message_report_reviewed',jsonb_build_object('report_id',p_report_id,'status',p_status));
 if v_previous_status='pending' then
  v_message := case when p_status='actioned'
   then 'گزارش پیام شما بررسی شد و اقدام لازم انجام گرفت. از همراهی شما برای حفظ فضای امن هماگرام سپاسگزاریم.'
   when p_status='dismissed'
   then 'گزارش پیام شما بررسی شد. پس از ارزیابی، تخلفی مطابق با این گزارش احراز نشد. از همراهی شما سپاسگزاریم.'
   else 'گزارش پیام شما بررسی شد. از دقت و همکاری شما برای بهتر و امن‌تر ماندن هماگرام سپاسگزاریم.'
  end;
  insert into public.notifications(recipient_id,actor_id,type,entity_id,entity_type,message)
  values(v_reporter,v_actor,'report_reviewed',p_report_id,'report',v_message);
 end if;
end;
$$;
revoke all on function private.admin_review_message_report(uuid,text,text) from public,anon;
grant execute on function private.admin_review_message_report(uuid,text,text) to authenticated;
