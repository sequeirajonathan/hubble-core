import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_scope.dart';

/// Shopper viewport: Discover, Carts, Mailbox, Profile.
class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final carts = AppScope.of(context).carts;
    return Scaffold(
      body: shell,
      bottomNavigationBar: ListenableBuilder(
        listenable: carts,
        builder: (context, _) => NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'DISCOVER',
            ),
            NavigationDestination(
              icon: Badge.count(
                count: carts.vendorCount,
                isLabelVisible: carts.vendorCount > 0,
                child: const Icon(Icons.shopping_basket_outlined),
              ),
              selectedIcon: const Icon(Icons.shopping_basket),
              label: 'CARTS',
            ),
            const NavigationDestination(
              icon: Icon(Icons.mail_outline),
              selectedIcon: Icon(Icons.mail),
              label: 'MAILBOX',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'PROFILE',
            ),
          ],
        ),
      ),
    );
  }
}
