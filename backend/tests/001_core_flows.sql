\o /dev/null
-- Behavioural tests for the schema. Runs inside one transaction and rolls
-- back, so it is safe against any migrated database. Every assertion raises
-- on failure so psql -v ON_ERROR_STOP=1 turns a regression into a red build.
begin;

-- fixtures --------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'owner@example.com', '{"display_name":"Owner"}'),
  ('00000000-0000-0000-0000-000000000002', 'shopper@example.com', '{}'),
  ('00000000-0000-0000-0000-000000000003', 'far@example.com', '{}'),
  ('00000000-0000-0000-0000-000000000004', 'optout@example.com', '{}');

do $$
begin
  assert (select count(*) from public.profiles) = 4, 'profiles mirrored from auth.users';
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000001') = 'Owner';
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000002') = 'shopper';
end $$;

update public.profiles set home_lat = 29.7604, home_lng = -95.3698 where id = '00000000-0000-0000-0000-000000000002'; -- Houston
update public.profiles set home_lat = 30.2672, home_lng = -97.7431 where id = '00000000-0000-0000-0000-000000000003'; -- Austin (~235km)
update public.profiles set home_lat = 29.7620, home_lng = -95.3700 where id = '00000000-0000-0000-0000-000000000004'; -- Houston

-- act as the owner
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into public.vendors (id, owner_id, slug, name, niche, lat, lng, is_live)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'taco-bolt', 'Taco Bolt', 'food_truck', 29.7600, -95.3690, true);
insert into public.vendors (id, owner_id, slug, name, niche, is_live)
values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'card-forge', 'Card Forge', 'card_shop', true);

do $$
begin
  assert public.is_vendor_member('10000000-0000-0000-0000-000000000001'), 'owner auto-enrolled as member';
  assert (select role from public.vendor_members where vendor_id = '10000000-0000-0000-0000-000000000001' and user_id = auth.uid()) = 'owner';
  assert (select count(*) from public.storefront_layouts where vendor_id = '10000000-0000-0000-0000-000000000001') = 1, 'live layout seeded';
  assert (select count(*) from public.storefront_layouts_draft where vendor_id = '10000000-0000-0000-0000-000000000001') = 1, 'draft layout seeded';
  assert (select ast ->> 'type' from public.storefront_layouts where vendor_id = '10000000-0000-0000-0000-000000000001') = 'screen';
end $$;

-- AST validation --------------------------------------------------------
do $$
begin
  assert public.layout_ast_is_valid('{"type":"screen","children":[{"type":"text","props":{"text":"hi"}}]}'::jsonb);
  assert not public.layout_ast_is_valid('{"type":"column"}'::jsonb), 'root must be a screen';
  assert not public.layout_ast_is_valid('{"type":"screen","children":[{"type":"webview"}]}'::jsonb), 'unknown node rejected';
  assert not public.layout_ast_is_valid('{"type":"screen","children":{"type":"text"}}'::jsonb), 'children must be array';
  assert public.theme_tokens_are_valid('{"accent":"#FF7A00"}'::jsonb);
  assert not public.theme_tokens_are_valid('{"accent":"orange"}'::jsonb), 'non-hex rejected';
  assert not public.theme_tokens_are_valid('{"font":"#FFFFFF"}'::jsonb), 'unknown token key rejected';
end $$;

do $$
begin
  begin
    update public.storefront_layouts_draft
    set ast = '{"type":"screen","children":[{"type":"script"}]}'::jsonb
    where vendor_id = '10000000-0000-0000-0000-000000000001';
    raise exception 'expected check violation';
  exception when check_violation then
    null;
  end;
end $$;

-- publish flow ------------------------------------------------------------
update public.storefront_layouts_draft
set ast = '{"type":"screen","children":[{"type":"hero","props":{"title":"Taco Bolt v2"}}]}'::jsonb,
    theme = '{"accent":"#00AAFF"}'::jsonb
where vendor_id = '10000000-0000-0000-0000-000000000001';

select public.publish_storefront_draft('10000000-0000-0000-0000-000000000001');

do $$
declare
  live public.storefront_layouts;
begin
  select * into live from public.storefront_layouts where vendor_id = '10000000-0000-0000-0000-000000000001';
  assert live.version = 2, 'version bumped to 2, got ' || live.version;
  assert live.theme ->> 'accent' = '#00AAFF', 'theme published';
  assert live.ast -> 'children' -> 0 ->> 'type' = 'hero';
  assert (select count(*) from public.storefront_layout_history where vendor_id = live.vendor_id and version = 1) = 1, 'v1 archived';
end $$;

-- catalog -----------------------------------------------------------------
insert into public.products (id, vendor_id, name, price_cents) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Street Taco', 350),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Horchata', 400),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'Booster Pack', 499);

insert into public.product_modifier_groups (id, product_id, name) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Extras');
insert into public.product_modifiers (id, group_id, name, price_delta_cents) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Extra meat', 150);

-- act as the shopper ------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);

do $$
begin
  assert not public.has_vendor_role(), 'shopper has no vendor role';
  assert (select count(*) from public.storefront_layouts_draft) = 0, 'shopper cannot see drafts';
  assert (select count(*) from public.storefront_layouts) = 2, 'shopper sees live layouts';
end $$;

select public.get_or_create_cart('10000000-0000-0000-0000-000000000001');
select public.get_or_create_cart('10000000-0000-0000-0000-000000000001'); -- idempotent
select public.get_or_create_cart('10000000-0000-0000-0000-000000000002');

do $$
begin
  assert (select count(*) from public.carts where customer_id = auth.uid()) = 2, 'one cart per vendor';
end $$;

insert into public.cart_items (cart_id, product_id, quantity, modifiers)
select c.id, '20000000-0000-0000-0000-000000000001', 2, '["40000000-0000-0000-0000-000000000001"]'::jsonb
from public.carts c where c.customer_id = auth.uid() and c.vendor_id = '10000000-0000-0000-0000-000000000001';
insert into public.cart_items (cart_id, product_id, quantity)
select c.id, '20000000-0000-0000-0000-000000000002', 1
from public.carts c where c.customer_id = auth.uid() and c.vendor_id = '10000000-0000-0000-0000-000000000001';

-- boundary: a Card Forge product cannot enter the Taco Bolt cart
do $$
begin
  begin
    insert into public.cart_items (cart_id, product_id, quantity)
    select c.id, '20000000-0000-0000-0000-000000000003', 1
    from public.carts c where c.customer_id = auth.uid() and c.vendor_id = '10000000-0000-0000-0000-000000000001';
    raise exception 'expected boundary violation';
  exception when check_violation then
    null;
  end;
end $$;

-- checkout ----------------------------------------------------------------
do $$
declare
  o public.orders;
begin
  o := public.create_order_from_cart('10000000-0000-0000-0000-000000000001', auth.uid(), 500);
  assert o.subtotal_cents = (350 + 150) * 2 + 400, 'subtotal priced from catalog + modifiers, got ' || o.subtotal_cents;
  assert o.platform_fee_cents = 70, 'fee 5% rounded, got ' || o.platform_fee_cents;
  assert o.status = 'pending_payment';
  assert o.reference_code ~ '^HB-[A-Z0-9]{6}$', 'reference code ' || o.reference_code;
  assert (select count(*) from public.order_items where order_id = o.id) = 2;
  assert (select count(*) from public.cart_items ci join public.carts c on c.id = ci.cart_id
          where c.customer_id = auth.uid() and c.vendor_id = '10000000-0000-0000-0000-000000000001') = 0, 'cart emptied';
  begin
    perform public.create_order_from_cart('10000000-0000-0000-0000-000000000001', auth.uid(), 500);
    raise exception 'expected empty cart error';
  exception when no_data_found then
    null;
  end;
  begin
    perform public.create_order_from_cart('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 500);
    raise exception 'expected authorization error';
  exception when insufficient_privilege then
    null;
  end;
end $$;

-- order status update lands in the mailbox (service role path)
reset role;
update public.orders set status = 'paid', paid_at = now() where customer_id = '00000000-0000-0000-0000-000000000002';
do $$
begin
  assert (select count(*) from public.user_inapp_mailbox
          where user_id = '00000000-0000-0000-0000-000000000002' and kind = 'order_update') = 1, 'order update delivered';
end $$;

-- opt-out matrix + campaign fan-out -------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
select public.set_niche_opt_in('food_truck', false);

do $$
begin
  assert (select count(*) from public.user_niche_preferences where user_id = auth.uid() and opted_in = false) = 1;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
insert into public.vendor_campaigns (id, vendor_id, kind, title, body, radius_km, created_by)
values ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'offer', '2-for-1 tacos', 'Today only', 10, auth.uid());

do $$
declare
  n integer;
begin
  n := public.fan_out_campaign('50000000-0000-0000-0000-000000000001');
  assert n = 1, 'only the nearby opted-in shopper receives it, got ' || n;
  assert public.fan_out_campaign('50000000-0000-0000-0000-000000000001') = 1, 'idempotent re-send';
  assert (select status from public.vendor_campaigns where id = '50000000-0000-0000-0000-000000000001') = 'sent';
end $$;

reset role;
do $$
begin
  assert (select count(*) from public.user_inapp_mailbox where user_id = '00000000-0000-0000-0000-000000000002' and kind = 'offer') = 1, 'nearby shopper got the offer';
  assert (select count(*) from public.user_inapp_mailbox where user_id = '00000000-0000-0000-0000-000000000003') = 0, 'far shopper excluded by radius';
  assert (select count(*) from public.user_inapp_mailbox where user_id = '00000000-0000-0000-0000-000000000004') = 0, 'opted-out shopper excluded';
  assert (select count(*) from public.user_inapp_mailbox where user_id = '00000000-0000-0000-0000-000000000001') = 0, 'owner not spammed by own campaign';
end $$;

-- shopper can read + mark read, but only their own
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
do $$
begin
  assert public.unread_mailbox_count() = 2, 'unread count, got ' || public.unread_mailbox_count();
  update public.user_inapp_mailbox set read_at = now() where kind = 'offer';
  assert public.unread_mailbox_count() = 1;
  assert (select count(*) from public.user_inapp_mailbox) = 2, 'sees only own mailbox';
end $$;

-- review cache aggregation -----------------------------------------------
reset role;
update public.vendors set google_place_id = 'ChIJ-test', yelp_business_id = 'taco-bolt-houston'
where id = '10000000-0000-0000-0000-000000000001';

do $$
begin
  assert (select count(*) from public.vendors_needing_review_sync()) = 2, 'both sources need a sync';
end $$;

insert into public.vendor_review_cache (vendor_id, source, external_id, rating, review_count) values
  ('10000000-0000-0000-0000-000000000001', 'google', 'ChIJ-test', 4.50, 100),
  ('10000000-0000-0000-0000-000000000001', 'yelp', 'taco-bolt-houston', 3.50, 100);

do $$
declare
  r public.vendor_ratings;
begin
  select * into r from public.vendor_ratings where vendor_id = '10000000-0000-0000-0000-000000000001';
  assert r.rating = 4.00, 'weighted average, got ' || r.rating;
  assert r.review_count = 200;
  assert (select count(*) from public.vendors_needing_review_sync()) = 0, 'fresh cache needs no sync';
  update public.vendor_review_cache set expires_at = now() - interval '1 minute' where source = 'yelp';
  assert (select count(*) from public.vendors_needing_review_sync()) = 1, 'expired row re-queued';
  select * into r from public.vendor_ratings where vendor_id = '10000000-0000-0000-0000-000000000001';
  assert r.rating = 4.50 and r.review_count = 100, 'expired source excluded from the aggregate';
end $$;

\o
\echo ALL SQL TESTS PASSED
rollback;
