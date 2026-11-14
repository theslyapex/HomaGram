-- Private cloud-backed story drafts.
create table if not exists public.story_drafts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  media_path text,
  music_path text,
  draft_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint story_drafts_data_object check (jsonb_typeof(draft_data) = 'object')
);

create index if not exists story_drafts_owner_updated_idx
  on public.story_drafts(owner_id, updated_at desc);

alter table public.story_drafts enable row level security;
revoke all on public.story_drafts from anon, authenticated;
grant select, insert, update, delete on public.story_drafts to authenticated;

drop policy if exists "Users manage only their own story drafts" on public.story_drafts;
create policy "Users manage only their own story drafts"
  on public.story_drafts for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'story-drafts', 'story-drafts', false, 52428800,
  array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime',
        'audio/mpeg','audio/mp4','audio/aac','audio/wav','image/gif']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 52428800,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users manage only their own story draft files" on storage.objects;
create policy "Users manage only their own story draft files"
  on storage.objects for all to authenticated
  using (
    bucket_id = 'story-drafts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'story-drafts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
