enum MailboxKind {
  offer('offer'),
  notice('notice'),
  discountCode('discount_code'),
  orderUpdate('order_update'),
  system('system');

  const MailboxKind(this.wire);

  final String wire;

  static MailboxKind fromWire(String? wire) =>
      values.firstWhere((k) => k.wire == wire, orElse: () => MailboxKind.system);
}

class MailboxMessage {
  const MailboxMessage({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.vendorId,
    this.vendorName,
    this.payload = const {},
    this.readAt,
    this.expiresAt,
  });

  factory MailboxMessage.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendors'] as Map<String, dynamic>?;
    return MailboxMessage(
      id: json['id'] as String,
      kind: MailboxKind.fromWire(json['kind'] as String?),
      title: json['title'] as String,
      body: json['body'] as String,
      vendorId: json['vendor_id'] as String?,
      vendorName: vendor?['name'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      expiresAt: json['expires_at'] == null ? null : DateTime.parse(json['expires_at'] as String),
    );
  }

  final String id;
  final MailboxKind kind;
  final String title;
  final String body;
  final String? vendorId;
  final String? vendorName;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? expiresAt;

  bool get isRead => readAt != null;
}
