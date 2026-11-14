-- SCATE: users + officials backend (Supabase)
-- Project: omfcsehehnfkcfenryje
-- Run in the Supabase SQL editor, or with `supabase db push`.
-- Safe to re-run: every statement is idempotent.
--
-- Model
--   users              profile row per auth.users account (role: citizen | official | admin)
--   officials          public directory of elected officials
--   official_claims    a user asks to be verified as a directory entry; an admin reviews
--   official_follows   users follow officials
--
-- Admin work (adding officials, changing roles) is done either by a user whose
-- role is 'admin', or from the dashboard / service role, which bypass these rules.

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  email text unique,
  display_name text,
  role text not null default 'citizen',
  preferred_language text default 'en',
  signup_lat double precision,
  signup_lng double precision,
  signup_geo geography(point, 4326),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- If forum-schema.sql already created public.users, add what is missing.
alter table public.users add column if not exists display_name text;
alter table public.users add column if not exists role text not null default 'citizen';
alter table public.users add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'users_role_check') then
    alter table public.users
      add constraint users_role_check check (role in ('citizen', 'official', 'admin'));
  end if;
end $$;

-- True when the caller is a signed-in admin. Security definer so it can be
-- used inside policies on public.users without recursing into them.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users where id = auth.uid() and role = 'admin'
  );
$$;

-- Create the profile row when someone signs up through Supabase Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, email, display_name, preferred_language)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'display_name',
    coalesce(new.raw_user_meta_data ->> 'preferred_language', 'en')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- A signed-in non-admin may edit their profile but not their id, email or role.
create or replace function public.users_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.id := old.id;
    new.email := old.email;
    new.role := old.role;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists users_before_update on public.users;
create trigger users_before_update
  before update on public.users
  for each row execute function public.users_before_update();

-- Keeps signup_geo in step with signup_lat / signup_lng.
create or replace function public.users_set_geo()
returns trigger
language plpgsql
as $$
begin
  if new.signup_lat is not null and new.signup_lng is not null then
    new.signup_geo := format('SRID=4326;POINT(%s %s)', new.signup_lng, new.signup_lat);
  else
    new.signup_geo := null;
  end if;
  return new;
end;
$$;

drop trigger if exists users_set_geo on public.users;
create trigger users_set_geo
  before insert or update of signup_lat, signup_lng on public.users
  for each row execute function public.users_set_geo();

alter table public.users enable row level security;

drop policy if exists "users: read own or admin" on public.users;
create policy "users: read own or admin" on public.users
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

drop policy if exists "users: update own or admin" on public.users;
create policy "users: update own or admin" on public.users
  for update to authenticated
  using (id = (select auth.uid()) or public.is_admin())
  with check (id = (select auth.uid()) or public.is_admin());

-- No insert policy: rows come from the signup trigger.
-- No delete policy: deleting the auth user cascades.

revoke all on public.users from anon;
grant select, update on public.users to authenticated;

-- ---------------------------------------------------------------------------
-- officials (public directory)
-- ---------------------------------------------------------------------------
create table if not exists public.officials (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  office_title text not null,                 -- e.g. 'Mayor', 'State Senator'
  level text not null default 'local'
    check (level in ('federal', 'state', 'county', 'local', 'other')),
  jurisdiction text,                          -- e.g. 'City of Oakland'
  district text,
  party text,
  country_code text,                          -- ISO 3166-1 alpha-2
  region text,                                -- state / province
  term_start date,
  term_end date,
  bio text,
  contact_email text,
  phone text,
  website_url text,
  photo_url text,
  is_active boolean not null default true,
  claimed_by uuid unique references public.users (id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists officials_place_idx
  on public.officials (country_code, region, level);
create index if not exists officials_name_idx
  on public.officials (lower(full_name));

-- A verified official may edit only the contact / bio fields of their own
-- entry. Admins and the service role may change anything.
create or replace function public.officials_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.officials;
begin
  if auth.uid() is not null and not public.is_admin() then
    r := old;
    r.bio := new.bio;
    r.contact_email := new.contact_email;
    r.phone := new.phone;
    r.website_url := new.website_url;
    r.photo_url := new.photo_url;
    r.updated_at := now();
    return r;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists officials_before_update on public.officials;
create trigger officials_before_update
  before update on public.officials
  for each row execute function public.officials_before_update();

alter table public.officials enable row level security;

drop policy if exists "officials: public read" on public.officials;
create policy "officials: public read" on public.officials
  for select to anon, authenticated
  using (is_active or public.is_admin());

drop policy if exists "officials: admin insert" on public.officials;
create policy "officials: admin insert" on public.officials
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "officials: admin or owner update" on public.officials;
create policy "officials: admin or owner update" on public.officials
  for update to authenticated
  using (public.is_admin() or claimed_by = (select auth.uid()))
  with check (public.is_admin() or claimed_by = (select auth.uid()));

drop policy if exists "officials: admin delete" on public.officials;
create policy "officials: admin delete" on public.officials
  for delete to authenticated
  using (public.is_admin());

grant select on public.officials to anon;
grant select, insert, update, delete on public.officials to authenticated;

-- ---------------------------------------------------------------------------
-- official_claims (a user asks to be verified as an official)
-- ---------------------------------------------------------------------------
create table if not exists public.official_claims (
  id uuid primary key default gen_random_uuid(),
  official_id uuid not null references public.officials (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  evidence text,                              -- e.g. official email or link proving identity
  review_note text,
  reviewed_by uuid references public.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists official_claims_one_pending_idx
  on public.official_claims (official_id, user_id) where status = 'pending';
create unique index if not exists official_claims_one_approved_idx
  on public.official_claims (official_id) where status = 'approved';
create index if not exists official_claims_user_idx
  on public.official_claims (user_id);

alter table public.official_claims enable row level security;

drop policy if exists "claims: read own or admin" on public.official_claims;
create policy "claims: read own or admin" on public.official_claims
  for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "claims: create own pending" on public.official_claims;
create policy "claims: create own pending" on public.official_claims
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );

drop policy if exists "claims: withdraw own pending" on public.official_claims;
create policy "claims: withdraw own pending" on public.official_claims
  for delete to authenticated
  using (user_id = (select auth.uid()) and status = 'pending');

-- No update policy: reviews go through review_official_claim().

revoke all on public.official_claims from anon;
grant select, insert, delete on public.official_claims to authenticated;

-- Admin approves or rejects a claim. Call with supabase.rpc('review_official_claim', {...}).
create or replace function public.review_official_claim(
  p_claim_id uuid,
  p_approve boolean,
  p_note text default null
)
returns public.official_claims
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.official_claims;
begin
  if not public.is_admin() then
    raise exception 'Only admins can review claims' using errcode = '42501';
  end if;

  select * into c from public.official_claims where id = p_claim_id for update;
  if not found then
    raise exception 'Claim not found' using errcode = 'P0002';
  end if;
  if c.status <> 'pending' then
    raise exception 'Claim already %', c.status;
  end if;

  update public.official_claims
     set status = case when p_approve then 'approved' else 'rejected' end,
         review_note = p_note,
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_claim_id
   returning * into c;

  if p_approve then
    update public.officials
       set claimed_by = c.user_id, verified_at = now()
     where id = c.official_id;
    update public.users
       set role = 'official'
     where id = c.user_id and role = 'citizen';
  end if;

  return c;
end;
$$;

revoke execute on function public.review_official_claim(uuid, boolean, text) from public, anon;
grant execute on function public.review_official_claim(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- official_follows
-- ---------------------------------------------------------------------------
create table if not exists public.official_follows (
  user_id uuid not null references public.users (id) on delete cascade,
  official_id uuid not null references public.officials (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, official_id)
);

create index if not exists official_follows_official_idx
  on public.official_follows (official_id);

alter table public.official_follows enable row level security;

drop policy if exists "follows: read own" on public.official_follows;
create policy "follows: read own" on public.official_follows
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "follows: follow as self" on public.official_follows;
create policy "follows: follow as self" on public.official_follows
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "follows: unfollow own" on public.official_follows;
create policy "follows: unfollow own" on public.official_follows
  for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.official_follows from anon;
grant select, insert, delete on public.official_follows to authenticated;

-- ---------------------------------------------------------------------------
-- First admin: after signing up, run once in the SQL editor
--   update public.users set role = 'admin' where email = 'you@example.com';
-- ---------------------------------------------------------------------------
