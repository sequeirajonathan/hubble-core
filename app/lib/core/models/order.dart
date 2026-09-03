class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.referenceCode,
    required this.vendorId,
    required this.status,
    required this.subtotalCents,
    required this.platformFeeCents,
    required this.totalCents,
    required this.currency,
    required this.createdAt,
    this.vendorName,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendors'] as Map<String, dynamic>?;
    return OrderSummary(
      id: json['id'] as String,
      referenceCode: json['reference_code'] as String,
      vendorId: json['vendor_id'] as String,
      vendorName: vendor?['name'] as String? ?? json['vendor_name'] as String?,
      status: json['status'] as String,
      subtotalCents: (json['subtotal_cents'] as num).toInt(),
      platformFeeCents: (json['platform_fee_cents'] as num?)?.toInt() ?? 0,
      totalCents: (json['total_cents'] as num).toInt(),
      currency: json['currency'] as String? ?? 'usd',
      createdAt: json['created_at'] == null ? DateTime.now() : DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String referenceCode;
  final String vendorId;
  final String? vendorName;
  final String status;
  final int subtotalCents;
  final int platformFeeCents;
  final int totalCents;
  final String currency;
  final DateTime createdAt;
}
