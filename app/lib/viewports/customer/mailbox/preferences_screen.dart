import 'package:flutter/material.dart';

import '../../../core/models/vendor.dart';
import '../../../core/theme/theme_scope.dart';
import '../../../core/theme/typography.dart';
import '../../widgets/app_scope.dart';

/// Opt-out matrix. Flipping a niche off removes the user from that niche's
/// targeting queue immediately (the view is evaluated at send time).
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final Map<VendorNiche, bool> _optIn = {for (final n in VendorNiche.values) n: true};
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final rows = await AppScope.of(context).db.from('user_niche_preferences').select('niche, opted_in');
    if (!mounted) return;
    setState(() {
      for (final r in rows) {
        _optIn[VendorNiche.fromWire(r['niche'] as String?)] = r['opted_in'] as bool? ?? true;
      }
      _loading = false;
    });
  }

  Future<void> _toggle(VendorNiche niche, bool value) async {
    setState(() => _optIn[niche] = value);
    await AppScope.of(context).db
        .rpc<dynamic>('set_niche_opt_in', params: {'p_niche': niche.wire, 'p_opted_in': value});
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('MAILBOX PREFERENCES')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Pick which kinds of local businesses may drop offers in your mailbox. Off means off: you leave that queue instantly.',
                  style: HubbleType.body(size: 14, color: t.onCanvas),
                ),
                const SizedBox(height: 16),
                for (final niche in VendorNiche.values)
                  SwitchListTile(
                    title: Text(
                      niche.label.toUpperCase(),
                      style: HubbleType.mono(size: 13, color: t.onCanvas, weight: FontWeight.w600),
                    ),
                    value: _optIn[niche] ?? true,
                    onChanged: (v) => _toggle(niche, v),
                  ),
              ],
            ),
    );
  }
}
