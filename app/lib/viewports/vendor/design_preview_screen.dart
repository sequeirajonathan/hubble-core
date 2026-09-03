import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/theme_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../interpreter/ast_node.dart';
import '../../interpreter/ast_renderer.dart';
import '../../interpreter/layout_repository.dart';
import '../widgets/app_scope.dart';
import '../widgets/empty_state.dart';

/// Sandbox isolation: this screen reads storefront_layouts_draft only, renders
/// it with the exact interpreter shoppers use, and offers Publish / Reset.
/// Nothing here touches the live table until Publish.
class DesignPreviewScreen extends StatefulWidget {
  const DesignPreviewScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<DesignPreviewScreen> createState() => _DesignPreviewScreenState();
}

class _DesignPreviewScreenState extends State<DesignPreviewScreen> {
  Future<StorefrontBundle>? _future;
  StorefrontBundle? _bundle;
  final _prompt = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<StorefrontBundle> _load() async {
    final bundle = await AppScope.of(context).layouts.loadStorefront(widget.vendorId, draft: true);
    _bundle = bundle;
    return bundle;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
      if (mounted) setState(() => _status = label);
    } catch (err) {
      if (mounted) setState(() => _status = 'Error: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() =>
      _run('Draft updated by the AI generator. Preview below, then publish.', () async {
        final scope = AppScope.of(context);
        final res = await scope.db.functions.invoke(
          'ai-generator',
          body: {'vendor_id': widget.vendorId, 'prompt': _prompt.text.trim()},
        );
        final data = (res.data as Map).cast<String, dynamic>();
        if (res.status >= 400) throw Exception(data['error'] ?? 'generation failed');
        _reload();
      });

  Future<void> _publish() => _run('Published. Shoppers now see this version.', () async {
    final layout = await AppScope.of(context).layouts.publishDraft(widget.vendorId);
    _reload();
    if (mounted) setState(() => _status = 'Published v${layout.version}. Shoppers now see this version.');
  });

  Future<void> _reset() => _run('Draft reset to the live layout.', () async {
    await AppScope.of(context).layouts.resetDraft(widget.vendorId);
    _reload();
  });

  Future<void> _saveTheme(HubbleTokens tokens) => _run('Draft theme saved.', () async {
    final bundle = _bundle;
    if (bundle == null) return;
    final next = StorefrontLayout(root: bundle.layout.root, theme: tokens.diffFromHost(), isDraft: true);
    await AppScope.of(context).layouts.saveDraft(widget.vendorId, next);
    _reload();
  });

  Future<void> _editJson(StorefrontBundle bundle) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(bundle.layout.root.toJson()),
    );
    String? problem;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('LAYOUT JSON'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    expands: true,
                    style: HubbleType.mono(size: 12),
                  ),
                ),
                if (problem != null)
                  Text(problem!, style: HubbleType.mono(size: 11, color: HubbleTokens.host.alert)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
            FilledButton(
              onPressed: () {
                try {
                  LayoutNode.parse(jsonDecode(controller.text));
                  Navigator.pop(context, true);
                } catch (err) {
                  setDialog(() => problem = err.toString());
                }
              },
              child: const Text('SAVE DRAFT'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      final root = LayoutNode.parse(jsonDecode(controller.text));
      await _run('Draft layout saved.', () async {
        await AppScope.of(context).layouts.saveDraft(
          widget.vendorId,
          StorefrontLayout(root: root, theme: bundle.layout.theme, isDraft: true),
        );
        _reload();
      });
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = ThemeInjector.tokensOf(context);
    return FutureBuilder<StorefrontBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final err = snap.error;
          return ErrorCard(
            message: err is LayoutValidationException
                ? 'Draft is invalid (${err.path}: ${err.message}). Reset it or fix the JSON.'
                : err.toString(),
            onRetry: _reload,
          );
        }
        final bundle = snap.data!;
        final draftTokens = HubbleTokens.host.merge(bundle.layout.theme);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('DRAFT PREVIEW', style: HubbleType.display(size: 20, color: host.onCanvas)),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _editJson(bundle),
                  icon: const Icon(Icons.data_object),
                  label: const Text('JSON'),
                ),
              ],
            ),
            Text(
              'Exactly what shoppers will see after you publish.',
              style: HubbleType.mono(size: 11, color: host.iron),
            ),
            const SizedBox(height: 12),
            _PhoneFrame(
              tokens: draftTokens,
              child: LayoutRenderer(
                root: bundle.layout.root,
                data: bundle.data,
                tokens: draftTokens,
                onAction: (_) {},
                onAddToCart: (_) {},
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'THEME TOKENS',
              style: HubbleType.mono(size: 12, color: host.iron, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _TokenEditor(tokens: draftTokens, enabled: !_busy, onChanged: _saveTheme),
            const SizedBox(height: 20),
            Text(
              'AI GENERATOR',
              style: HubbleType.mono(size: 12, color: host.iron, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                hintText: 'e.g. "Lead with a grid of my three best sellers and add a directions card at the bottom."',
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('TRANSFORM DRAFT'),
            ),
            const SizedBox(height: 20),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _busy ? null : _reset, child: const Text('RESET TO LIVE')),
                ),
                Expanded(
                  child: FilledButton(onPressed: _busy ? null : _publish, child: const Text('PUBLISH')),
                ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _status!,
                  style: HubbleType.mono(
                    size: 12,
                    color: _status!.startsWith('Error') ? host.alert : host.accent,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.tokens, required this.child});

  final HubbleTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: 520,
    decoration: BoxDecoration(
      color: tokens.canvas,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: tokens.iron, width: 3),
    ),
    clipBehavior: Clip.antiAlias,
    child: TokenTheme(tokens: tokens, child: child),
  );
}

class _TokenEditor extends StatelessWidget {
  const _TokenEditor({required this.tokens, required this.enabled, required this.onChanged});

  final HubbleTokens tokens;
  final bool enabled;
  final ValueChanged<HubbleTokens> onChanged;

  static const _presets = <String, List<Color>>{
    'accent': [
      Color(0xFFFF7A00),
      Color(0xFF00AAFF),
      Color(0xFF39D353),
      Color(0xFFFFD60A),
      Color(0xFFFF2D95),
      Color(0xFFB388FF),
    ],
    'canvas': [
      Color(0xFF1A1A1A),
      Color(0xFF0B1220),
      Color(0xFF14110F),
      Color(0xFF101814),
      Color(0xFF1E1420),
      Color(0xFF111111),
    ],
    'surface': [
      Color(0xFF222222),
      Color(0xFF15203A),
      Color(0xFF241B16),
      Color(0xFF17241C),
      Color(0xFF2A1D2C),
      Color(0xFF1A1A1A),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final host = ThemeInjector.tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in _presets.entries) ...[
          Text(entry.key.toUpperCase(), style: HubbleType.mono(size: 11, color: host.iron)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in entry.value)
                _Swatch(
                  color: color,
                  selected: tokens.byKey(entry.key) == color,
                  onTap: enabled ? () => onChanged(tokens.merge({entry.key: toHex(color)})) : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final host = ThemeInjector.tokensOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? host.accent : host.iron, width: selected ? 3 : 1),
        ),
      ),
    );
  }
}
