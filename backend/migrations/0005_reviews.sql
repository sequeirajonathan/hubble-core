-- 0005_reviews: abstracted review cache aggregator.
-- The review-sync edge function reads Google Places / Yelp Fusion, computes a
-- count-weighted average and caches it here for exactly 24 hours.

create type public.review_source as enum ('google', 'yelp');

create table public.vendor_review_cache (
  vendor_id    uuid not null references public.vendors (id) on delete cascade,
  source       public.review_source not null,
  external_id  text not null,
  rating       numeric(3, 2) not null check (rating >= 0 and rating <= 5),
  review_count integer not null check (review_count >= 0),
  raw          jsonb not null default '{}'::jsonb,
  fetched_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '24 hours',
  primary key (vendor_id, source)
);

create index vendor_review_cache_expiry_idx on public.vendor_review_cache (expires_at);

-- Absolute internal average across sources, weighted by review count.
create view public.vendor_ratings with (security_invoker = true) as
  select
    vendor_id,
    round((sum(rating * review_count) / nullif(sum(review_count), 0))::numeric, 2) as rating,
    sum(review_count)::integer as review_count,
    array_agg(source order by source) as sources,
    max(fetched_at) as fetched_at,
    min(expires_at) as expires_at
  from public.vendor_review_cache
  where expires_at > now()
  group by vendor_id;

-- Vendors whose cache is missing or expired for a source they have an id for.
create or replace function public.vendors_needing_review_sync(p_limit integer default 50)
returns table (vendor_id uuid, source public.review_source, external_id text)
language sql stable security definer set search_path = public as $$
  with candidates as (
    select v.id as vendor_id, 'google'::public.review_source as source, v.google_place_id as external_id
    from public.vendors v where v.google_place_id is not null
    union all
    select v.id, 'yelp'::public.review_source, v.yelp_business_id
    from public.vendors v where v.yelp_business_id is not null
  )
  select c.vendor_id, c.source, c.external_id
  from candidates c
  left join public.vendor_review_cache rc on rc.vendor_id = c.vendor_id and rc.source = c.source
  where rc.vendor_id is null or rc.expires_at <= now()
  order by rc.expires_at nulls first
  limit p_limit;
$$;

revoke all on function public.vendors_needing_review_sync(integer) from public, anon, authenticated;
grant execute on function public.vendors_needing_review_sync(integer) to service_role;

alter table public.vendor_review_cache enable row level security;

create policy review_cache_select on public.vendor_review_cache
  for select to anon, authenticated
  using (exists (select 1 from public.vendors v where v.id = vendor_id and v.is_live) or public.is_vendor_member(vendor_id));

grant select on public.vendor_review_cache, public.vendor_ratings to anon, authenticated;
grant all on all tables in schema public to service_role;
