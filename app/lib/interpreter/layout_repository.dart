import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models/product.dart';
import '../core/models/vendor.dart';
import '../core/storage/local_cache.dart';
import 'ast_node.dart';
import 'storefront_data.dart';

/// A parsed storefront: layout tree plus vendor theme overrides.
class StorefrontLayout {
  const StorefrontLayout({required this.root, required this.theme, this.version = 0, this.isDraft = false});

  factory StorefrontLayout.fromRow(Map<String, dynamic> row, {bool isDraft = false}) => StorefrontLayout(
    root: LayoutNode.parse(row['ast']),
    theme: (row['theme'] as Map?)?.cast<String, dynamic>() ?? const {},
    version: (row['version'] as num?)?.toInt() ?? 0,
    isDraft: isDraft,
  );

  final LayoutNode root;
  final Map<String, dynamic> theme;
  final int version;
  final bool isDraft;

  Map<String, dynamic> toRow() => {'ast': root.toJson(), 'theme': theme, 'version': version};
}

/// Everything a storefront screen needs in one object.
class StorefrontBundle {
  const StorefrontBundle({required this.layout, required this.data});

  final StorefrontLayout layout;
  final StorefrontData data;
}

/// Fetches live layouts for shoppers and drafts for vendors. Live layouts are
/// cached locally so re-opening a favorite store renders before the network.
class LayoutRepository {
  LayoutRepository(this._db, {LocalCache? cache}) : _cache = cache; // ignore: prefer_initializing_formals

  final SupabaseClient _db;
  final LocalCache? _cache;

  static const vendorColumns =
      'id, name, slug, niche, tagline, logo_url, lat, lng, address_text, phone, website_url, hours_text, is_live, '
      'vendor_ratings(rating, review_count)';

  static const productColumns =
      'id, vendor_id, name, description, image_url, price_cents, currency, is_available, sort_order, '
      'product_modifier_groups(id, name, product_modifiers(id, name, price_delta_cents))';

  Future<Vendor> fetchVendor(String vendorId) async {
    final row = await _db.from('vendors').select(vendorColumns).eq('id', vendorId).single();
    return Vendor.fromJson(row);
  }

  Future<List<Product>> fetchProducts(String vendorId) async {
    final rows = await _db
        .from('products')
        .select(productColumns)
        .eq('vendor_id', vendorId)
        .order('sort_order');
    return rows.map(Product.fromJson).toList(growable: false);
  }

  Future<StorefrontLayout> fetchLive(String vendorId) async {
    final row = await _db
        .from('storefront_layouts')
        .select('ast, theme, version')
        .eq('vendor_id', vendorId)
        .single();
    await _cache?.writeLayout(vendorId, row);
    return StorefrontLayout.fromRow(row);
  }

  StorefrontLayout? cachedLive(String vendorId) {
    final row = _cache?.readLayout(vendorId);
    if (row == null) return null;
    try {
      return StorefrontLayout.fromRow(row);
    } on LayoutValidationException {
      return null;
    }
  }

  Future<StorefrontLayout> fetchDraft(String vendorId) async {
    final row = await _db
        .from('storefront_layouts_draft')
        .select('ast, theme')
        .eq('vendor_id', vendorId)
        .single();
    return StorefrontLayout.fromRow(row, isDraft: true);
  }

  Future<void> saveDraft(String vendorId, StorefrontLayout layout) async {
    await _db
        .from('storefront_layouts_draft')
        .update({'ast': layout.root.toJson(), 'theme': layout.theme})
        .eq('vendor_id', vendorId);
  }

  Future<StorefrontLayout> publishDraft(String vendorId) async {
    final row = await _db.rpc<dynamic>('publish_storefront_draft', params: {'p_vendor_id': vendorId});
    return StorefrontLayout.fromRow((row as Map).cast<String, dynamic>());
  }

  Future<StorefrontLayout> resetDraft(String vendorId) async {
    final row = await _db.rpc<dynamic>('reset_storefront_draft', params: {'p_vendor_id': vendorId});
    return StorefrontLayout.fromRow((row as Map).cast<String, dynamic>(), isDraft: true);
  }

  Future<StorefrontBundle> loadStorefront(String vendorId, {bool draft = false}) async {
    final results = await Future.wait<Object>([
      fetchVendor(vendorId),
      fetchProducts(vendorId),
      draft ? fetchDraft(vendorId) : fetchLive(vendorId),
    ]);
    return StorefrontBundle(
      layout: results[2] as StorefrontLayout,
      data: StorefrontData(vendor: results[0] as Vendor, products: results[1] as List<Product>),
    );
  }
}
