import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vendor.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../interpreter/layout_repository.dart';
import '../widgets/app_scope.dart';
import '../widgets/empty_state.dart';

/// Search + browse live vendors. Tapping a row applies the vendor's theme
/// tokens immediately (before the storefront finishes loading) so the
/// transition already reads as "their" app.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  VendorNiche? _niche;
  Future<List<_VendorRow>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<List<_VendorRow>> _load() async {
    final scope = AppScope.of(context);
    var query = scope.db
        .from('vendors')
        .select('${LayoutRepository.vendorColumns}, storefront_layouts(theme)')
        .eq('is_live', true);
    final text = _query.text.trim();
    if (text.isNotEmpty) query = query.or('name.ilike.%$text%,tagline.ilike.%$text%');
    if (_niche != null) query = query.eq('niche', _niche!.wire);
    final rows = await query.order('created_at', ascending: false).limit(60);
    final home = scope.session.profile;
    final list = rows.map((r) {
      final vendor = Vendor.fromJson(r);
      final layout = r['storefront_layouts'];
      final theme = layout is Map
          ? (layout['theme'] as Map?)?.cast<String, dynamic>()
          : layout is List && layout.isNotEmpty
          ? ((layout.first as Map)['theme'] as Map?)?.cast<String, dynamic>()
          : null;
      double? km;
      if (home != null && home.hasHome && vendor.hasLocation) {
        km = _haversineKm(home.homeLat!, home.homeLng!, vendor.lat!, vendor.lng!);
      }
      return _VendorRow(vendor: vendor, theme: theme, distanceKm: km);
    }).toList();
    list.sort((a, b) => (a.distanceKm ?? 1e9).compareTo(b.distanceKm ?? 1e9));
    return list;
  }

  void _refresh() => setState(() => _future = _load());

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('HUBBLE', style: HubbleType.display(size: 24, color: t.accent)),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _query,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'SEARCH NEARBY'),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _chip(null, 'ALL'),
                for (final n in VendorNiche.values) _chip(n, n.label.toUpperCase()),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_VendorRow>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) return ErrorCard(message: snap.error.toString(), onRetry: _refresh);
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'NOTHING HERE YET',
                    body: 'No live storefronts match. Try another category or clear the search.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _VendorRowTile(row: rows[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(VendorNiche? niche, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: _niche == niche,
      onSelected: (_) {
        setState(() => _niche = niche);
        _refresh();
      },
    ),
  );
}

class _VendorRow {
  const _VendorRow({required this.vendor, this.theme, this.distanceKm});

  final Vendor vendor;
  final Map<String, dynamic>? theme;
  final double? distanceKm;
}

class _VendorRowTile extends StatelessWidget {
  const _VendorRowTile({required this.row});

  final _VendorRow row;

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    final v = row.vendor;
    final accent = row.theme?['accent'] is String
        ? (parseHexColor(row.theme!['accent'] as String) ?? t.accent)
        : t.accent;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          // Re-skin first, navigate second: the header and buttons flip to the
          // vendor's palette the moment the row is tapped.
          ThemeInjector.of(context).applyVendor(v.id, row.theme);
          context.push('/store/${v.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  v.name.isEmpty ? '?' : v.name[0].toUpperCase(),
                  style: HubbleType.display(size: 24, color: t.onAccent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name.toUpperCase(), style: HubbleType.display(size: 18, color: t.onCanvas)),
                    Text(
                      [
                        v.niche.label,
                        if (row.distanceKm != null) '${row.distanceKm!.toStringAsFixed(1)} km',
                      ].join(' · '),
                      style: HubbleType.mono(size: 12, color: t.iron),
                    ),
                    if (v.tagline != null)
                      Text(
                        v.tagline!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HubbleType.body(size: 13, color: t.onCanvas),
                      ),
                  ],
                ),
              ),
              if (v.rating != null)
                Column(
                  children: [
                    Icon(Icons.star, color: accent, size: 18),
                    Text(v.rating!.toStringAsFixed(1), style: HubbleType.mono(size: 12, color: t.onCanvas)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0088;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
