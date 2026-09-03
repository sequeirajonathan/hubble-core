import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/session_controller.dart';
import '../../core/storage/local_cache.dart';
import '../../core/theme/theme_scope.dart';
import '../../interpreter/layout_repository.dart';
import '../customer/cart/cart_controller.dart';
import '../customer/cart/cart_sync.dart';

/// Composition root exposed to the widget tree. Plain InheritedWidget: no
/// DI framework, no code generation.
class AppServices {
  AppServices({
    required this.db,
    required this.session,
    required this.cache,
    required this.theme,
    required this.carts,
  }) : layouts = LayoutRepository(db, cache: cache),
       checkout = CheckoutService(db);

  final SupabaseClient db;
  final SessionController session;
  final LocalCache cache;
  final VendorThemeController theme;
  final CartController carts;
  final LayoutRepository layouts;
  final CheckoutService checkout;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}
