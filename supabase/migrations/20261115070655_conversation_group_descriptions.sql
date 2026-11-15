alter table public.conversations
  add column if not exists description text not null default '';

create or replace function public.update_group_details(
  p_conversation_id uuid,
  p_title text,
  p_description text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception 'Title must contain 1 to 100 characters' using errcode = '22023';
  end if;
  if char_length(coalesce(p_description, '')) > 500 then
    raise exception 'Description is too long' using errcode = '22023';
  end if;

  update public.conversations c
  set title = btrim(p_title),
      description = btrim(coalesce(p_description, '')),
      updated_at = now()
  where c.id = p_conversation_id
    and c.kind = 'group'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.id
        and cm.user_id = v_actor
        and cm.left_at is null
        and cm.role in ('owner', 'admin')
    );

  if not found then
    raise exception 'Not permitted or group not found' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.update_group_details(uuid, text, text) from public;
revoke all on function public.update_group_details(uuid, text, text) from anon;
grant execute on function public.update_group_details(uuid, text, text) to authenticated;
