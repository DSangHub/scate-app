-- SCATE: profile fields collected by the landing page "Create your profile" form.
-- Run after 20261114000000_users_officials.sql. Safe to re-run.
--
-- The form signs people up through Supabase Auth (email link) and sends
-- user name, zip code and account type as sign-up metadata. This copies
-- them onto the profile row. Role (citizen / official / admin) is never
-- taken from sign-up metadata.

alter table public.users add column if not exists zip_code text;
alter table public.users add column if not exists account_type text not null default 'resident';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'users_account_type_check') then
    alter table public.users
      add constraint users_account_type_check check (account_type in ('resident', 'candidate'));
  end if;
end $$;

create index if not exists users_zip_code_idx on public.users (zip_code);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.users (id, email, display_name, preferred_language, zip_code, account_type)
  values (
    new.id,
    new.email,
    nullif(left(trim(meta ->> 'display_name'), 60), ''),
    coalesce(nullif(left(meta ->> 'preferred_language', 8), ''), 'en'),
    nullif(left(trim(meta ->> 'zip_code'), 10), ''),
    case when meta ->> 'account_type' = 'candidate' then 'candidate' else 'resident' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Backfill anyone who signed up before this migration ran.
update public.users u
   set zip_code = coalesce(u.zip_code, nullif(left(trim(a.raw_user_meta_data ->> 'zip_code'), 10), '')),
       account_type = case when a.raw_user_meta_data ->> 'account_type' = 'candidate' then 'candidate' else u.account_type end
  from auth.users a
 where a.id = u.id;
