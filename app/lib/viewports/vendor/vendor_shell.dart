import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/typography.dart';
import '../widgets/app_scope.dart';

/// Vendor viewport: Dashboard, Design (draft preview), Menu.
class VendorShell extends StatelessWidget {
  const VendorShell({super.key, required this.vendorId, required this.shell});

  final String vendorId;
  final StatefulNavigationShell shell;

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
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
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
