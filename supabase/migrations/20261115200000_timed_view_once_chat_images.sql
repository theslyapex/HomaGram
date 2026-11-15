alter table public.message_attachments
  add column if not exists is_view_once boolean not null default false;

create table if not exists public.message_attachment_views (
  id uuid primary key default gen_random_uuid(),
  attachment_id uuid not null references public.message_attachments(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  opened_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint message_attachment_views_once unique (attachment_id, viewer_id),
  constraint message_attachment_views_expiry check (expires_at > opened_at and expires_at <= opened_at + interval '11 seconds')
);
alter table public.message_attachment_views enable row level security;
revoke all on public.message_attachment_views from anon, authenticated;
grant select on public.message_attachment_views to authenticated;
drop policy if exists "Users can read own timed image view state" on public.message_attachment_views;
create policy "Users can read own timed image view state"
on public.message_attachment_views for select to authenticated
using (viewer_id = (select auth.uid()));

create or replace function public.open_timed_image(p_attachment_id uuid)
returns table(storage_path text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_attachment public.message_attachments%rowtype;
  v_expiry timestamptz;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select * into v_attachment
  from public.message_attachments
  where id = p_attachment_id and is_view_once = true
    and mime_type like 'image/%'
  for update;
  if v_attachment.id is null then raise exception 'Timed image not found' using errcode='P0002'; end if;
  if v_attachment.uploader_id = v_user then
    raise exception 'Sender cannot open the recipient view' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = v_attachment.conversation_id
      and cm.user_id = v_user and cm.left_at is null
  ) then raise exception 'Active conversation membership required' using errcode='42501'; end if;
  if exists (
    select 1 from public.message_attachment_views v
    where v.attachment_id = p_attachment_id and v.viewer_id = v_user
  ) then raise exception 'This image has already been opened' using errcode='42501'; end if;
  v_expiry := now() + interval '10 seconds';
  insert into public.message_attachment_views(attachment_id,viewer_id,opened_at,expires_at)
  values(p_attachment_id,v_user,now(),v_expiry);
  return query select v_attachment.storage_path, v_expiry;
end;
$function$;
revoke all on function public.open_timed_image(uuid) from public, anon;
grant execute on function public.open_timed_image(uuid) to authenticated;

drop policy if exists "Chat members can read attached media" on storage.objects;
create policy "Chat members can read attached media"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-media'
  and exists (
    select 1 from public.message_attachments a
    join public.conversation_members cm on cm.conversation_id = a.conversation_id
    where a.storage_path = storage.objects.name
      and cm.user_id = (select auth.uid()) and cm.left_at is null
      and (
        a.is_view_once = false
        or exists (
          select 1 from public.message_attachment_views v
          where v.attachment_id = a.id and v.viewer_id = (select auth.uid())
            and v.expires_at > now()
        )
      )
  )
);