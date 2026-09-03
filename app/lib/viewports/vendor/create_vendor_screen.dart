import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/models/vendor.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/typography.dart';
import '../widgets/app_scope.dart';

/// Vendor creation hub. Creating a vendor seeds a starter layout (SQL
/// trigger), enrolls the creator as owner, and refreshes the session so the
/// vendor viewport unlocks with the same JWT.
class CreateVendorScreen extends StatefulWidget {
  const CreateVendorScreen({super.key});

  @override
  State<CreateVendorScreen> createState() => _CreateVendorScreenState();
}

class _CreateVendorScreenState extends State<CreateVendorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _tagline = TextEditingController();
  VendorNiche _niche = VendorNiche.foodTruck;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _tagline.dispose();
    super.dispose();
  }

  static String slugify(String input) {
    final s = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return s.length > 48 ? s.substring(0, 48).replaceAll(RegExp(r'-+$'), '') : s;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final scope = AppScope.of(context);
    final uid = scope.session.userId;
    if (uid == null) {
      unawaited(context.push('/sign-in'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await scope.db
          .from('vendors')
          .insert({
            'owner_id': uid,
            'name': _name.text.trim(),
            'slug': _slug.text.trim(),
            'tagline': _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
            'niche': _niche.wire,
          })
          .select('id')
          .single();
      await scope.session.refresh();
      await scope.session.setMode(ViewportMode.vendor);
      if (mounted) context.go('/vendor/${row['id']}');
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('NEW STOREFRONT')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('DEPLOY IN MINUTES', style: HubbleType.display(size: 28, color: t.accent)),
            Text(
              'You get a starter layout immediately. Style it, preview it, publish when ready.',
              style: HubbleType.body(color: t.onCanvas),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'BUSINESS NAME'),
              onChanged: (v) => _slug.text = slugify(v),
              validator: (v) => (v == null || v.trim().length < 2) ? 'At least 2 characters' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _slug,
              style: HubbleType.mono(size: 14, color: t.onCanvas),
              decoration: const InputDecoration(labelText: 'HANDLE', prefixText: 'hubble/'),
              validator: (v) => RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,46}[a-z0-9])?$').hasMatch(v ?? '')
                  ? null
                  : 'Lowercase letters, numbers, dashes',
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _tagline,
              maxLength: 140,
              decoration: const InputDecoration(labelText: 'TAGLINE'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<VendorNiche>(
              initialValue: _niche,
              decoration: const InputDecoration(labelText: 'CATEGORY'),
              items: [for (final n in VendorNiche.values) DropdownMenuItem(value: n, child: Text(n.label))],
              onChanged: (v) => setState(() => _niche = v ?? _niche),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: HubbleType.mono(size: 12, color: t.alert)),
              ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('CREATE STOREFRONT')),
          ],
        ),
      ),
    );
  }
}
