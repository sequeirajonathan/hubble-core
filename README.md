# Hubble

One download, every local storefront. Hubble is a multi-tenant marketplace
where food trucks, card shops and neighborhood startups deploy re-skinned,
near-native storefronts inside a single host app. The full product spec lives
in [`docs/PRD.md`](docs/PRD.md).

```
hubble-core/
├── .github/workflows/   CI, TestFlight, Play Internal, Supabase deploy
├── app/                 Flutter host application
└── backend/             Supabase schema + edge functions
```

## How the pieces fit

| Requirement | Where it lives |
| --- | --- |
| Single sign-on (magic link / phone OTP, one JWT for shopper + vendor) | `app/lib/core/auth`, `profiles` + `vendor_members` in `backend/migrations/0001_identity.sql` |
| AST rendering core (JSON layout → native widgets, no web view) | `app/lib/interpreter`, schema in `backend/supabase/functions/_shared/ast.ts`, DB check `layout_ast_is_valid()` |
| Theme injection (vendor token overrides re-skin the host) | `app/lib/core/theme/theme_scope.dart`, `theme_tokens_are_valid()` |
| Sandbox isolation (draft vs live layouts, in-app preview) | `storefront_layouts_draft`, `publish_storefront_draft()`, `app/lib/viewports/vendor/design_preview_screen.dart` |
| Single-store checkout boundary (carts keyed by vendor) | `app/lib/viewports/customer/cart/cart_controller.dart`, `carts` unique `(customer_id, vendor_id)`, `cart_items_vendor_boundary` trigger, `stripe-split` |
| Anti-spam in-app mailbox + opt-out matrix | `user_inapp_mailbox`, `user_niche_preferences`, `campaign_targeting_queue`, `fan_out_campaign()` |
| Review cache aggregator (24 h TTL, weighted average) | `review-sync` function, `vendor_review_cache`, `vendor_ratings` view |
| AI layout transformations | `ai-generator` function (layout architect + brand stylist + deterministic reviewer) |

## Local development

### Backend

```bash
# Postgres 16 running locally (or `supabase start` inside backend/)
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=hubble
bash backend/scripts/apply_migrations.sh   # applies the auth shim + migrations
bash backend/scripts/run_sql_tests.sh      # behavioural tests, rolled back

cd backend/supabase/functions
deno task check && deno task test          # type-check + unit tests
supabase functions serve --env-file .env   # run the functions locally
```

`backend/supabase/migrations` is a symlink to `backend/migrations` so the
Supabase CLI and the plain-psql scripts read the same files.

Function secrets: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
`GOOGLE_PLACES_API_KEY`, `YELP_API_KEY`, `ANTHROPIC_API_KEY`,
`HUBBLE_PLATFORM_FEE_BPS` (default 500 = 5 %).

### App

```bash
cd app
flutter pub get
flutter run --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
            --dart-define=SUPABASE_ANON_KEY=<anon key>
flutter analyze && flutter test
```

The app icon source is `app/assets/icon/hubble_icon.svg`; run
`app/tool/render_icon.sh` to regenerate platform icons.

## Pipelines

* `ci.yml`: Flutter analyze/test, Deno fmt/lint/check/test, migrations applied
  to a throwaway Postgres followed by the SQL behavioural tests.
* `supabase-deploy.yml`: on merge to `main`, `supabase db push` and redeploy of
  every function directory, then secret sync.
* `ios-distribution.yml` / `android-distribution.yml`: Fastlane lanes
  (`ios beta`, `android internal`) upload to TestFlight and the Play Internal
  track. Signing is via `match` (iOS) and an upload keystore (Android) provided
  as repository secrets; see the workflow files for the exact names.

## Storefront layout contract

A layout is a JSON tree whose root is a `screen`. Containers (`screen`,
`column`, `row`, `stack`) hold children; leaves (`text`, `image`, `hero`,
`badge`, `button`, `product_list`, `product_card`, `hours`, `map_pin`,
`contact`, `spacer`, `divider`) do not. Props may reference runtime data with
`{"$bind": "vendor.logo_url"}` or theme tokens with `{"$token": "accent"}`.
Unknown node types, unknown binds, non-https URLs, nesting deeper than 24 and
more than 200 siblings are rejected by the database, the edge functions and
the interpreter alike.
