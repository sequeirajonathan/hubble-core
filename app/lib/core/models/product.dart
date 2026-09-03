class ProductModifier {
  const ProductModifier({required this.id, required this.name, required this.priceDeltaCents});

  factory ProductModifier.fromJson(Map<String, dynamic> json) => ProductModifier(
    id: json['id'] as String,
    name: json['name'] as String,
    priceDeltaCents: (json['price_delta_cents'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final int priceDeltaCents;
}

class Product {
  const Product({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.priceCents,
    this.description,
    this.imageUrl,
    this.currency = 'usd',
    this.isAvailable = true,
    this.sortOrder = 0,
    this.modifiers = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final groups = (json['product_modifier_groups'] as List?) ?? const [];
    final modifiers = <ProductModifier>[
      for (final g in groups.cast<Map<String, dynamic>>())
        for (final m in ((g['product_modifiers'] as List?) ?? const []).cast<Map<String, dynamic>>())
          ProductModifier.fromJson(m),
    ];
    return Product(
      id: json['id'] as String,
      vendorId: json['vendor_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      priceCents: (json['price_cents'] as num).toInt(),
      currency: json['currency'] as String? ?? 'usd',
      isAvailable: json['is_available'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      modifiers: modifiers,
    );
  }

  final String id;
  final String vendorId;
  final String name;
  final String? description;
  final String? imageUrl;
  final int priceCents;
  final String currency;
  final bool isAvailable;
  final int sortOrder;
  final List<ProductModifier> modifiers;

  Map<String, dynamic> toJson() => {
    'id': id,
    'vendor_id': vendorId,
    'name': name,
    'description': description,
    'image_url': imageUrl,
    'price_cents': priceCents,
    'currency': currency,
    'is_available': isAvailable,
    'sort_order': sortOrder,
  };
}

/// Money formatting lives in one place so prices render identically in the
/// AST renderer, carts and vendor dashboards.
String formatCents(int cents, {String currency = 'usd'}) {
  final symbol = switch (currency.toLowerCase()) {
    'usd' => r'$',
    'eur' => '€',
    'gbp' => '£',
    _ => '${currency.toUpperCase()} ',
  };
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '$symbol$whole.$frac';
}
