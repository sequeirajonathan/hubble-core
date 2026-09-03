import 'package:flutter/material.dart';

import 'hubble_theme.dart';
import 'tokens.dart';

/// Mutable token state. Tapping a merchant row calls [applyVendor]; leaving
/// the storefront calls [reset]. Every widget under a [ThemeInjector]
/// rebuilds with the new token set.
class VendorThemeController extends ChangeNotifier {
  VendorThemeController([HubbleTokens initial = HubbleTokens.host]) : _tokens = initial;

  HubbleTokens _tokens;
  String? _vendorId;

  HubbleTokens get tokens => _tokens;
  String? get vendorId => _vendorId;
  bool get isHost => _vendorId == null;

  void applyVendor(String vendorId, Map<String, dynamic>? overrides) {
    final next = HubbleTokens.host.merge(overrides);
    if (_vendorId == vendorId && next == _tokens) return;
    _vendorId = vendorId;
    _tokens = next;
    notifyListeners();
  }

  void applyTokens(HubbleTokens tokens, {String? vendorId}) {
    if (tokens == _tokens && vendorId == _vendorId) return;
    _tokens = tokens;
    _vendorId = vendorId;
    notifyListeners();
  }

  void reset() {
    if (_vendorId == null && _tokens == HubbleTokens.host) return;
    _vendorId = null;
    _tokens = HubbleTokens.host;
    notifyListeners();
  }
}

/// Parent container that listens to token state and re-skins its subtree.
class ThemeInjector extends InheritedNotifier<VendorThemeController> {
  const ThemeInjector({super.key, required VendorThemeController controller, required super.child})
    : super(notifier: controller);

  static VendorThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeInjector>();
    assert(scope != null, 'ThemeInjector missing above this widget');
    return scope!.notifier!;
  }

  static VendorThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeInjector>()?.notifier;

  static HubbleTokens tokensOf(BuildContext context) => maybeOf(context)?.tokens ?? HubbleTokens.host;
}

/// Wraps [child] in a Material [Theme] derived from the injected tokens, so a
/// storefront subtree (or a vendor's draft preview) is fully re-skinned.
class TokenTheme extends StatelessWidget {
  const TokenTheme({super.key, required this.tokens, required this.child});

  final HubbleTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(data: buildHubbleTheme(tokens), child: child);
}
