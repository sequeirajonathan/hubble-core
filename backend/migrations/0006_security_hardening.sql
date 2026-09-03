-- 0006_security_hardening: findings from the Supabase security advisor.
--
-- 1. Postgres grants EXECUTE on new functions to PUBLIC, which exposes every
--    function (trigger bodies included) via /rest/v1/rpc. Revoke that default
--    and grant only what each role legitimately calls.
-- 2. Pin search_path on the functions that did not set one.
-- 3. Keep extensions out of the public schema.

-- ---------------------------------------------------------------------------
-- 1. function execution surface
-- ---------------------------------------------------------------------------
alter default privileges in schema public revoke execute on functions from public;

-- Trigger bodies and internal helpers: never callable over the API.
revoke execute on function
  public.set_updated_at(),
  public.handle_new_auth_user(),
  public.add_owner_membership(),
  public.seed_storefront_for_vendor(),
  public.notify_order_status(),
  public.enforce_cart_vendor_boundary(),
  public.generate_order_reference(),
  public.cart_line_total_cents(public.cart_items),
  public.default_storefront_ast(text)
from public, anon, authenticated;

-- RPCs intended for signed-in users only.
revoke execute on function
  public.has_vendor_role(),
  public.is_vendor_manager(uuid),
  public.get_or_create_cart(uuid),
  public.create_order_from_cart(uuid, uuid, integer, text),
  public.publish_storefront_draft(uuid),
  public.reset_storefront_draft(uuid),
  public.fan_out_campaign(uuid),
  public.set_niche_opt_in(public.vendor_niche, boolean),
  public.unread_mailbox_count()
from public, anon;

grant execute on function
  public.has_vendor_role(),
  public.is_vendor_manager(uuid),
  public.get_or_create_cart(uuid),
  public.create_order_from_cart(uuid, uuid, integer, text),
  public.publish_storefront_draft(uuid),
  public.reset_storefront_draft(uuid),
  public.fan_out_campaign(uuid),
  public.set_niche_opt_in(public.vendor_niche, boolean),
  public.unread_mailbox_count()
to authenticated, service_role;

-- is_vendor_member() stays executable by anon: RLS policies that anon rows
-- pass through (live vendors, products, layouts) evaluate it as the caller.
-- It only ever returns false for an anonymous session.
revoke execute on function public.is_vendor_member(uuid) from public;
grant execute on function public.is_vendor_member(uuid) to anon, authenticated;

-- Pure validators used by check constraints and the app: harmless, keep open
-- to signed-in callers so the vendor design screen can pre-validate.
revoke execute on function
  public.layout_node_types(),
  public.theme_token_keys(),
  public.layout_ast_is_valid(jsonb, integer),
  public.theme_tokens_are_valid(jsonb),
  public.haversine_km(double precision, double precision, double precision, double precision)
from public, anon;

grant execute on function
  public.layout_node_types(),
  public.theme_token_keys(),
  public.layout_ast_is_valid(jsonb, integer),
  public.theme_tokens_are_valid(jsonb),
  public.haversine_km(double precision, double precision, double precision, double precision)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. pinned search_path
-- ---------------------------------------------------------------------------
alter function public.set_updated_at() set search_path = public;
alter function public.haversine_km(double precision, double precision, double precision, double precision) set search_path = public;
alter function public.layout_node_types() set search_path = public;
alter function public.theme_token_keys() set search_path = public;
alter function public.layout_ast_is_valid(jsonb, integer) set search_path = public;
alter function public.theme_tokens_are_valid(jsonb) set search_path = public;
alter function public.default_storefront_ast(text) set search_path = public;
alter function public.enforce_cart_vendor_boundary() set search_path = public;
alter function public.cart_line_total_cents(public.cart_items) set search_path = public;
-- pgcrypto lives in `extensions` on Supabase and in `public` locally.
alter function public.generate_order_reference() set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 3. extensions out of public
-- ---------------------------------------------------------------------------
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;
do $$
begin
  if exists (
    select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'citext' and n.nspname = 'public'
  ) then
    alter extension citext set schema extensions;
  end if;
end
$$;
