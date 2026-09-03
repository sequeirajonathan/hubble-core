import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/product.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../interpreter/ast_node.dart';
import '../../interpreter/ast_renderer.dart';
import '../../interpreter/layout_repository.dart';
import '../widgets/app_scope.dart';
import '../widgets/empty_state.dart';

/// Renders one vendor's live storefront from its AST. The whole subtree is
/// re-themed with the vendor's tokens; leaving the screen restores the host.
class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  late Future<StorefrontBundle> _future;
  StorefrontLayout? _cached;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cached ??= AppScope.of(context).layouts.cachedLive(widget.vendorId);
  }

  Future<StorefrontBundle> _load() async {
    final scope = AppScope.of(context);
    final bundle = await scope.layouts.loadStorefront(widget.vendorId);
    scope.theme.applyVendor(widget.vendorId, bundle.layout.theme);
    return bundle;
  }

  @override
  void dispose() {
    // Leaving the storefront returns the host chrome to Industrial Bolt.
    ThemeInjector.maybeOf(context)?.reset();
    super.dispose();
  }

  Future<void> _handleAction(LayoutAction action, StorefrontBundle bundle) async {
    final v = bundle.data.vendor;
    switch (action.name) {
      case 'open_cart':
        if (mounted) unawaited(context.push('/cart/${widget.vendorId}'));
      case 'call':
        final phone = v.phone;
        if (phone != null) await launchUrl(Uri(scheme: 'tel', path: phone));
      case 'directions':
        final q = v.hasLocation ? '${v.lat},${v.lng}' : (v.addressText ?? v.name);
        await launchUrl(
          Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': q}),
          mode: LaunchMode.externalApplication,
        );
      case 'open_url':
        final url = action.url;
        if (url != null && url.startsWith('https://')) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      default:
        break;
    }
  }

  void _addToCart(Product product, StorefrontBundle bundle) {
    final scope = AppScope.of(context);
    scope.carts.add(product, vendorId: widget.vendorId, vendorName: bundle.data.vendor.name);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.name} added to ${bundle.data.vendor.name} cart'),
          action: SnackBarAction(label: 'VIEW', onPressed: () => context.push('/cart/${widget.vendorId}')),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.theme,
      builder: (context, _) {
        final tokens = scope.theme.vendorId == widget.vendorId
            ? scope.theme.tokens
            : ThemeInjector.tokensOf(context);
        return TokenTheme(
          tokens: tokens,
          child: FutureBuilder<StorefrontBundle>(
            future: _future,
            builder: (context, snap) {
              final bundle = snap.data;
              return Scaffold(
                appBar: AppBar(
                  title: Text((bundle?.data.vendor.name ?? 'LOADING').toUpperCase()),
                  actions: [
                    ListenableBuilder(
                      listenable: scope.carts,
                      builder: (context, _) {
                        final count = scope.carts.itemCountFor(widget.vendorId);
                        return IconButton(
                          tooltip: 'This store\'s cart',
                          onPressed: () => context.push('/cart/${widget.vendorId}'),
                          icon: Badge.count(
                            count: count,
                            isLabelVisible: count > 0,
                            child: const Icon(Icons.shopping_basket_outlined),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                body: _body(snap, tokens),
              );
            },
          ),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<StorefrontBundle> snap, HubbleTokens tokens) {
    if (snap.hasError) {
      final err = snap.error;
      return ErrorCard(
        message: err is LayoutValidationException
            ? 'This storefront has an invalid layout (${err.path}: ${err.message}).'
            : err.toString(),
        onRetry: () => setState(() => _future = _load()),
      );
    }
    final bundle = snap.data;
    if (bundle == null) {
      return Column(
        children: [
          const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Center(
              child: Text(
                _cached != null ? 'REFRESHING LAYOUT v${_cached!.version}' : 'LOADING',
                style: HubbleType.mono(size: 12, color: tokens.iron),
              ),
            ),
          ),
        ],
      );
    }
    return LayoutRenderer(
      root: bundle.layout.root,
      data: bundle.data,
      tokens: tokens,
      onAction: (action) => _handleAction(action, bundle),
      onAddToCart: (product) => _addToCart(product, bundle),
      onProductTap: (product) => _addToCart(product, bundle),
    );
  }
}
