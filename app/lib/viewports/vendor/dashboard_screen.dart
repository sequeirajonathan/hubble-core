import 'package:flutter/material.dart';

import '../../core/models/order.dart';
import '../../core/models/product.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../widgets/app_scope.dart';
import '../widgets/empty_state.dart';

class _Stats {
  const _Stats({
    required this.ordersToday,
    required this.revenueTodayCents,
    required this.pending,
    this.rating,
    this.reviewCount,
    this.isLive = false,
    this.recent = const [],
  });

  final int ordersToday;
  final int revenueTodayCents;
  final int pending;
  final double? rating;
  final int? reviewCount;
  final bool isLive;
  final List<OrderSummary> recent;
}

/// Vendor dashboard: today's numbers, live toggle, recent orders.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<_Stats>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_Stats> _load() async {
    final db = AppScope.of(context).db;
    final startOfDay = DateTime.now().toUtc();
    final since = DateTime.utc(startOfDay.year, startOfDay.month, startOfDay.day).toIso8601String();
    final results = await Future.wait<Object?>([
      db
          .from('orders')
          .select(
            'id, reference_code, vendor_id, status, subtotal_cents, platform_fee_cents, total_cents, currency, created_at',
          )
          .eq('vendor_id', widget.vendorId)
          .order('created_at', ascending: false)
          .limit(20),
      db
          .from('vendors')
          .select('is_live, vendor_ratings(rating, review_count)')
          .eq('id', widget.vendorId)
          .single(),
    ]);
    final orders = (results[0] as List).cast<Map<String, dynamic>>().map(OrderSummary.fromJson).toList();
    final vendor = results[1] as Map<String, dynamic>;
    final ratings = vendor['vendor_ratings'];
    final ratingRow = ratings is List && ratings.isNotEmpty
        ? ratings.first as Map<String, dynamic>
        : ratings is Map<String, dynamic>
        ? ratings
        : null;
    final today = orders.where(
      (o) =>
          o.createdAt.toUtc().toIso8601String().compareTo(since) >= 0 &&
          o.status != 'failed' &&
          o.status != 'cancelled',
    );
    return _Stats(
      ordersToday: today.length,
      revenueTodayCents: today.fold(0, (sum, o) => sum + o.totalCents),
      pending: orders.where((o) => o.status == 'paid' || o.status == 'accepted').length,
      rating: (ratingRow?['rating'] as num?)?.toDouble(),
      reviewCount: (ratingRow?['review_count'] as num?)?.toInt(),
      isLive: vendor['is_live'] as bool? ?? false,
      recent: orders,
    );
  }

  Future<void> _setLive(bool value) async {
    await AppScope.of(context).db.from('vendors').update({'is_live': value}).eq('id', widget.vendorId);
    setState(() => _future = _load());
  }

  Future<void> _advance(OrderSummary order) async {
    final next = switch (order.status) {
      'paid' => 'accepted',
      'accepted' => 'ready',
      'ready' => 'completed',
      _ => null,
    };
    if (next == null) return;
    await AppScope.of(context).db.from('orders').update({'status': next}).eq('id', order.id);
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return FutureBuilder<_Stats>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorCard(message: snap.error.toString(), onRetry: () => setState(() => _future = _load()));
        }
        final s = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  s.isLive ? 'STOREFRONT IS LIVE' : 'STOREFRONT IS HIDDEN',
                  style: HubbleType.display(size: 18, color: s.isLive ? t.accent : t.iron),
                ),
                subtitle: Text(
                  'Shoppers only see live storefronts.',
                  style: HubbleType.mono(size: 11, color: t.iron),
                ),
                value: s.isLive,
                onChanged: _setLive,
              ),
              const SizedBox(height: 12),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: _Stat(label: 'ORDERS TODAY', value: '${s.ordersToday}', tokens: t),
                  ),
                  Expanded(
                    child: _Stat(label: 'REVENUE TODAY', value: formatCents(s.revenueTodayCents), tokens: t),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: _Stat(label: 'IN PROGRESS', value: '${s.pending}', tokens: t),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'RATING',
                      value: s.rating == null
                          ? '—'
                          : '${s.rating!.toStringAsFixed(1)} (${s.reviewCount ?? 0})',
                      tokens: t,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'RECENT ORDERS',
                style: HubbleType.mono(size: 12, color: t.iron, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (s.recent.isEmpty)
                Text(
                  'No orders yet. Publish your design and go live.',
                  style: HubbleType.body(color: t.onCanvas),
                )
              else
                for (final o in s.recent)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        o.referenceCode,
                        style: HubbleType.mono(size: 14, color: t.onCanvas, weight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${o.status.replaceAll('_', ' ').toUpperCase()} · ${formatCents(o.totalCents, currency: o.currency)}',
                        style: HubbleType.mono(size: 11, color: o.status == 'failed' ? t.alert : t.iron),
                      ),
                      trailing: switch (o.status) {
                        'paid' => TextButton(onPressed: () => _advance(o), child: const Text('ACCEPT')),
                        'accepted' => TextButton(onPressed: () => _advance(o), child: const Text('READY')),
                        'ready' => TextButton(onPressed: () => _advance(o), child: const Text('DONE')),
                        _ => null,
                      },
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.tokens});

  final String label;
  final String value;
  final HubbleTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: tokens.surface,
      border: Border.all(color: tokens.iron),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: HubbleType.mono(size: 11, color: tokens.iron, weight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(value, style: HubbleType.display(size: 24, color: tokens.accent)),
      ],
    ),
  );
}
