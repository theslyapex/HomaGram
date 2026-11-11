create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  display_name text not null,
  bio text not null default '',
  website_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,24}$'),
  constraint profiles_display_name_length check (char_length(display_name) between 1 and 50),
  constraint profiles_bio_length check (char_length(bio) <= 160)
);
create unique index profiles_username_lower_uidx on public.profiles (lower(username));

create table public.account_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  locale text not null default 'fa' check (locale in ('fa', 'en')),
  theme text not null default 'system' check (theme in ('system', 'light', 'dark')),
  is_private boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.account_settings enable row level security;
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.account_settings from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (display_name, bio, website_url) on table public.profiles to authenticated;
grant select on table public.account_settings to authenticated;
grant update (locale, theme, is_private) on table public.account_settings to authenticated;

create policy "Users can read their own profile" on public.profiles
for select to authenticated using ((select auth.uid()) = id);
create policy "Users can update their own profile" on public.profiles
for update to authenticated using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);
create policy "Users can read their own settings" on public.account_settings
for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users can update their own settings" on public.account_settings
for update to authenticated using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create or replace function private.set_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin new.updated_at := now(); return new; end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function private.set_updated_at();
create trigger account_settings_set_updated_at before update on public.account_settings
for each row execute function private.set_updated_at();

create or replace function private.handle_new_homagram_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  requested_username text;
  requested_display_name text;
begin
  requested_username := lower(btrim(coalesce(
    new.raw_user_meta_data ->> 'username',
    'user_' || substr(replace(new.id::text, '-', ''), 1, 12)
  )));
  requested_display_name := btrim(coalesce(
    new.raw_user_meta_data ->> 'display_name',
    split_part(coalesce(new.email, 'HomaGram User'), '@', 1)
  ));
  insert into public.profiles (id, username, display_name)
  values (new.id, requested_username, requested_display_name);
  insert into public.account_settings (user_id) values (new.id);
  return new;
end;
$$;
revoke all on function private.handle_new_homagram_user() from public, anon, authenticated;
create trigger on_auth_user_created_homagram after insert on auth.users
for each row execute function private.handle_new_homagram_user();
