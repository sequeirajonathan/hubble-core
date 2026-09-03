import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_router.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/session_controller.dart';
import 'core/network/supabase_client.dart';
import 'core/storage/local_cache.dart';
import 'core/theme/hubble_theme.dart';
import 'core/theme/theme_scope.dart';
import 'viewports/customer/cart/cart_controller.dart';
import 'viewports/widgets/app_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship with the bundle; never fetch at runtime on a shopper's data plan.
  GoogleFonts.config.allowRuntimeFetching = false;

  await HubbleBackend.initialize();
  final cache = await LocalCache.open();
  final session = SessionController(
    auth: AuthService(HubbleBackend.auth),
    db: HubbleBackend.db,
    cache: cache,
  );
  final carts = CartController.fromJson(cache.readCarts());
  carts.addListener(() => cache.writeCarts(carts.toJson()));

  runApp(
    HubbleApp(
      services: AppServices(
        db: HubbleBackend.db,
        session: session,
        cache: cache,
        theme: VendorThemeController(),
        carts: carts,
      ),
    ),
  );
}

class HubbleApp extends StatefulWidget {
  const HubbleApp({super.key, required this.services});

  final AppServices services;

  @override
  State<HubbleApp> createState() => _HubbleAppState();
}

class _HubbleAppState extends State<HubbleApp> {
  late final router = buildRouter(widget.services.session);

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: ThemeInjector(
      controller: widget.services.theme,
      child: ListenableBuilder(
        listenable: widget.services.theme,
        builder: (context, _) => MaterialApp.router(
          title: 'Hubble',
          debugShowCheckedModeBanner: false,
          theme: buildHubbleTheme(widget.services.theme.tokens),
          routerConfig: router,
        ),
      ),
    ),
  );
}
