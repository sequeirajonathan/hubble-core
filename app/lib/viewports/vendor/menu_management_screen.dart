import 'package:flutter/material.dart';

import '../../core/models/product.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/theme/typography.dart';
import '../../interpreter/ast_renderer.dart';
import '../widgets/app_scope.dart';
import '../widgets/empty_state.dart';

/// Product CRUD. Prices are integers in cents; the checkout function prices
/// carts from this table, never from the client.
class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  Future<List<Product>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).layouts.fetchProducts(widget.vendorId);
  }

  void _reload() => setState(() => _future = AppScope.of(context).layouts.fetchProducts(widget.vendorId));

  Future<void> _edit([Product? existing]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductForm(existing: existing),
    );
    if (result == null || !mounted) return;
    final db = AppScope.of(context).db;
    if (existing == null) {
      await db.from('products').insert({...result, 'vendor_id': widget.vendorId});
    } else {
      await db.from('products').update(result).eq('id', existing.id);
    }
    _reload();
  }

  Future<void> _toggleAvailability(Product p) async {
    await AppScope.of(context).db.from('products').update({'is_available': !p.isAvailable}).eq('id', p.id);
    _reload();
  }

  Future<void> _delete(Product p) async {
    final t = ThemeInjector.tokensOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DELETE ITEM?'),
        content: Text('${p.name} will disappear from the storefront and every open cart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KEEP')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('DELETE', style: TextStyle(color: t.alert)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AppScope.of(context).db.from('products').delete().eq('id', p.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        icon: const Icon(Icons.add),
        label: Text('ITEM', style: HubbleType.mono(size: 13, weight: FontWeight.w700)),
      ),
      body: FutureBuilder<List<Product>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorCard(message: snap.error.toString(), onRetry: _reload);
          final products = snap.data ?? const [];
          if (products.isEmpty) {
            return const EmptyState(
              icon: Icons.restaurant_menu,
              title: 'NO ITEMS YET',
              body: 'Add your first product to fill the storefront menu.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = products[i];
              return Row(
                children: [
                  Expanded(
                    child: ProductTile(product: p, tokens: t, onTap: (_) => _edit(p)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'toggle' => _toggleAvailability(p),
                      'delete' => _delete(p),
                      _ => _edit(p),
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(p.isAvailable ? 'Mark sold out' : 'Mark available'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({this.existing});

  final Product? existing;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(text: widget.existing?.description);
  late final _price = TextEditingController(
    text: widget.existing == null ? '' : (widget.existing!.priceCents / 100).toStringAsFixed(2),
  );
  late final _image = TextEditingController(text: widget.existing?.imageUrl);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _image.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final cents = (double.parse(_price.text.trim()) * 100).round();
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'price_cents': cents,
      'image_url': _image.text.trim().isEmpty ? null : _image.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeInjector.tokensOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'NEW ITEM' : 'EDIT ITEM',
              style: HubbleType.display(size: 22, color: t.onCanvas),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'NAME'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'DESCRIPTION'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: HubbleType.mono(size: 16, color: t.onCanvas),
              decoration: const InputDecoration(labelText: 'PRICE (USD)', prefixText: r'$ '),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n < 0) return 'Enter a price like 4.50';
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _image,
              decoration: const InputDecoration(labelText: 'IMAGE URL (HTTPS, OPTIONAL)'),
              validator: (v) => (v != null && v.trim().isNotEmpty && !v.trim().startsWith('https://'))
                  ? 'Must start with https://'
                  : null,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('SAVE')),
          ],
        ),
      ),
    );
  }
}
