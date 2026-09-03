-- 0004_mailbox: anti-spam in-app communication box + opt-out matrix.
-- Promotions never leave the database: campaigns fan out into
-- user_inapp_mailbox rows for users who are opted in to the vendor's niche
-- and within radius.

create type public.mailbox_kind as enum (
  'offer', 'notice', 'discount_code', 'order_update', 'system'
);

create type public.campaign_status as enum ('draft', 'sent', 'cancelled');

create table public.user_inapp_mailbox (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  vendor_id   uuid references public.vendors (id) on delete cascade,
  campaign_id uuid,
  kind        public.mailbox_kind not null,
  title       text not null check (char_length(title) between 1 and 120),
  body        text not null check (char_length(body) <= 2000),
  payload     jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz
);

create index mailbox_user_idx on public.user_inapp_mailbox (user_id, created_at desc);
create index mailbox_unread_idx on public.user_inapp_mailbox (user_id) where read_at is null;

-- Opt-out matrix: absence of a row means opted in (default). A row with
-- opted_in = false drops the user from targeting instantly.
create table public.user_niche_preferences (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  niche      public.vendor_niche not null,
  opted_in   boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, niche)
);

create trigger user_niche_preferences_set_updated_at
  before update on public.user_niche_preferences
  for each row execute function public.set_updated_at();

create table public.vendor_campaigns (
  id               uuid primary key default gen_random_uuid(),
  vendor_id        uuid not null references public.vendors (id) on delete cascade,
  kind             public.mailbox_kind not null default 'offer'
                   check (kind in ('offer', 'notice', 'discount_code')),
  title            text not null check (char_length(title) between 1 and 120),
  body             text not null check (char_length(body) <= 2000),
  payload          jsonb not null default '{}'::jsonb,
  radius_km        numeric(5, 1) not null default 10.0 check (radius_km > 0 and radius_km <= 100),
  status           public.campaign_status not null default 'draft',
  recipients_count integer not null default 0,
  expires_at       timestamptz,
  created_by       uuid references public.profiles (id) on delete set null,
  sent_at          timestamptz,
  created_at       timestamptz not null default now()
);

create index vendor_campaigns_vendor_idx on public.vendor_campaigns (vendor_id, created_at desc);

alter table public.user_inapp_mailbox
  add constraint mailbox_campaign_fk
  foreign key (campaign_id) references public.vendor_campaigns (id) on delete set null;

-- Localized targeting queue: one row per (user, niche) the user still accepts.
-- Flipping opted_in = false removes the row on the next read; no job needed.
create view public.campaign_targeting_queue with (security_invoker = false) as
  select p.id as user_id, n.niche, p.home_lat, p.home_lng
  from public.profiles p
  cross join unnest(enum_range(null::public.vendor_niche)) as n (niche)
  left join public.user_niche_preferences pref
    on pref.user_id = p.id and pref.niche = n.niche
  where coalesce(pref.opted_in, true)
    and p.home_lat is not null
    and p.home_lng is not null;

revoke all on public.campaign_targeting_queue from anon, authenticated;

-- Deliver a draft campaign into mailboxes. Idempotent per campaign.
create or replace function public.fan_out_campaign(p_campaign_id uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare
  c public.vendor_campaigns;
  v public.vendors;
  inserted integer;
begin
  select * into c from public.vendor_campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'campaign % not found', p_campaign_id using errcode = 'P0002';
  end if;
  if auth.uid() is not null and not public.is_vendor_manager(c.vendor_id) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if c.status <> 'draft' then
    return c.recipients_count;
  end if;

  select * into v from public.vendors where id = c.vendor_id;
  if v.lat is null or v.lng is null then
    raise exception 'vendor % has no location; cannot target a radius', v.id using errcode = '22023';
  end if;

  insert into public.user_inapp_mailbox (user_id, vendor_id, campaign_id, kind, title, body, payload, expires_at)
  select q.user_id, c.vendor_id, c.id, c.kind, c.title, c.body, c.payload, c.expires_at
  from public.campaign_targeting_queue q
  where q.niche = v.niche
    and q.user_id <> v.owner_id
    and public.haversine_km(q.home_lat, q.home_lng, v.lat, v.lng) <= c.radius_km;

  get diagnostics inserted = row_count;

  update public.vendor_campaigns
  set status = 'sent', sent_at = now(), recipients_count = inserted
  where id = c.id;

  return inserted;
end
$$;

-- Shopper-side helpers.
create or replace function public.set_niche_opt_in(p_niche public.vendor_niche, p_opted_in boolean)
returns public.user_niche_preferences
language plpgsql security definer set search_path = public as $$
declare
  r public.user_niche_preferences;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  insert into public.user_niche_preferences (user_id, niche, opted_in)
  values (auth.uid(), p_niche, p_opted_in)
  on conflict (user_id, niche) do update set opted_in = excluded.opted_in
  returning * into r;
  return r;
end
$$;

create or replace function public.unread_mailbox_count() returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::integer from public.user_inapp_mailbox
  where user_id = auth.uid() and read_at is null and (expires_at is null or expires_at > now());
$$;

-- Order status changes land in the customer's mailbox too.
create or replace function public.notify_order_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into public.user_inapp_mailbox (user_id, vendor_id, kind, title, body, payload)
    values (
      new.customer_id, new.vendor_id, 'order_update',
      'Order ' || new.reference_code || ' is ' || replace(new.status::text, '_', ' '),
      'Your order status changed to ' || replace(new.status::text, '_', ' ') || '.',
      jsonb_build_object('order_id', new.id, 'status', new.status)
    );
  end if;
  return new;
end
$$;

create trigger orders_notify_status
  after update on public.orders
  for each row execute function public.notify_order_status();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.user_inapp_mailbox    enable row level security;
alter table public.user_niche_preferences enable row level security;
alter table public.vendor_campaigns       enable row level security;

create policy mailbox_select_own on public.user_inapp_mailbox
  for select to authenticated using (user_id = auth.uid());
create policy mailbox_update_own on public.user_inapp_mailbox
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy mailbox_delete_own on public.user_inapp_mailbox
  for delete to authenticated using (user_id = auth.uid());

create policy niche_prefs_own on public.user_niche_preferences
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy campaigns_member on public.vendor_campaigns
  for all to authenticated
  using (public.is_vendor_member(vendor_id)) with check (public.is_vendor_manager(vendor_id));

grant select, update, delete on public.user_inapp_mailbox to authenticated;
grant select, insert, update, delete on public.user_niche_preferences, public.vendor_campaigns to authenticated;
grant all on all tables in schema public to service_role;
grant execute on function public.fan_out_campaign(uuid) to authenticated, service_role;
grant execute on function public.set_niche_opt_in(public.vendor_niche, boolean), public.unread_mailbox_count() to authenticated;
