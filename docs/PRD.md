# Hubble — Technical Specification & Product Requirements Document

## 1. Project Overview & Identity Core

* **App Name**: Hubble
* **Mission**: A single-download, anti-corporate, multi-tenant marketplace platform connecting local vendors (food trucks, card shops, startups) directly with neighboring consumers. It eliminates app fatigue by allowing vendors to instantly deploy uniquely re-skinned, near-native digital storefronts inside a single host application.
* **Target Audience**: Local merchants seeking high publishing velocity without technical overhead, and community consumers looking for streamlined local purchasing options.
* **Engineering Persona**: High-performance, single-developer, zero-overhead deployment architecture utilizing automated code pipelines.

## 2. Design System: The Industrial Bolt Theme

The visual ecosystem rejects generic corporate tech minimalism and soft organic styles. It implements a utilitarian, hardworking aesthetic that emphasizes structural integrity and professional reliability.

### A. Digital Color Matrix (Tokens)

| Token | Hex | Role |
| --- | --- | --- |
| Scaffold Canvas | `#1A1A1A` | Flat, premium matte black foundation layer. Optimizes OLED battery use and minimizes outdoor glare. |
| Container Surface | `#222222` | Deep obsidian layer framing individual vendor card sections. |
| Primary Active Accent (Safety Amber) | `#FF7A00` | Reserved for system actions, selection rings, primary checkout links, status highlights. |
| Secondary Text/Borders (Dark Iron) | `#4A4A4A` | Non-essential labels, outline borders, inactive slider dividers. |
| Semantic Alert (Alert Red) | `#FF3B30` | Dangerous actions, failed transaction states, sold-out notifications. |

Implementation: `app/lib/core/theme/tokens.dart` (Dart) and `backend/supabase/functions/_shared/tokens.ts` (edge functions). Vendors may override a whitelisted subset of tokens (see `vendor_theme` in `backend/migrations/0002_storefronts.sql`).

### B. App Icon Specifications

* **Visual Structure**: An interlocking, isometric graphic forming a thick, structural letter **H**, engineered with clean mechanical angles to resemble an integrated hardware bracket or industrial bolt.
* **Composition**: Centered over a dark slate-charcoal tile base. Thick line profile for instant recognition at small home-screen footprints.
* **Colorway**: Matte charcoal backdrop supporting a high-contrast safety-amber emblem body.

Source asset: `app/assets/icon/hubble_icon.svg`. Rasterize with `app/tool/render_icon.sh` before running `flutter_launcher_icons`.

### C. System Typography Matrix

* **Display Headers**: Heavy industrial geometric families (*SF Pro Display Bold* / *Roboto Condensed Bold* class). The app bundles *Barlow Condensed Bold* via `google_fonts`, which no longer ships Roboto Condensed as a separate family; the platform fallback is SF Pro Display / Roboto.
* **Functional Body Content**: High-readability monospace (*JetBrains Mono* / *Roboto Mono*) for product specifications and numerical text (prices, modifier lists, tracking indexes).

## 3. MVP Core Requirements

### A. Single-Sign-On Unified Authentication

* Centralized identity provider (Supabase Auth) managing a global `profiles` table.
* Users sign up once via email magic link or phone OTP. The resulting JWT allows switching from the shopper profile to the vendor creation hub instantly without re-authenticating. Role is derived, not stored: a user with one or more rows in `vendor_members` may enter the vendor viewport.

### B. Abstract Syntax Tree (AST) Dynamic Rendering Core

* The mobile layout template does not parse JavaScript or run web views. It evaluates a lightweight JSON structural layout tree downloaded from the database at runtime (`storefront_layouts.ast`).
* **Theme Injection**: Parent view containers listen to token state. Tapping a merchant row fetches their token overrides and logo, immediately re-skinning headers, status boundaries, and card buttons.
* **Sandbox Isolation Layout**: Vendor edits write to `storefront_layouts_draft`. The vendor viewport runs an internal preview screen reading directly from the draft, so merchants preview style alterations before calling `publish_storefront_draft()`.

The AST schema is defined once in `backend/supabase/functions/_shared/ast.ts` and mirrored in `app/lib/interpreter/ast_node.dart`. Both sides validate the same node set and reject unknown node types.

### C. Single-Store Checkout Boundary Engine

* No global cross-store master cart. Items are grouped into individual carts keyed by `vendor_id` (`carts` has a unique `(customer_id, vendor_id)` constraint; `cart_items` enforce that the product belongs to the cart's vendor via trigger).
* Customers process purchases one store at a time. Each checkout creates exactly one Stripe PaymentIntent for exactly one vendor (`stripe-split` edge function), routed to that vendor's connected account with the platform fee taken as `application_fee_amount`.

### D. Anti-Spam Internal Communication Box

* No external email routing for promotional deals. Offers, neighborhood notices, and discount codes distribute exclusively to `user_inapp_mailbox`.
* **Opt-Out Matrix**: `user_niche_preferences` holds one row per (user, niche). Setting `opted_in = false` removes the user from the `campaign_targeting_queue` view instantly; `fan_out_campaign()` reads the queue at send time.

### E. Abstracted Review Cache Aggregator

* An asynchronous background system (`review-sync` edge function, scheduled via `pg_cron`/GitHub schedule) loads existing merchant profiles from external review directories (Google Places, Yelp Fusion).
* Pay-per-use tasks read external scores, compute a count-weighted absolute internal average, and cache the records in `vendor_review_cache` with a 24-hour `expires_at`. The `vendor_ratings` view exposes only unexpired rows.

## 4. GitHub Architecture & Project Organization

```
hubble-core/
├── .github/workflows/
│   ├── ci.yml                    # analyze + test (Flutter, Deno, SQL migrations)
│   ├── ios-distribution.yml      # Fastlane -> TestFlight
│   ├── android-distribution.yml  # Fastlane -> Play Internal Track
│   └── supabase-deploy.yml       # migrations + edge functions -> production
├── app/                          # Flutter host application
│   ├── lib/
│   │   ├── core/                 # auth, network, storage, theme tokens
│   │   ├── interpreter/          # AST parser, renderer, token binder
│   │   ├── viewports/customer/   # discover, storefront, mailbox, checkout
│   │   ├── viewports/vendor/     # dashboard, preview, menu management
│   │   └── main.dart             # role-based entrance router
│   ├── fastlane/
│   └── pubspec.yaml
└── backend/
    ├── migrations/               # sequential SQL migrations (source of truth)
    └── supabase/
        ├── config.toml
        ├── migrations -> ../migrations   (symlink consumed by the Supabase CLI)
        └── functions/
            ├── _shared/          # AST schema, tokens, auth + response helpers
            ├── stripe-split/     # single-vendor PaymentIntent + webhook
            ├── review-sync/      # Google / Yelp ingestion + 24h cache
            └── ai-generator/     # Claude-driven draft layout transformations
```

### Automated Pipeline Configuration (CI/CD)

* **Database Version Control**: Sequential SQL migrations in `backend/migrations`. `supabase-deploy.yml` pushes them with `supabase db push` and deploys every function directory on merge to `main`.
* **Compilation Tasks**: Merges to `main` trigger isolated runners. Mobile lanes use **Fastlane** with match-managed signing to upload bundles to **Apple TestFlight** and the **Google Play Internal Track**.
