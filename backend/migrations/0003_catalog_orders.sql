-- 0003_catalog_orders: products, per-vendor carts (single-store checkout
-- boundary), orders and line items.

create type public.order_status as enum (
  'pending_payment', 'paid', 'accepted', 'ready', 'completed',
  'cancelled', 'refunded', 'failed'
);

-- ---------------------------------------------------------------------------
-- catalog
-- ---------------------------------------------------------------------------
create table public.products (
  id           uuid primary key default gen_random_uuid(),
  vendor_id    uuid not null references public.vendors (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 120),
  description  text,
  sku          text,
  price_cents  integer not null check (price_cents >= 0),
  currency     char(3) not null default 'usd',
  image_url    text,
  is_available boolean not null default true,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (vendor_id, sku)
);

create index products_vendor_idx on public.products (vendor_id, sort_order);

create trigger products_set_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();

create table public.product_modifier_groups (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products (id) on delete cascade,
  name        text not null,
  min_select  integer not null default 0 check (min_select >= 0),
  max_select  integer not null default 1 check (max_select >= 1),
  sort_order  integer not null default 0,
  check (max_select >= min_select)
);

create table public.product_modifiers (
  id                uuid primary key default gen_random_uuid(),
  group_id          uuid not null references public.product_modifier_groups (id) on delete cascade,
  name              text not null,
  price_delta_cents integer not null default 0,
  is_available      boolean not null default true,
  sort_order        integer not null default 0
);

-- ---------------------------------------------------------------------------
-- carts: exactly one cart per (customer, vendor). There is no global cart.
-- ---------------------------------------------------------------------------
create table public.carts (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  vendor_id   uuid not null references public.vendors (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (customer_id, vendor_id)
);

create trigger carts_set_updated_at
  before update on public.carts
  for each row execute function public.set_updated_at();

create table public.cart_items (
  id               uuid primary key default gen_random_uuid(),
  cart_id          uuid not null references public.carts (id) on delete cascade,
  product_id       uuid not null references public.products (id) on delete cascade,
  quantity         integer not null check (quantity between 1 and 99),
  modifiers        jsonb not null default '[]'::jsonb check (jsonb_typeof(modifiers) = 'array'),
  note             text check (note is null or char_length(note) <= 280),
  created_at       timestamptz not null default now()
);

create index cart_items_cart_idx on public.cart_items (cart_id);

-- Boundary enforcement: a cart item must belong to the cart's vendor.
create or replace function public.enforce_cart_vendor_boundary() returns trigger
language plpgsql as $$
declare
  cart_vendor uuid;
  product_vendor uuid;
begin
  select vendor_id into cart_vendor from public.carts where id = new.cart_id;
  select vendor_id into product_vendor from public.products where id = new.product_id;
  if cart_vendor is null or product_vendor is null or cart_vendor <> product_vendor then
    raise exception 'cart % is bound to a different vendor than product %', new.cart_id, new.product_id
      using errcode = '23514', hint = 'Items are grouped per vendor; create a cart for that vendor.';
  end if;
  return new;
end
$$;

create trigger cart_items_vendor_boundary
  before insert or update on public.cart_items
  for each row execute function public.enforce_cart_vendor_boundary();

-- Convenience: fetch-or-create the caller's cart for a vendor.
create or replace function public.get_or_create_cart(p_vendor_id uuid) returns public.carts
language plpgsql security definer set search_path = public as $$
declare
  c public.carts;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  insert into public.carts (customer_id, vendor_id) values (auth.uid(), p_vendor_id)
  on conflict (customer_id, vendor_id) do update set updated_at = now()
  returning * into c;
  return c;
end
$$;

-- ---------------------------------------------------------------------------
-- orders
-- ---------------------------------------------------------------------------
create or replace function public.generate_order_reference() returns text
language sql volatile as $$
  -- HB-XXXXXX: short, unambiguous, readable on a bank statement.
  select 'HB-' || upper(substr(translate(encode(gen_random_bytes(6), 'base64'), '+/=0O1Il', 'ABCDEFGH'), 1, 6));
$$;

create table public.orders (
  id                       uuid primary key default gen_random_uuid(),
  reference_code           text not null unique default public.generate_order_reference(),
  vendor_id                uuid not null references public.vendors (id) on delete restrict,
  customer_id              uuid not null references public.profiles (id) on delete restrict,
  status                   public.order_status not null default 'pending_payment',
  currency                 char(3) not null default 'usd',
  subtotal_cents           integer not null check (subtotal_cents >= 0),
  platform_fee_cents       integer not null default 0 check (platform_fee_cents >= 0),
  tax_cents                integer not null default 0 check (tax_cents >= 0),
  total_cents              integer not null check (total_cents >= 0),
  stripe_payment_intent_id text unique,
  stripe_transfer_id       text,
  customer_note            text,
  failure_reason           text,
  paid_at                  timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index orders_vendor_status_idx on public.orders (vendor_id, status, created_at desc);
create index orders_customer_idx on public.orders (customer_id, created_at desc);

create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();

create table public.order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders (id) on delete cascade,
  product_id       uuid references public.products (id) on delete set null,
  name_snapshot    text not null,
  unit_price_cents integer not null check (unit_price_cents >= 0),
  quantity         integer not null check (quantity >= 1),
  modifiers        jsonb not null default '[]'::jsonb,
  line_total_cents integer not null check (line_total_cents >= 0)
);

create index order_items_order_idx on public.order_items (order_id);

-- Price a cart from current catalog data. Modifier deltas are looked up by id
-- so the client cannot forge prices.
create or replace function public.cart_line_total_cents(p_item public.cart_items) returns integer
language sql stable as $$
  select (
    p.price_cents + coalesce((
      select sum(m.price_delta_cents)
      from jsonb_array_elements_text(p_item.modifiers) mid
      join public.product_modifiers m on m.id::text = mid
    ), 0)
  ) * p_item.quantity
  from public.products p
  where p.id = p_item.product_id;
$$;

-- Turn the caller's cart for one vendor into a pending order. Called by the
-- stripe-split edge function (service role, acting on behalf of p_customer_id)
-- or directly by the customer.
create or replace function public.create_order_from_cart(
  p_vendor_id uuid,
  p_customer_id uuid default auth.uid(),
  p_platform_fee_bps integer default 500,
  p_note text default null
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  c public.carts;
  o public.orders;
  subtotal integer;
  fee integer;
begin
  if p_customer_id is null then
    raise exception 'customer required' using errcode = '42501';
  end if;
  if auth.uid() is not null and auth.uid() <> p_customer_id then
    raise exception 'cannot checkout another customer''s cart' using errcode = '42501';
  end if;

  select * into c from public.carts where customer_id = p_customer_id and vendor_id = p_vendor_id for update;
  if not found then
    raise exception 'no cart for vendor %', p_vendor_id using errcode = 'P0002';
  end if;

  select coalesce(sum(public.cart_line_total_cents(ci)), 0) into subtotal
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = c.id and p.is_available;

  if subtotal <= 0 then
    raise exception 'cart is empty' using errcode = 'P0002';
  end if;

  fee := (subtotal * p_platform_fee_bps + 5000) / 10000;

  insert into public.orders (vendor_id, customer_id, subtotal_cents, platform_fee_cents, total_cents, customer_note)
  values (p_vendor_id, p_customer_id, subtotal, fee, subtotal, p_note)
  returning * into o;

  insert into public.order_items (order_id, product_id, name_snapshot, unit_price_cents, quantity, modifiers, line_total_cents)
  select o.id, p.id, p.name, p.price_cents, ci.quantity, ci.modifiers, public.cart_line_total_cents(ci)
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = c.id and p.is_available;

  delete from public.cart_items where cart_id = c.id;
  return o;
end
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.products                enable row level security;
alter table public.product_modifier_groups enable row level security;
alter table public.product_modifiers       enable row level security;
alter table public.carts                   enable row level security;
alter table public.cart_items              enable row level security;
alter table public.orders                  enable row level security;
alter table public.order_items             enable row level security;

create policy products_select on public.products
  for select to anon, authenticated
  using (exists (select 1 from public.vendors v where v.id = vendor_id and v.is_live) or public.is_vendor_member(vendor_id));
create policy products_manage on public.products
  for all to authenticated
  using (public.is_vendor_manager(vendor_id)) with check (public.is_vendor_manager(vendor_id));

create policy modifier_groups_select on public.product_modifier_groups
  for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id));
create policy modifier_groups_manage on public.product_modifier_groups
  for all to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and public.is_vendor_manager(p.vendor_id)))
  with check (exists (select 1 from public.products p where p.id = product_id and public.is_vendor_manager(p.vendor_id)));

create policy modifiers_select on public.product_modifiers
  for select to anon, authenticated
  using (exists (select 1 from public.product_modifier_groups g where g.id = group_id));
create policy modifiers_manage on public.product_modifiers
  for all to authenticated
  using (exists (
    select 1 from public.product_modifier_groups g join public.products p on p.id = g.product_id
    where g.id = group_id and public.is_vendor_manager(p.vendor_id)))
  with check (exists (
    select 1 from public.product_modifier_groups g join public.products p on p.id = g.product_id
    where g.id = group_id and public.is_vendor_manager(p.vendor_id)));

create policy carts_owner on public.carts
  for all to authenticated using (customer_id = auth.uid()) with check (customer_id = auth.uid());
create policy cart_items_owner on public.cart_items
  for all to authenticated
  using (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = auth.uid()))
  with check (exists (select 1 from public.carts c where c.id = cart_id and c.customer_id = auth.uid()));

create policy orders_select on public.orders
  for select to authenticated using (customer_id = auth.uid() or public.is_vendor_member(vendor_id));
create policy orders_vendor_update on public.orders
  for update to authenticated
  using (public.is_vendor_member(vendor_id)) with check (public.is_vendor_member(vendor_id));
create policy order_items_select on public.order_items
  for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or public.is_vendor_member(o.vendor_id))));

grant select on public.products, public.product_modifier_groups, public.product_modifiers to anon;
grant select, insert, update, delete on
  public.products, public.product_modifier_groups, public.product_modifiers,
  public.carts, public.cart_items to authenticated;
grant select, update on public.orders to authenticated;
grant select on public.order_items to authenticated;
grant all on all tables in schema public to service_role;
grant execute on function public.get_or_create_cart(uuid) to authenticated;
grant execute on function public.create_order_from_cart(uuid, uuid, integer, text) to authenticated, service_role;
