import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/session_controller.dart';
import 'viewports/auth/sign_in_screen.dart';
import 'viewports/customer/cart/carts_screen.dart';
import 'viewports/customer/cart/checkout_screen.dart';
import 'viewports/customer/customer_shell.dart';
import 'viewports/customer/discover_screen.dart';
import 'viewports/customer/mailbox/mailbox_screen.dart';
import 'viewports/customer/mailbox/preferences_screen.dart';
import 'viewports/customer/profile_screen.dart';
import 'viewports/customer/storefront_screen.dart';
import 'viewports/vendor/create_vendor_screen.dart';
import 'viewports/vendor/dashboard_screen.dart';
import 'viewports/vendor/design_preview_screen.dart';
import 'viewports/vendor/menu_management_screen.dart';
import 'viewports/vendor/vendor_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Role-based system entrance router.
///
/// Routes are split into the shopper shell (`/`) and the vendor shell
/// (`/vendor/:id`). Vendor routes require a signed-in user with a membership
/// for that vendor; everything else is open, with sign-in requested at the
/// point of action (checkout, mailbox, vendor creation).
GoRouter buildRouter(SessionController session) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  refreshListenable: session,
  redirect: (context, state) {
    final path = state.uri.path;
    final vendorMatch = RegExp(r'^/vendor/([^/]+)').firstMatch(path);
    if (vendorMatch != null) {
      final id = vendorMatch.group(1)!;
      if (id == 'new') return session.isSignedIn ? null : '/sign-in';
      if (!session.isSignedIn) return '/sign-in';
      if (session.loading) return null;
      if (!session.memberships.any((m) => m.vendor.id == id)) return '/';
      return null;
    }
    if (path == '/sign-in' && session.isSignedIn) return '/';
    if (path == '/' && session.mode == ViewportMode.vendor && session.memberships.isNotEmpty) {
      return '/vendor/${session.memberships.first.vendor.id}';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
    GoRoute(
      path: '/store/:vendorId',
      parentNavigatorKey: _rootKey,
      builder: (_, state) => StorefrontScreen(vendorId: state.pathParameters['vendorId']!),
    ),
    GoRoute(
      path: '/cart/:vendorId',
      parentNavigatorKey: _rootKey,
      builder: (_, state) => CheckoutScreen(vendorId: state.pathParameters['vendorId']!),
    ),
    GoRoute(
      path: '/mailbox/preferences',
      parentNavigatorKey: _rootKey,
      builder: (_, _) => const PreferencesScreen(),
    ),
    GoRoute(path: '/vendor/new', parentNavigatorKey: _rootKey, builder: (_, _) => const CreateVendorScreen()),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => CustomerShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (_, _) => const DiscoverScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/carts', builder: (_, _) => const CartsScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/mailbox', builder: (_, _) => const MailboxScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())],
        ),
      ],
    ),
    GoRoute(
      path: '/vendor/:vendorId',
      parentNavigatorKey: _rootKey,
      builder: (_, state) {
        final id = state.pathParameters['vendorId']!;
        return VendorShell(
          vendorId: id,
          currentIndex: 0,
          child: DashboardScreen(vendorId: id),
        );
      },
    ),
    GoRoute(
      path: '/vendor/:vendorId/design',
      parentNavigatorKey: _rootKey,
      builder: (_, state) {
        final id = state.pathParameters['vendorId']!;
        return VendorShell(
          vendorId: id,
          currentIndex: 1,
          child: DesignPreviewScreen(vendorId: id),
        );
      },
    ),
    GoRoute(
      path: '/vendor/:vendorId/menu',
      parentNavigatorKey: _rootKey,
      builder: (_, state) {
        final id = state.pathParameters['vendorId']!;
        return VendorShell(
          vendorId: id,
          currentIndex: 2,
          child: MenuManagementScreen(vendorId: id),
        );
      },
    ),
  ],
);
