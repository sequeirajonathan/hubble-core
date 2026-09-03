import 'package:flutter/foundation.dart';

import '../../../core/models/product.dart';

/// One line in a vendor cart. Quantity and chosen modifier ids only; prices
/// are re-derived from the catalog at checkout by the database.
class CartLine {
  const CartLine({required this.product, required this.quantity, this.modifierIds = const [], this.note});

  final Product product;
  final int quantity;
  final List<String> modifierIds;
  final String? note;

  int get unitPriceCents =>
      product.priceCents +
      product.modifiers.where((m) => modifierIds.contains(m.id)).fold(0, (sum, m) => sum + m.priceDeltaCents);

  int get lineTotalCents => unitPriceCents * quantity;

  CartLine copyWith({int? quantity, String? note}) => CartLine(
    product: product,
    quantity: quantity ?? this.quantity,
    modifierIds: modifierIds,
    note: note ?? this.note,
  );

  /// Lines with the same product + modifiers merge.
  String get key => '${product.id}|${(List.of(modifierIds)..sort()).join(',')}';

  Map<String, dynamic> toJson() => {
    'product': product.toJson(),
    'quantity': quantity,
    'modifier_ids': modifierIds,
    'note': note,
  };

  static CartLine fromJson(Map<String, dynamic> json) => CartLine(
    product: Product.fromJson(json['product'] as Map<String, dynamic>),
    quantity: (json['quantity'] as num).toInt(),
    modifierIds: ((json['modifier_ids'] as List?) ?? const []).cast<String>(),
    note: json['note'] as String?,
  );
}

/// A cart bound to exactly one vendor.
class VendorCart {
  const VendorCart({required this.vendorId, required this.vendorName, this.lines = const []});

  final String vendorId;
  final String vendorName;
  final List<CartLine> lines;

  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);
  int get subtotalCents => lines.fold(0, (sum, l) => sum + l.lineTotalCents);
  bool get isEmpty => lines.isEmpty;
  String get currency => lines.isEmpty ? 'usd' : lines.first.product.currency;

  VendorCart copyWith({List<CartLine>? lines}) =>
      VendorCart(vendorId: vendorId, vendorName: vendorName, lines: lines ?? this.lines);

  Map<String, dynamic> toJson() => {
    'vendor_id': vendorId,
    'vendor_name': vendorName,
    'lines': lines.map((l) => l.toJson()).toList(),
  };

  static VendorCart fromJson(Map<String, dynamic> json) => VendorCart(
    vendorId: json['vendor_id'] as String,
    vendorName: json['vendor_name'] as String? ?? '',
    lines: ((json['lines'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(CartLine.fromJson)
        .toList(growable: false),
  );
}

class CartBoundaryException implements Exception {
  const CartBoundaryException(this.message);

  final String message;

  @override
  String toString() => 'CartBoundaryException: $message';
}

/// Single-store checkout boundary engine.
///
/// There is no master cart. Items are grouped into independent carts keyed by
/// vendor id; a product can only ever enter the cart of the vendor that sells
/// it, and checkout operates on one vendor at a time.
class CartController extends ChangeNotifier {
  CartController({Map<String, VendorCart>? initial}) : _carts = {...?initial};

  final Map<String, VendorCart> _carts;

  /// Carts with at least one line, most recently touched first.
  List<VendorCart> get carts =>
      _carts.values.where((c) => !c.isEmpty).toList(growable: false).reversed.toList();

  int get vendorCount => carts.length;

  int get totalItems => carts.fold(0, (sum, c) => sum + c.itemCount);

  VendorCart? cartFor(String vendorId) => _carts[vendorId];

  int itemCountFor(String vendorId) => _carts[vendorId]?.itemCount ?? 0;

  /// Adds a product to that product's vendor cart. [vendorName] labels a cart
  /// created by this call. Throws [CartBoundaryException] if [vendorId] does
  /// not match the product's vendor.
  void add(
    Product product, {
    required String vendorId,
    String vendorName = '',
    int quantity = 1,
    List<String> modifierIds = const [],
    String? note,
  }) {
    if (product.vendorId != vendorId) {
      throw CartBoundaryException(
        'product ${product.id} belongs to vendor ${product.vendorId}, not $vendorId',
      );
    }
    if (quantity < 1) throw ArgumentError.value(quantity, 'quantity', 'must be >= 1');
    final cart = _carts.remove(vendorId) ?? VendorCart(vendorId: vendorId, vendorName: vendorName);
    final line = CartLine(product: product, quantity: quantity, modifierIds: modifierIds, note: note);
    final lines = List<CartLine>.of(cart.lines);
    final existing = lines.indexWhere((l) => l.key == line.key);
    if (existing >= 0) {
      lines[existing] = lines[existing].copyWith(
        quantity: (lines[existing].quantity + quantity).clamp(1, 99),
      );
    } else {
      lines.add(line);
    }
    _carts[vendorId] = cart.copyWith(lines: lines);
    notifyListeners();
  }

  void setQuantity(String vendorId, String lineKey, int quantity) {
    final cart = _carts[vendorId];
    if (cart == null) return;
    final lines = List<CartLine>.of(cart.lines);
    final index = lines.indexWhere((l) => l.key == lineKey);
    if (index < 0) return;
    if (quantity <= 0) {
      lines.removeAt(index);
    } else {
      lines[index] = lines[index].copyWith(quantity: quantity.clamp(1, 99));
    }
    _carts[vendorId] = cart.copyWith(lines: lines);
    notifyListeners();
  }

  void remove(String vendorId, String lineKey) => setQuantity(vendorId, lineKey, 0);

  void clear(String vendorId) {
    if (_carts.remove(vendorId) != null) notifyListeners();
  }

  Map<String, dynamic> toJson() => {for (final e in _carts.entries) e.key: e.value.toJson()};

  static CartController fromJson(Map<String, dynamic>? json) {
    if (json == null) return CartController();
    final carts = <String, VendorCart>{};
    for (final e in json.entries) {
      try {
        carts[e.key] = VendorCart.fromJson((e.value as Map).cast<String, dynamic>());
      } catch (_) {
        // A corrupt cached cart is dropped rather than blocking startup.
      }
    }
    return CartController(initial: carts);
  }
}
