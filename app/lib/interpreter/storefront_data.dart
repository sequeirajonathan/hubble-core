import '../core/models/product.dart';
import '../core/models/vendor.dart';

/// Runtime data the interpreter binds into a layout (`{"$bind": ...}`).
class StorefrontData {
  const StorefrontData({required this.vendor, this.products = const []});

  final Vendor vendor;
  final List<Product> products;

  Object? resolve(String path) => switch (path) {
    'vendor.name' => vendor.name,
    'vendor.tagline' => vendor.tagline,
    'vendor.logo_url' => vendor.logoUrl,
    'vendor.address_text' => vendor.addressText,
    'vendor.phone' => vendor.phone,
    'vendor.website_url' => vendor.websiteUrl,
    'vendor.hours_text' => vendor.hoursText,
    'vendor.rating' => vendor.rating,
    'vendor.review_count' => vendor.reviewCount,
    'vendor.products' => products,
    _ => null,
  };
}
