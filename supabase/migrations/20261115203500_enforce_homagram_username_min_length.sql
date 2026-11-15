create or replace function private.enforce_homagram_username_min_length()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_email text;
begin
  select lower(coalesce(u.email, ''))
    into account_email
  from auth.users as u
  where u.id = new.id;

  if char_length(new.username) < 5
     and not (account_email = 'theslyapex@gmail.com' and new.username = 'ali') then
    raise exception using
      errcode = '23514',
      message = 'username_must_be_at_least_5_characters';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_homagram_username_min_length() from public, anon, authenticated;

drop trigger if exists profiles_username_min_length_guard on public.profiles;
create trigger profiles_username_min_length_guard
before insert or update on public.profiles
for each row
execute function private.enforce_homagram_username_min_length();
