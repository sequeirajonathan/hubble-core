// Renders real screens to PNG so the UI can be reviewed without a device.
//
//   HUBBLE_SCREENSHOTS=1 HUBBLE_FONT_DIR=/path/to/ttfs HUBBLE_SHOT_DIR=/tmp/shots \
//     flutter test test/screenshots
//
// HUBBLE_FONT_DIR must contain BarlowCondensed-{Regular,Bold}.ttf and
// JetBrainsMono-{Medium,SemiBold,Bold}.ttf (download from Google Fonts).
// Skipped in normal runs and in CI.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hubble/core/auth/auth_service.dart';
import 'package:hubble/core/auth/session_controller.dart';
import 'package:hubble/core/models/product.dart';
import 'package:hubble/core/models/vendor.dart';
import 'package:hubble/core/storage/local_cache.dart';
import 'package:hubble/core/theme/hubble_theme.dart';
import 'package:hubble/core/theme/theme_scope.dart';
import 'package:hubble/core/theme/tokens.dart';
import 'package:hubble/core/theme/typography.dart';
import 'package:hubble/interpreter/ast_node.dart';
import 'package:hubble/interpreter/ast_renderer.dart';
import 'package:hubble/interpreter/storefront_data.dart';
import 'package:hubble/viewports/customer/cart/cart_controller.dart';
import 'package:hubble/viewports/customer/cart/carts_screen.dart';
import 'package:hubble/viewports/customer/cart/checkout_screen.dart';
import 'package:hubble/viewports/customer/mailbox/mailbox_screen.dart';
import 'package:hubble/viewports/widgets/app_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _enabled = Platform.environment['HUBBLE_SCREENSHOTS'] == '1';
final _fontDir = Platform.environment['HUBBLE_FONT_DIR'] ?? '';
final _shotDir = Platform.environment['HUBBLE_SHOT_DIR'] ?? 'build/screenshots';

const _taco = Vendor(
  id: 'v1',
  name: 'Taco Bolt',
  slug: 'taco-bolt',
  niche: VendorNiche.foodTruck,
  tagline: 'Al pastor, sparks included',
  addressText: '2200 Navigation Blvd, Houston',
  phone: '+1 713 555 0142',
  hoursText: 'Tue–Sun 11:00–22:00',
  rating: 4.6,
  reviewCount: 812,
);

const _cards = Vendor(
  id: 'v2',
  name: 'Card Forge',
  slug: 'card-forge',
  niche: VendorNiche.cardShop,
  tagline: 'Singles, sealed, and Friday night drafts',
  addressText: '410 Westheimer Rd, Houston',
  rating: 4.9,
  reviewCount: 57,
);

const _tacoProducts = [
  Product(
    id: 'p1',
    vendorId: 'v1',
    name: 'Street Taco (3)',
    description: 'Corn tortillas, onion, cilantro, salsa verde',
    priceCents: 950,
  ),
  Product(
    id: 'p2',
    vendorId: 'v1',
    name: 'Quesabirria',
    description: 'Consommé on the side',
    priceCents: 1400,
  ),
  Product(id: 'p3', vendorId: 'v1', name: 'Horchata', priceCents: 400),
  Product(
    id: 'p4',
    vendorId: 'v1',
    name: 'Elote',
    description: 'Cotija, tajín, lime',
    priceCents: 550,
    isAvailable: false,
  ),
];

const _cardProducts = [
  Product(id: 'c1', vendorId: 'v2', name: 'Booster Box', priceCents: 12999),
  Product(id: 'c2', vendorId: 'v2', name: 'Draft Entry', priceCents: 1500),
  Product(id: 'c3', vendorId: 'v2', name: 'Sleeves (100)', priceCents: 899),
  Product(id: 'c4', vendorId: 'v2', name: 'Playmat', priceCents: 2499),
];

final _tacoLayout = LayoutNode.parse({
  'type': 'screen',
  'children': [
    {
      'type': 'hero',
      'props': {
        'title': {r'$bind': 'vendor.name'},
        'subtitle': {r'$bind': 'vendor.tagline'},
      },
    },
    {
      'type': 'row',
      'props': {'gap': 8},
      'children': [
        {
          'type': 'badge',
          'props': {'label': 'open late'},
        },
        {
          'type': 'badge',
          'props': {'label': 'cash + card', 'tone': 'iron'},
        },
      ],
    },
    {
      'type': 'spacer',
      'props': {'size': 8},
    },
    {
      'type': 'product_list',
      'props': {'title': 'Menu', 'layout': 'list'},
    },
    {
      'type': 'spacer',
      'props': {'size': 8},
    },
    {'type': 'hours'},
    {
      'type': 'spacer',
      'props': {'size': 8},
    },
    {'type': 'map_pin'},
    {
      'type': 'spacer',
      'props': {'size': 16},
    },
    {
      'type': 'button',
      'props': {'label': 'view cart', 'action': 'open_cart'},
    },
  ],
});

final _cardLayout = LayoutNode.parse({
  'type': 'screen',
  'children': [
    {
      'type': 'hero',
      'props': {
        'title': {r'$bind': 'vendor.name'},
        'subtitle': {r'$bind': 'vendor.tagline'},
        'background': {r'$token': 'surface'},
      },
    },
    {
      'type': 'text',
      'props': {
        'text': 'Friday draft · 7pm · 8 seats left',
        'style': 'mono',
        'color': {r'$token': 'accent'},
      },
    },
    {'type': 'divider'},
    {
      'type': 'product_list',
      'props': {'title': 'Shop', 'layout': 'grid'},
    },
    {
      'type': 'spacer',
      'props': {'size': 8},
    },
    {'type': 'map_pin'},
    {
      'type': 'spacer',
      'props': {'size': 16},
    },
    {
      'type': 'button',
      'props': {'label': 'view cart', 'action': 'open_cart', 'variant': 'outline'},
    },
  ],
});

const _cardTheme = {'accent': '#5EB1FF', 'canvas': '#0B1220', 'surface': '#15203A', 'iron': '#33415C'};

Future<void> _loadFont(String family, String file) async {
  final data = File('$_fontDir/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(data.buffer)))).load();
}

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
  await _loadFont(HubbleType.display().fontFamily!, 'BarlowCondensed-Bold.ttf');
  await _loadFont(HubbleType.body().fontFamily!, 'BarlowCondensed-Regular.ttf');
  await _loadFont(HubbleType.mono().fontFamily!, 'JetBrainsMono-Medium.ttf');
  await _loadFont(HubbleType.mono(weight: FontWeight.w600).fontFamily!, 'JetBrainsMono-SemiBold.ttf');
  await _loadFont(HubbleType.mono(weight: FontWeight.w700).fontFamily!, 'JetBrainsMono-Bold.ttf');
}

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(MaterialApp)));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_shotDir).createSync(recursive: true);
    File('$_shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _storefront(
  Vendor vendor,
  List<Product> products,
  LayoutNode layout,
  HubbleTokens tokens,
  int cartCount,
) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildHubbleTheme(tokens),
  home: ThemeInjector(
    controller: VendorThemeController(tokens),
    child: Scaffold(
      appBar: AppBar(
        title: Text(vendor.name.toUpperCase()),
        leading: const Icon(Icons.arrow_back),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge.count(count: cartCount, child: const Icon(Icons.shopping_basket_outlined)),
          ),
        ],
      ),
      body: LayoutRenderer(
        root: layout,
        data: StorefrontData(vendor: vendor, products: products),
        tokens: tokens,
        onAction: (_) {},
        onAddToCart: (_) {},
      ),
    ),
  ),
);

void main() {
  if (!_enabled) {
    test('screenshots are opt-in (HUBBLE_SCREENSHOTS=1)', () {});
    return;
  }

  late AppServices services;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    final db = SupabaseClient('http://127.0.0.1:1', 'offline');
    final cache = LocalCache(await SharedPreferences.getInstance());
    final carts = CartController()
      ..add(_tacoProducts[0], vendorId: 'v1', vendorName: 'Taco Bolt', quantity: 2)
      ..add(_tacoProducts[2], vendorId: 'v1', vendorName: 'Taco Bolt')
      ..add(_cardProducts[1], vendorId: 'v2', vendorName: 'Card Forge');
    services = AppServices(
      db: db,
      session: SessionController(auth: AuthService(db.auth), db: db, cache: cache),
      cache: cache,
      theme: VendorThemeController(),
      carts: carts,
    );
  });

  Widget host(Widget child) => AppScope(
    services: services,
    child: ThemeInjector(
      controller: services.theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildHubbleTheme(HubbleTokens.host),
        home: child,
      ),
    ),
  );

  testWidgets('screens', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);

    await tester.pumpWidget(_storefront(_taco, _tacoProducts, _tacoLayout, HubbleTokens.host, 3));
    await _snap(tester, '01_storefront_taco_bolt');

    final cardTokens = HubbleTokens.host.merge(_cardTheme);
    await tester.pumpWidget(_storefront(_cards, _cardProducts, _cardLayout, cardTokens, 1));
    await _snap(tester, '02_storefront_card_forge_reskinned');

    await tester.pumpWidget(host(const CartsScreen()));
    await _snap(tester, '03_carts_per_vendor');

    await tester.pumpWidget(host(const CheckoutScreen(vendorId: 'v1')));
    await _snap(tester, '04_checkout_single_store');

    await tester.pumpWidget(host(const MailboxScreen()));
    await _snap(tester, '05_mailbox_signed_out');
  });
}
