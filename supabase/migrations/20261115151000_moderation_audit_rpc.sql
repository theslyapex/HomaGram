create or replace function public.admin_record_moderation_action(
  p_actor_id uuid,p_target_user_id uuid,p_action text,p_metadata jsonb default '{}'::jsonb
)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if p_action is null or char_length(p_action) not between 1 and 80 then
    raise exception 'Invalid action' using errcode='22023';
  end if;
  insert into private.admin_audit_logs(actor_id,target_user_id,action,metadata)
  values(p_actor_id,p_target_user_id,p_action,
    case when jsonb_typeof(p_metadata)='object' then p_metadata else '{}'::jsonb end);
end;
$$;
revoke all on function public.admin_record_moderation_action(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_record_moderation_action(uuid,uuid,text,jsonb) to service_role;

create or replace function public.admin_is_protected_account(p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists(select 1 from private.admin_users where user_id=p_user_id); $$;
revoke all on function public.admin_is_protected_account(uuid) from public,anon,authenticated;
grant execute on function public.admin_is_protected_account(uuid) to service_role;
