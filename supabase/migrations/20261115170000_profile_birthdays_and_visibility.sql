
create table public.profile_birthdays (
  user_id uuid primary key references auth.users(id) on delete cascade,
  birth_date date not null,
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_birthdays_not_future check (birth_date <= current_date),
  constraint profile_birthdays_reasonable_range check (birth_date >= date '1900-01-01')
);

alter table public.profile_birthdays enable row level security;
revoke all on table public.profile_birthdays from anon, authenticated;
grant select on table public.profile_birthdays to authenticated;
grant insert (user_id, birth_date, is_public) on table public.profile_birthdays to authenticated;
grant update (birth_date, is_public) on table public.profile_birthdays to authenticated;
grant delete on table public.profile_birthdays to authenticated;

create policy "Users can read their own birthday"
on public.profile_birthdays for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can insert their own birthday"
on public.profile_birthdays for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update their own birthday"
on public.profile_birthdays for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users can delete their own birthday"
on public.profile_birthdays for delete to authenticated
using ((select auth.uid()) = user_id);

create trigger profile_birthdays_set_updated_at
before update on public.profile_birthdays
for each row execute function private.set_updated_at();

create or replace function public.get_public_profile_birthday(p_profile_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select b.birth_date
  from public.profile_birthdays as b
  where b.user_id = p_profile_id
    and b.is_public = true
    and (select auth.uid()) is not null
  limit 1;
$$;

revoke all on function public.get_public_profile_birthday(uuid) from public, anon;
grant execute on function public.get_public_profile_birthday(uuid) to authenticated;
