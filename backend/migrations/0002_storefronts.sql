-- 0002_storefronts: AST layouts (live + draft), theme tokens, publish flow.
-- The app renders storefront_layouts.ast at runtime. Vendors edit
-- storefront_layouts_draft and preview it in-app before publishing.

-- Node types the mobile interpreter knows how to render. Keep in sync with
-- backend/supabase/functions/_shared/ast.ts and app/lib/interpreter/ast_node.dart.
create or replace function public.layout_node_types() returns text[]
language sql immutable as $$
  select array[
    'screen', 'column', 'row', 'stack', 'spacer', 'divider',
    'text', 'image', 'hero', 'badge', 'button', 'product_list', 'product_card',
    'hours', 'map_pin', 'contact'
  ];
$$;

-- Theme keys a vendor is allowed to override. Others are host-owned.
create or replace function public.theme_token_keys() returns text[]
language sql immutable as $$
  select array['canvas', 'surface', 'accent', 'iron', 'alert', 'on_accent', 'on_canvas'];
$$;

-- Recursive structural validation: every node has a known "type", children
-- are arrays of nodes, and depth is bounded so a hostile payload cannot blow
-- the renderer's stack.
create or replace function public.layout_ast_is_valid(node jsonb, depth integer default 0)
returns boolean
language plpgsql immutable as $$
declare
  child jsonb;
  props jsonb;
begin
  if depth > 24 then
    return false;
  end if;
  if node is null or jsonb_typeof(node) <> 'object' then
    return false;
  end if;
  if not (node ? 'type') or jsonb_typeof(node -> 'type') <> 'string' then
    return false;
  end if;
  if not ((node ->> 'type') = any (public.layout_node_types())) then
    return false;
  end if;
  if depth = 0 and (node ->> 'type') <> 'screen' then
    return false;
  end if;
  props := node -> 'props';
  if props is not null and jsonb_typeof(props) <> 'object' then
    return false;
  end if;
  if node ? 'children' then
    if jsonb_typeof(node -> 'children') <> 'array' then
      return false;
    end if;
    if jsonb_array_length(node -> 'children') > 200 then
      return false;
    end if;
    for child in select value from jsonb_array_elements(node -> 'children') loop
      if not public.layout_ast_is_valid(child, depth + 1) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end
$$;

create or replace function public.theme_tokens_are_valid(theme jsonb) returns boolean
language plpgsql immutable as $$
declare
  k text;
  v jsonb;
begin
  if theme is null or jsonb_typeof(theme) <> 'object' then
    return false;
  end if;
  for k, v in select key, value from jsonb_each(theme) loop
    if not (k = any (public.theme_token_keys())) then
      return false;
    end if;
    if jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^#[0-9A-Fa-f]{6}$' then
      return false;
    end if;
  end loop;
  return true;
end
$$;

-- Starter layout every new vendor gets so their storefront is never blank.
create or replace function public.default_storefront_ast(p_vendor_name text) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'type', 'screen',
    'props', jsonb_build_object('scroll', true),
    'children', jsonb_build_array(
      jsonb_build_object(
        'type', 'hero',
        'props', jsonb_build_object(
          'title', p_vendor_name,
          'subtitle', 'Now open in your neighborhood',
          'logo', jsonb_build_object('$bind', 'vendor.logo_url')
        )
      ),
      jsonb_build_object('type', 'divider'),
      jsonb_build_object(
        'type', 'text',
        'props', jsonb_build_object('text', 'MENU', 'style', 'display')
      ),
      jsonb_build_object(
        'type', 'product_list',
        'props', jsonb_build_object('source', 'vendor.products', 'layout', 'list')
      ),
      jsonb_build_object('type', 'spacer', 'props', jsonb_build_object('size', 24)),
      jsonb_build_object(
        'type', 'button',
        'props', jsonb_build_object('label', 'VIEW CART', 'action', 'open_cart', 'variant', 'primary')
      )
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- tables
-- ---------------------------------------------------------------------------
create table public.storefront_layouts (
  vendor_id    uuid primary key references public.vendors (id) on delete cascade,
  version      integer not null default 1 check (version >= 1),
  ast          jsonb not null check (public.layout_ast_is_valid(ast)),
  theme        jsonb not null default '{}'::jsonb check (public.theme_tokens_are_valid(theme)),
  published_at timestamptz not null default now(),
  published_by uuid references public.profiles (id) on delete set null
);

create table public.storefront_layouts_draft (
  vendor_id   uuid primary key references public.vendors (id) on delete cascade,
  ast         jsonb not null check (public.layout_ast_is_valid(ast)),
  theme       jsonb not null default '{}'::jsonb check (public.theme_tokens_are_valid(theme)),
  ai_history  jsonb not null default '[]'::jsonb,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null
);

create trigger storefront_layouts_draft_set_updated_at
  before update on public.storefront_layouts_draft
  for each row execute function public.set_updated_at();

create table public.storefront_layout_history (
  id           bigint generated always as identity primary key,
  vendor_id    uuid not null references public.vendors (id) on delete cascade,
  version      integer not null,
  ast          jsonb not null,
  theme        jsonb not null,
  published_at timestamptz not null,
  published_by uuid,
  unique (vendor_id, version)
);

-- Seed live + draft when a vendor is created.
create or replace function public.seed_storefront_for_vendor() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  seed jsonb := public.default_storefront_ast(new.name);
begin
  insert into public.storefront_layouts (vendor_id, ast, published_by)
  values (new.id, seed, new.owner_id)
  on conflict (vendor_id) do nothing;
  insert into public.storefront_layouts_draft (vendor_id, ast, updated_by)
  values (new.id, seed, new.owner_id)
  on conflict (vendor_id) do nothing;
  return new;
end
$$;

create trigger vendors_seed_storefront
  after insert on public.vendors
  for each row execute function public.seed_storefront_for_vendor();

-- Promote the draft to live. Archives the outgoing live version first.
create or replace function public.publish_storefront_draft(p_vendor_id uuid)
returns public.storefront_layouts
language plpgsql security definer set search_path = public as $$
declare
  draft public.storefront_layouts_draft;
  live  public.storefront_layouts;
begin
  if not public.is_vendor_manager(p_vendor_id) then
    raise exception 'not authorized to publish for vendor %', p_vendor_id
      using errcode = '42501';
  end if;

  select * into draft from public.storefront_layouts_draft where vendor_id = p_vendor_id for update;
  if not found then
    raise exception 'no draft for vendor %', p_vendor_id using errcode = 'P0002';
  end if;

  select * into live from public.storefront_layouts where vendor_id = p_vendor_id for update;
  if found then
    insert into public.storefront_layout_history (vendor_id, version, ast, theme, published_at, published_by)
    values (live.vendor_id, live.version, live.ast, live.theme, live.published_at, live.published_by)
    on conflict (vendor_id, version) do nothing;
  end if;

  insert into public.storefront_layouts (vendor_id, version, ast, theme, published_at, published_by)
  values (p_vendor_id, coalesce(live.version, 0) + 1, draft.ast, draft.theme, now(), auth.uid())
  on conflict (vendor_id) do update
    set version = excluded.version,
        ast = excluded.ast,
        theme = excluded.theme,
        published_at = excluded.published_at,
        published_by = excluded.published_by
  returning * into live;

  return live;
end
$$;

-- Discard the draft by resetting it to the live layout.
create or replace function public.reset_storefront_draft(p_vendor_id uuid)
returns public.storefront_layouts_draft
language plpgsql security definer set search_path = public as $$
declare
  out_row public.storefront_layouts_draft;
begin
  if not public.is_vendor_manager(p_vendor_id) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  insert into public.storefront_layouts_draft (vendor_id, ast, theme, updated_by)
  select vendor_id, ast, theme, auth.uid() from public.storefront_layouts where vendor_id = p_vendor_id
  on conflict (vendor_id) do update
    set ast = excluded.ast, theme = excluded.theme, updated_by = excluded.updated_by
  returning * into out_row;
  return out_row;
end
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.storefront_layouts        enable row level security;
alter table public.storefront_layouts_draft  enable row level security;
alter table public.storefront_layout_history enable row level security;

create policy layouts_select_public on public.storefront_layouts
  for select to anon, authenticated
  using (
    exists (select 1 from public.vendors v where v.id = vendor_id and v.is_live)
    or public.is_vendor_member(vendor_id)
  );

create policy draft_member_all on public.storefront_layouts_draft
  for all to authenticated
  using (public.is_vendor_member(vendor_id))
  with check (public.is_vendor_manager(vendor_id));

create policy history_member_select on public.storefront_layout_history
  for select to authenticated using (public.is_vendor_member(vendor_id));

grant select on public.storefront_layouts to anon;
grant select on public.storefront_layouts, public.storefront_layout_history to authenticated;
grant select, insert, update, delete on public.storefront_layouts_draft to authenticated;
grant all on all tables in schema public to service_role;
grant execute on function public.publish_storefront_draft(uuid), public.reset_storefront_draft(uuid) to authenticated;
