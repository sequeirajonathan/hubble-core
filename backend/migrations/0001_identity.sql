-- 0001_identity: global profiles, vendors, membership, role helpers.
-- Single-sign-on: every human is one auth.users row -> one profiles row.
-- Vendor capability is derived from vendor_members, never stored on the profile.

create extension if not exists pgcrypto;
create extension if not exists citext;

create type public.vendor_niche as enum (
  'food_truck', 'card_shop', 'startup', 'retail', 'services', 'other'
);

create type public.vendor_role as enum ('owner', 'manager', 'staff');

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  display_name        text,
  email               citext,
  phone               text,
  avatar_url          text,
  home_lat            double precision,
  home_lng            double precision,
  discovery_radius_km numeric(5, 1) not null default 15.0
                      check (discovery_radius_km > 0 and discovery_radius_km <= 200),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint profiles_home_location_pair check (
    (home_lat is null and home_lng is null) or (home_lat is not null and home_lng is not null)
  )
);

comment on table public.profiles is
  'One row per authenticated human. Shopper and vendor views share this identity.';

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Mirror new auth users into profiles automatically.
create or replace function public.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, phone, display_name)
  values (
    new.id,
    new.email,
    new.phone,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(coalesce(new.email, ''), '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- vendors + membership
-- ---------------------------------------------------------------------------
create table public.vendors (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.profiles (id) on delete restrict,
  slug               citext not null unique
                     check (slug ~ '^[a-z0-9](?:[a-z0-9-]{1,46}[a-z0-9])?$'),
  name               text not null check (char_length(name) between 2 and 80),
  tagline            text check (tagline is null or char_length(tagline) <= 140),
  niche              public.vendor_niche not null default 'other',
  logo_url           text,
  lat                double precision,
  lng                double precision,
  address_text       text,
  phone              text,
  website_url        text check (website_url is null or website_url ~ '^https://'),
  hours_text         text check (hours_text is null or char_length(hours_text) <= 500),
  stripe_account_id  text unique,
  google_place_id    text,
  yelp_business_id   text,
  is_live            boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint vendors_location_pair check (
    (lat is null and lng is null) or (lat is not null and lng is not null)
  )
);

create index vendors_niche_idx on public.vendors (niche) where is_live;
create index vendors_location_idx on public.vendors (lat, lng) where is_live;

create trigger vendors_set_updated_at
  before update on public.vendors
  for each row execute function public.set_updated_at();

create table public.vendor_members (
  vendor_id  uuid not null references public.vendors (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       public.vendor_role not null default 'staff',
  created_at timestamptz not null default now(),
  primary key (vendor_id, user_id)
);

create index vendor_members_user_idx on public.vendor_members (user_id);

-- The creator is always an owner member.
create or replace function public.add_owner_membership() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.vendor_members (vendor_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (vendor_id, user_id) do update set role = 'owner';
  return new;
end
$$;

create trigger vendors_add_owner_membership
  after insert on public.vendors
  for each row execute function public.add_owner_membership();

-- ---------------------------------------------------------------------------
-- role helpers (security definer so RLS policies can call them cheaply)
-- ---------------------------------------------------------------------------
create or replace function public.is_vendor_member(p_vendor_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.vendor_members m
    where m.vendor_id = p_vendor_id and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_vendor_manager(p_vendor_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.vendor_members m
    where m.vendor_id = p_vendor_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'manager')
  );
$$;

create or replace function public.has_vendor_role() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.vendor_members m where m.user_id = auth.uid());
$$;

-- Distance helper used by discovery + campaign targeting (great-circle, km).
create or replace function public.haversine_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision
language sql immutable strict as $$
  select 6371.0088 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- ---------------------------------------------------------------------------
-- row level security
-- ---------------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.vendors        enable row level security;
alter table public.vendor_members enable row level security;

create policy profiles_select_self on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_update_self on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy vendors_select_live_or_member on public.vendors
  for select to anon, authenticated
  using (is_live or public.is_vendor_member(id));
create policy vendors_insert_owner on public.vendors
  for insert to authenticated with check (owner_id = auth.uid());
create policy vendors_update_manager on public.vendors
  for update to authenticated
  using (public.is_vendor_manager(id)) with check (public.is_vendor_manager(id));
create policy vendors_delete_owner on public.vendors
  for delete to authenticated using (owner_id = auth.uid());

create policy vendor_members_select on public.vendor_members
  for select to authenticated
  using (user_id = auth.uid() or public.is_vendor_member(vendor_id));
create policy vendor_members_manage on public.vendor_members
  for all to authenticated
  using (public.is_vendor_manager(vendor_id)) with check (public.is_vendor_manager(vendor_id));

grant usage on schema public to anon, authenticated, service_role;
grant select on public.vendors to anon;
grant select, insert, update, delete on public.profiles, public.vendors, public.vendor_members to authenticated;
grant all on all tables in schema public to service_role;
