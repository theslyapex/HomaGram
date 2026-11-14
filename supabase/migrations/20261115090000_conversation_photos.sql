-- Private group and channel cover photos, writable only by conversation owners/admins.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('conversation-photos', 'conversation-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = false, file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Conversation members can view conversation photos" on storage.objects;
create policy "Conversation members can view conversation photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'conversation-photos'
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id::text = split_part(name, '/', 1)
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
  )
);

drop policy if exists "Conversation managers can upload conversation photos" on storage.objects;
create policy "Conversation managers can upload conversation photos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'conversation-photos'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id::text = split_part(name, '/', 1)
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
      and cm.role in ('owner', 'admin')
  )
);

drop policy if exists "Conversation managers can update conversation photos" on storage.objects;
create policy "Conversation managers can update conversation photos"
on storage.objects for update to authenticated
using (
  bucket_id = 'conversation-photos'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id::text = split_part(name, '/', 1)
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
      and cm.role in ('owner', 'admin')
  )
)
with check (
  bucket_id = 'conversation-photos'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id::text = split_part(name, '/', 1)
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
      and cm.role in ('owner', 'admin')
  )
);

drop policy if exists "Conversation managers can delete conversation photos" on storage.objects;
create policy "Conversation managers can delete conversation photos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'conversation-photos'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id::text = split_part(name, '/', 1)
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
      and cm.role in ('owner', 'admin')
  )
);

create or replace function public.update_conversation_photo(
  p_conversation_id uuid,
  p_photo_path text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  if p_photo_path is not null and (
    split_part(p_photo_path, '/', 1) <> p_conversation_id::text
    or split_part(p_photo_path, '/', 2) <> v_uid::text
    or split_part(p_photo_path, '/', 3) = ''
    or p_photo_path like '%..%'
  ) then
    raise exception 'Invalid conversation photo path';
  end if;
  if not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.user_id = v_uid
      and cm.left_at is null
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Only conversation owners and admins can change the photo';
  end if;
  update public.conversations
  set photo_path = p_photo_path, updated_at = now()
  where id = p_conversation_id;
end;
$$;

revoke all on function public.update_conversation_photo(uuid, text) from public;
grant execute on function public.update_conversation_photo(uuid, text) to authenticated;
