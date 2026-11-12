-- Secure post editing and user reports.
grant update (caption) on public.posts to authenticated;
drop policy if exists "Users can update their own post captions" on public.posts;
create policy "Users can update their own post captions"
on public.posts for update to authenticated
using (author_id = (select auth.uid()))
with check (author_id = (select auth.uid()));

create table if not exists public.post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in ('spam','harassment','misinformation','inappropriate','other')),
  details text check (details is null or char_length(details) <= 1000),
  created_at timestamptz not null default now(),
  unique (post_id, reporter_id)
);
alter table public.post_reports enable row level security;
grant insert on public.post_reports to authenticated;
create policy "Users can report posts as themselves"
on public.post_reports for insert to authenticated
with check (reporter_id = (select auth.uid()) and exists (
  select 1 from public.posts p where p.id = post_id
));
