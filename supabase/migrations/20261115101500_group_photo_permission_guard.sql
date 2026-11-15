create or replace function public.update_conversation_photo(p_conversation_id uuid,p_photo_path text)
returns void language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_kind text;
  v_role text;
  v_admins_can_change boolean;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if p_photo_path is not null and (
    split_part(p_photo_path,'/',1)<>p_conversation_id::text
    or split_part(p_photo_path,'/',2)<>v_uid::text
    or split_part(p_photo_path,'/',3)=''
    or p_photo_path like '%..%'
  ) then raise exception 'Invalid conversation photo path' using errcode='22023'; end if;
  select c.kind,cm.role,c.admins_can_change_info into v_kind,v_role,v_admins_can_change
  from public.conversations c join public.conversation_members cm on cm.conversation_id=c.id
  where c.id=p_conversation_id and cm.user_id=v_uid and cm.left_at is null;
  if not found then raise exception 'Active membership not found' using errcode='42501'; end if;
  if v_kind='group' and not (v_role='owner' or (v_role='admin' and v_admins_can_change)) then
    raise exception 'Only authorized group managers can change the photo' using errcode='42501';
  end if;
  if v_kind<>'group' and v_role not in ('owner','admin') then
    raise exception 'Only conversation owners and admins can change the photo' using errcode='42501';
  end if;
  update public.conversations set photo_path=p_photo_path,updated_at=now() where id=p_conversation_id;
end;
$$;
revoke all on function public.update_conversation_photo(uuid,text) from public,anon;
grant execute on function public.update_conversation_photo(uuid,text) to authenticated;