class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.email,
    this.phone,
    this.homeLat,
    this.homeLng,
    this.discoveryRadiusKm = 15,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    displayName: json['display_name'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    homeLat: (json['home_lat'] as num?)?.toDouble(),
    homeLng: (json['home_lng'] as num?)?.toDouble(),
    discoveryRadiusKm: (json['discovery_radius_km'] as num?)?.toDouble() ?? 15,
  );

  final String id;
  final String? displayName;
  final String? email;
  final String? phone;
  final double? homeLat;
  final double? homeLng;
  final double discoveryRadiusKm;

  bool get hasHome => homeLat != null && homeLng != null;
}
