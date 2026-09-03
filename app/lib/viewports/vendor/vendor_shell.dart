import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/typography.dart';
import '../widgets/app_scope.dart';

/// Vendor viewport chrome: Dashboard, Design (draft preview), Menu.
///
/// Unlike the customer shell, this cannot be a `StatefulShellRoute`: every
/// vendor route carries a `:vendorId` path parameter, and go_router requires
/// a `StatefulShellBranch`'s default route to have none (it needs a
/// parameterless fallback location to cold-start a branch by index). So the
/// three vendor screens are plain sibling routes that each wrap themselves in
/// this shell and pass their own tab index.
class VendorShell extends StatelessWidget {
  const VendorShell({super.key, required this.vendorId, required this.currentIndex, required this.child});

  final String vendorId;
  final int currentIndex;
  final Widget child;

  void _onDestinationSelected(BuildContext context, int index) {
    if (index == currentIndex) return;
    switch (index) {
      case 0:
        context.go('/vendor/$vendorId');
      case 1:
        context.go('/vendor/$vendorId/design');
      case 2:
        context.go('/vendor/$vendorId/menu');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = ThemeInjector.tokensOf(context);
    return ListenableBuilder(
      listenable: scope.session,
      builder: (context, _) {
        final membership = scope.session.memberships.where((m) => m.vendor.id == vendorId).firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text((membership?.vendor.name ?? 'VENDOR HUB').toUpperCase()),
            actions: [
              if (scope.session.memberships.length > 1)
                PopupMenuButton<String>(
                  tooltip: 'Switch storefront',
                  icon: const Icon(Icons.swap_horiz),
                  onSelected: (id) => context.go('/vendor/$id'),
                  itemBuilder: (context) => [
                    for (final m in scope.session.memberships)
                      PopupMenuItem(value: m.vendor.id, child: Text(m.vendor.name)),
                  ],
                ),
              TextButton(
                onPressed: () async {
                  await scope.session.setMode(ViewportMode.shopper);
                  if (context.mounted) context.go('/');
                },
                child: Text(
                  'SHOP',
                  style: HubbleType.mono(size: 12, color: t.accent, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (i) => _onDestinationSelected(context, i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'DASHBOARD',
              ),
              NavigationDestination(
                icon: Icon(Icons.brush_outlined),
                selectedIcon: Icon(Icons.brush),
                label: 'DESIGN',
              ),
              NavigationDestination(
                icon: Icon(Icons.restaurant_menu_outlined),
                selectedIcon: Icon(Icons.restaurant_menu),
                label: 'MENU',
              ),
            ],
          ),
        );
      },
    );
  }
}
