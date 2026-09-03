import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/product.dart';
import '../../../core/theme/theme_scope.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../widgets/app_scope.dart';
import '../../widgets/empty_state.dart';
import 'cart_controller.dart';
import 'cart_sync.dart';

/// Single-store checkout: this screen only ever knows about one vendor cart.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _note = TextEditingController();
  bool _busy = false;
  CheckoutResult? _result;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pay(VendorCart cart) async {
    final scope = AppScope.of(context);
    if (!scope.session.isSignedIn) {
      unawaited(context.push('/sign-in'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await scope.checkout.checkout(cart, note: _note.text);
      scope.carts.clear(cart.vendorId);
      if (mounted) setState(() => _result = result);
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = ThemeInjector.tokensOf(context);
    final result = _result;
    if (result != null) return _Confirmation(result: result, tokens: t);

    return ListenableBuilder(
      listenable: scope.carts,
      builder: (context, _) {
        final cart = scope.carts.cartFor(widget.vendorId);
        if (cart == null || cart.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('CHECKOUT')),
            body: const EmptyState(
              icon: Icons.remove_shopping_cart_outlined,
              title: 'CART IS EMPTY',
              body: '',
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(cart.vendorName.toUpperCase())),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final line in cart.lines)
                _LineRow(cart: cart, line: line, tokens: t, controller: scope.carts),
              const Divider(height: 32),
              _TotalsRow(
                label: 'SUBTOTAL',
                value: formatCents(cart.subtotalCents, currency: cart.currency),
                tokens: t,
              ),
              const SizedBox(height: 4),
              Text(
                'Taxes and any platform fee are settled in the payment step. One charge, one store, one reference on your statement.',
                style: HubbleType.mono(size: 11, color: t.iron),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _note,
                maxLength: 280,
                decoration: const InputDecoration(labelText: 'NOTE FOR THE VENDOR (OPTIONAL)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: HubbleType.mono(size: 12, color: t.alert)),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _pay(cart),
                icon: _busy
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt),
                label: Text('PAY ${formatCents(cart.subtotalCents, currency: cart.currency)}'),
              ),
              TextButton(
                onPressed: _busy ? null : () => scope.carts.clear(cart.vendorId),
                child: Text('EMPTY THIS CART', style: HubbleType.mono(size: 12, color: t.alert)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.cart, required this.line, required this.tokens, required this.controller});

  final VendorCart cart;
  final CartLine line;
  final HubbleTokens tokens;
  final CartController controller;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final mods = line.product.modifiers
        .where((m) => line.modifierIds.contains(m.id))
        .map((m) => m.name)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name, style: HubbleType.display(size: 16, color: t.onCanvas)),
                if (mods.isNotEmpty) Text(mods, style: HubbleType.mono(size: 11, color: t.iron)),
                Text(
                  '${formatCents(line.unitPriceCents, currency: line.product.currency)} × ${line.quantity}',
                  style: HubbleType.mono(size: 12, color: t.onCanvas),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => controller.setQuantity(cart.vendorId, line.key, line.quantity - 1),
            icon: Icon(Icons.remove_circle_outline, color: t.iron),
          ),
          Text('${line.quantity}', style: HubbleType.mono(size: 14, color: t.onCanvas)),
          IconButton(
            onPressed: () => controller.setQuantity(cart.vendorId, line.key, line.quantity + 1),
            icon: Icon(Icons.add_circle_outline, color: t.accent),
          ),
          SizedBox(
            width: 72,
            child: Text(
              formatCents(line.lineTotalCents, currency: line.product.currency),
              textAlign: TextAlign.end,
              style: HubbleType.mono(size: 13, color: t.accent, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.value, required this.tokens});

  final String label;
  final String value;
  final HubbleTokens tokens;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: HubbleType.mono(size: 13, color: tokens.iron, weight: FontWeight.w700),
      ),
      Text(
        value,
        style: HubbleType.mono(size: 16, color: tokens.onCanvas, weight: FontWeight.w700),
      ),
    ],
  );
}

/// The PaymentIntent has been created for this one vendor. The client secret
/// is what a Stripe payment sheet needs; until that dependency is wired in,
/// it can be copied for testing against the Stripe CLI.
class _Confirmation extends StatelessWidget {
  const _Confirmation({required this.result, required this.tokens});

  final CheckoutResult result;
  final HubbleTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final order = result.order;
    return Scaffold(
      appBar: AppBar(title: const Text('ORDER CREATED')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: t.accent),
            const SizedBox(height: 16),
            Text(
              order.referenceCode,
              textAlign: TextAlign.center,
              style: HubbleType.display(size: 34, color: t.onCanvas),
            ),
            Text(
              '${order.vendorName ?? ''} · ${formatCents(order.totalCents, currency: order.currency)}',
              textAlign: TextAlign.center,
              style: HubbleType.mono(size: 14, color: t.accent),
            ),
            const SizedBox(height: 24),
            Text(
              'Payment is collected for this store only. Your bank statement will show the reference above.',
              textAlign: TextAlign.center,
              style: HubbleType.body(size: 14, color: t.onCanvas),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: result.clientSecret));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Client secret copied')));
                }
              },
              icon: const Icon(Icons.key),
              label: const Text('COPY PAYMENT CLIENT SECRET'),
            ),
            const Spacer(),
            FilledButton(onPressed: () => context.go('/'), child: const Text('BACK TO DISCOVER')),
          ],
        ),
      ),
    );
  }
}
