/// Business categories. Wire names match the `vendor_niche` SQL enum.
enum VendorNiche {
  foodTruck('food_truck', 'Food trucks'),
  cardShop('card_shop', 'Card shops'),
  startup('startup', 'Startups'),
  retail('retail', 'Retail'),
  services('services', 'Services'),
  other('other', 'Everything else');

  const VendorNiche(this.wire, this.label);

  final String wire;
  final String label;

  static VendorNiche fromWire(String? wire) =>
      values.firstWhere((n) => n.wire == wire, orElse: () => VendorNiche.other);
}

class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.slug,
    required this.niche,
    this.tagline,
    this.logoUrl,
    this.lat,
    this.lng,
    this.addressText,
    this.phone,
    this.websiteUrl,
    this.hoursText,
    this.isLive = false,
    this.rating,
    this.reviewCount,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    final ratings = json['vendor_ratings'];
    final ratingRow = ratings is List && ratings.isNotEmpty
        ? ratings.first as Map<String, dynamic>
        : ratings is Map<String, dynamic>
        ? ratings
        : null;
    return Vendor(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      niche: VendorNiche.fromWire(json['niche'] as String?),
      tagline: json['tagline'] as String?,
      logoUrl: json['logo_url'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      addressText: json['address_text'] as String?,
      phone: json['phone'] as String?,
      websiteUrl: json['website_url'] as String?,
      hoursText: json['hours_text'] as String?,
      isLive: json['is_live'] as bool? ?? false,
      rating: (ratingRow?['rating'] as num?)?.toDouble(),
      reviewCount: (ratingRow?['review_count'] as num?)?.toInt(),
    );
  }

  final String id;
  final String name;
  final String slug;
  final VendorNiche niche;
  final String? tagline;
  final String? logoUrl;
  final double? lat;
  final double? lng;
  final String? addressText;
  final String? phone;
  final String? websiteUrl;
  final String? hoursText;
  final bool isLive;
  final double? rating;
  final int? reviewCount;

  bool get hasLocation => lat != null && lng != null;
}

class VendorMembership {
  const VendorMembership({required this.vendor, required this.role});

  factory VendorMembership.fromJoinRow(Map<String, dynamic> row) => VendorMembership(
    vendor: Vendor.fromJson(row['vendors'] as Map<String, dynamic>),
    role: row['role'] as String? ?? 'staff',
  );

  final Vendor vendor;
  final String role;

  bool get canManage => role == 'owner' || role == 'manager';
}
