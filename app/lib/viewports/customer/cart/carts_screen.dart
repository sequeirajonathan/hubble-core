import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/product.dart';
import '../../../core/theme/theme_scope.dart';
import '../../../core/theme/typography.dart';
import '../../widgets/app_scope.dart';
import '../../widgets/empty_state.dart';

/// One card per vendor. Nothing here ever sums across vendors.
class CartsScreen extends StatelessWidget {
  const CartsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final carts = AppScope.of(context).carts;
    final t = ThemeInjector.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('CARTS')),
      body: ListenableBuilder(
        listenable: carts,
        builder: (context, _) {
          final list = carts.carts;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.shopping_basket_outlined,
              title: 'NO CARTS YET',
              body: 'Each store gets its own cart. Add something from a storefront to start one.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final cart = list[i];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    cart.vendorName.toUpperCase(),
                    style: HubbleType.display(size: 18, color: t.onCanvas),
                  ),
                  subtitle: Text(
                    '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'} · ${formatCents(cart.subtotalCents, currency: cart.currency)}',
                    style: HubbleType.mono(size: 13, color: t.accent),
                  ),
                  trailing: Icon(Icons.chevron_right, color: t.iron),
                  onTap: () => context.push('/cart/${cart.vendorId}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
