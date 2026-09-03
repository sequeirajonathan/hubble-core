import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hubble/core/models/product.dart';
import 'package:hubble/core/models/vendor.dart';
import 'package:hubble/core/theme/theme_scope.dart';
import 'package:hubble/core/theme/tokens.dart';
import 'package:hubble/interpreter/ast_node.dart';
import 'package:hubble/interpreter/ast_renderer.dart';
import 'package:hubble/interpreter/storefront_data.dart';

const _vendor = Vendor(
  id: 'v1',
  name: 'Taco Bolt',
  slug: 'taco-bolt',
  niche: VendorNiche.foodTruck,
  tagline: 'Sparks fly',
  addressText: '100 Main St',
  phone: '+15550100',
  rating: 4.5,
  reviewCount: 200,
);

const _products = [
  Product(id: 'p1', vendorId: 'v1', name: 'Street Taco', priceCents: 350),
  Product(id: 'p2', vendorId: 'v1', name: 'Horchata', priceCents: 400),
  Product(id: 'p3', vendorId: 'v1', name: 'Sold Thing', priceCents: 100, isAvailable: false),
];

Widget _host(Widget child, {HubbleTokens tokens = HubbleTokens.host}) => MaterialApp(
  home: ThemeInjector(
    controller: VendorThemeController(tokens),
    child: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final root = LayoutNode.parse({
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
        'type': 'badge',
        'props': {'label': 'open late', 'tone': 'accent'},
      },
      {
        'type': 'product_list',
        'props': {'title': 'Menu', 'layout': 'list'},
      },
      {
        'type': 'button',
        'props': {'label': 'View cart', 'action': 'open_cart'},
      },
      {'type': 'map_pin'},
    ],
  });

  testWidgets('renders bound vendor data, products and actions', (tester) async {
    final actions = <LayoutAction>[];
    final added = <Product>[];
    await tester.pumpWidget(
      _host(
        LayoutRenderer(
          root: root,
          data: const StorefrontData(vendor: _vendor, products: _products),
          onAction: actions.add,
          onAddToCart: added.add,
        ),
      ),
    );

    expect(find.text('TACO BOLT'), findsOneWidget);
    expect(find.text('Sparks fly'), findsOneWidget);
    expect(find.text('4.5 · 200 reviews'), findsOneWidget);
    expect(find.text('OPEN LATE'), findsOneWidget);
    expect(find.text('MENU'), findsOneWidget);
    expect(find.text('Street Taco'), findsOneWidget);
    expect(find.text(r'$3.50'), findsOneWidget);
    expect(find.text('Sold Thing'), findsNothing, reason: 'unavailable products are hidden from the list');
    expect(find.text('100 Main St'), findsOneWidget);

    await tester.tap(find.text('VIEW CART'));
    expect(actions.single.name, 'open_cart');

    await tester.tap(find.byIcon(Icons.add_box).first);
    expect(added.single.id, 'p1');

    await tester.tap(find.text('DIRECTIONS'));
    expect(actions.last.name, 'directions');
  });

  testWidgets('token references resolve against injected vendor tokens', (tester) async {
    final layout = LayoutNode.parse({
      'type': 'screen',
      'children': [
        {
          'type': 'text',
          'props': {
            'text': 'Amber?',
            'style': 'mono',
            'color': {r'$token': 'accent'},
          },
        },
      ],
    });
    final custom = HubbleTokens.host.merge({'accent': '#00AAFF'});
    await tester.pumpWidget(
      _host(
        LayoutRenderer(
          root: layout,
          data: const StorefrontData(vendor: _vendor),
        ),
        tokens: custom,
      ),
    );
    final text = tester.widget<Text>(find.text('Amber?'));
    expect(text.style?.color, const Color(0xFF00AAFF));
  });

  testWidgets('grid layout and product_card index', (tester) async {
    final layout = LayoutNode.parse({
      'type': 'screen',
      'children': [
        {
          'type': 'product_list',
          'props': {'layout': 'grid'},
        },
        {
          'type': 'product_card',
          'props': {'product_index': 1},
        },
        {
          'type': 'product_card',
          'props': {'product_index': 99},
        },
      ],
    });
    await tester.pumpWidget(
      _host(
        LayoutRenderer(
          root: layout,
          data: const StorefrontData(vendor: _vendor, products: _products),
        ),
      ),
    );
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Horchata'), findsNWidgets(2));
    expect(find.byType(ProductTile), findsNWidgets(3));
  });
}
