import 'package:flutter/material.dart';

import '../core/models/product.dart';
import '../core/theme/theme_scope.dart';
import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import 'ast_node.dart';
import 'storefront_data.dart';
import 'token_binder.dart';

/// Actions a layout can request. The host decides what they do (open the
/// single-store cart, dial, launch maps); the layout only names them.
class LayoutAction {
  const LayoutAction(this.name, {this.url, this.target});

  final String name;
  final String? url;
  final String? target;
}

typedef LayoutActionHandler = void Function(LayoutAction action);
typedef ProductTapHandler = void Function(Product product);

/// Walks a [LayoutNode] tree and emits native widgets. Pure mapping: no
/// scripting, no web view. Token references resolve against the tokens
/// injected by the nearest [ThemeInjector] (or [tokens] when given).
class LayoutRenderer extends StatelessWidget {
  const LayoutRenderer({
    super.key,
    required this.root,
    required this.data,
    this.tokens,
    this.onAction,
    this.onProductTap,
    this.onAddToCart,
  });

  final LayoutNode root;
  final StorefrontData data;
  final HubbleTokens? tokens;
  final LayoutActionHandler? onAction;
  final ProductTapHandler? onProductTap;
  final ProductTapHandler? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final t = tokens ?? ThemeInjector.tokensOf(context);
    final binder = TokenBinder(tokens: t, data: data);
    final ctx = _RenderContext(binder: binder, tokens: t, renderer: this);
    return _buildNode(context, root, ctx);
  }

  Widget _buildNode(BuildContext context, LayoutNode node, _RenderContext ctx) {
    final p = node.props;
    final b = ctx.binder;
    switch (node.type) {
      case NodeType.screen:
        final children = _children(context, node, ctx);
        final padding = b.number(p, 'padding', fallback: 16)!;
        final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        if (b.boolean(p, 'scroll', fallback: true)) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + 96),
            child: body,
          );
        }
        return Padding(padding: EdgeInsets.all(padding), child: body);

      case NodeType.column:
        return Padding(
          padding: EdgeInsets.all(b.number(p, 'padding', fallback: 0)!),
          child: Column(
            crossAxisAlignment: _cross(b.string(p, 'align')),
            mainAxisSize: MainAxisSize.min,
            spacing: b.number(p, 'gap', fallback: 8)!,
            children: _children(context, node, ctx),
          ),
        );

      case NodeType.row:
        return Padding(
          padding: EdgeInsets.all(b.number(p, 'padding', fallback: 0)!),
          child: Row(
            mainAxisAlignment: _main(b.string(p, 'align')),
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: b.number(p, 'gap', fallback: 8)!,
            children: _children(context, node, ctx),
          ),
        );

      case NodeType.stack:
        return Stack(children: _children(context, node, ctx));

      case NodeType.spacer:
        final size = b.number(p, 'size', fallback: 16)!;
        return SizedBox(height: size, width: size);

      case NodeType.divider:
        return Divider(color: ctx.tokens.iron, height: 24);

      case NodeType.text:
        return _text(context, p, ctx);

      case NodeType.image:
        return _image(p, ctx);

      case NodeType.hero:
        return _hero(context, p, ctx);

      case NodeType.badge:
        return _badge(p, ctx);

      case NodeType.button:
        return _button(context, p, ctx);

      case NodeType.productList:
        return _productList(context, p, ctx);

      case NodeType.productCard:
        final index = b.number(p, 'product_index', fallback: 0)!.toInt();
        final products = data.products;
        if (index < 0 || index >= products.length) return const SizedBox.shrink();
        return ProductTile(
          product: products[index],
          tokens: ctx.tokens,
          onTap: onProductTap,
          onAdd: onAddToCart,
        );

      case NodeType.hours:
        return _infoCard(
          ctx,
          icon: Icons.schedule,
          title: 'HOURS',
          body: data.vendor.hoursText ?? b.string(p, 'text') ?? 'Hours not posted yet',
        );

      case NodeType.mapPin:
        return _infoCard(
          ctx,
          icon: Icons.place_outlined,
          title: 'FIND US',
          body: data.vendor.addressText ?? 'Location not posted yet',
          action: data.vendor.hasLocation || data.vendor.addressText != null
              ? const LayoutAction('directions')
              : null,
          actionLabel: 'DIRECTIONS',
        );

      case NodeType.contact:
        final phone = data.vendor.phone;
        final site = data.vendor.websiteUrl;
        return _infoCard(
          ctx,
          icon: Icons.call_outlined,
          title: 'CONTACT',
          body: [?phone, ?site].join('\n').ifEmpty('No contact details yet'),
          action: phone != null
              ? const LayoutAction('call')
              : site != null
              ? LayoutAction('open_url', url: site)
              : null,
          actionLabel: phone != null ? 'CALL' : 'WEBSITE',
        );
    }
  }

  List<Widget> _children(BuildContext context, LayoutNode node, _RenderContext ctx) => [
    for (final child in node.children) _buildNode(context, child, ctx),
  ];

  Widget _text(BuildContext context, Map<String, Object?> p, _RenderContext ctx) {
    final b = ctx.binder;
    final text = b.string(p, 'text', fallback: '')!;
    final color = b.color(p, 'color', fallback: ctx.tokens.onCanvas);
    final style = switch (b.string(p, 'style', fallback: 'body')) {
      'display' => HubbleType.display(size: b.number(p, 'size', fallback: 24)!, color: color),
      'mono' => HubbleType.mono(size: b.number(p, 'size', fallback: 14)!, color: color),
      'caption' => HubbleType.mono(size: b.number(p, 'size', fallback: 12)!, color: ctx.tokens.iron),
      _ => HubbleType.body(size: b.number(p, 'size', fallback: 15)!, color: color),
    };
    return Text(text, style: style, textAlign: _textAlign(b.string(p, 'align')));
  }

  Widget _image(Map<String, Object?> p, _RenderContext ctx) {
    final b = ctx.binder;
    final src = b.string(p, 'src');
    final height = b.number(p, 'height', fallback: 180)!;
    final fit = b.string(p, 'fit') == 'contain' ? BoxFit.contain : BoxFit.cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: src == null || !src.startsWith('https://')
            ? _placeholder(ctx.tokens, Icons.image_outlined)
            : Image.network(
                src,
                fit: fit,
                errorBuilder: (_, _, _) => _placeholder(ctx.tokens, Icons.broken_image_outlined),
              ),
      ),
    );
  }

  Widget _hero(BuildContext context, Map<String, Object?> p, _RenderContext ctx) {
    final b = ctx.binder;
    final t = ctx.tokens;
    final title = b.string(p, 'title', fallback: data.vendor.name)!;
    final subtitle = b.string(p, 'subtitle', fallback: data.vendor.tagline);
    final logo = b.string(p, 'logo');
    final background = b.color(p, 'background', fallback: t.surface)!;
    final rating = data.vendor.rating;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.iron),
      ),
      child: Row(
        children: [
          _Logo(url: logo, tokens: t, fallbackLetter: title.isEmpty ? '?' : title[0]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: HubbleType.display(size: 26, color: t.onCanvas)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle, style: HubbleType.body(size: 14, color: t.onCanvas)),
                  ),
                if (rating != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.star, size: 16, color: t.accent),
                        const SizedBox(width: 4),
                        Text(
                          '${rating.toStringAsFixed(1)} · ${data.vendor.reviewCount ?? 0} reviews',
                          style: HubbleType.mono(size: 12, color: t.onCanvas),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(Map<String, Object?> p, _RenderContext ctx) {
    final b = ctx.binder;
    final t = ctx.tokens;
    final label = b.string(p, 'label', fallback: '')!;
    final tone = b.string(p, 'tone', fallback: 'accent');
    final color = switch (tone) {
      'alert' => t.alert,
      'iron' => t.iron,
      _ => t.accent,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label.toUpperCase(),
          style: HubbleType.mono(size: 11, color: color, weight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, Map<String, Object?> p, _RenderContext ctx) {
    final b = ctx.binder;
    final label = b.string(p, 'label', fallback: 'TAP')!;
    final action = LayoutAction(
      b.string(p, 'action', fallback: 'open_cart')!,
      url: b.string(p, 'url'),
      target: b.string(p, 'target'),
    );
    void handle() => onAction?.call(action);
    final child = Text(label.toUpperCase());
    return SizedBox(
      width: double.infinity,
      child: b.string(p, 'variant', fallback: 'primary') == 'outline'
          ? OutlinedButton(onPressed: handle, child: child)
          : FilledButton(onPressed: handle, child: child),
    );
  }

  Widget _productList(BuildContext context, Map<String, Object?> p, _RenderContext ctx) {
    final b = ctx.binder;
    final t = ctx.tokens;
    final title = b.string(p, 'title');
    final grid = b.string(p, 'layout') == 'grid';
    final products = data.products.where((x) => x.isAvailable).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title.toUpperCase(), style: HubbleType.display(size: 20, color: t.onCanvas)),
          ),
        if (products.isEmpty)
          _infoCard(ctx, icon: Icons.inventory_2_outlined, title: 'MENU', body: 'Nothing listed yet.')
        else if (grid)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
            ),
            itemCount: products.length,
            itemBuilder: (_, i) => ProductTile(
              product: products[i],
              tokens: t,
              compact: true,
              onTap: onProductTap,
              onAdd: onAddToCart,
            ),
          )
        else
          Column(
            spacing: 8,
            children: [
              for (final product in products)
                ProductTile(product: product, tokens: t, onTap: onProductTap, onAdd: onAddToCart),
            ],
          ),
      ],
    );
  }

  Widget _infoCard(
    _RenderContext ctx, {
    required IconData icon,
    required String title,
    required String body,
    LayoutAction? action,
    String? actionLabel,
  }) {
    final t = ctx.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.iron),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: HubbleType.mono(size: 12, color: t.iron, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(body, style: HubbleType.body(color: t.onCanvas)),
              ],
            ),
          ),
          if (action != null && onAction != null)
            TextButton(onPressed: () => onAction!(action), child: Text(actionLabel ?? 'OPEN')),
        ],
      ),
    );
  }

  static Widget _placeholder(HubbleTokens t, IconData icon) => ColoredBox(
    color: t.surface,
    child: Center(child: Icon(icon, color: t.iron, size: 36)),
  );

  static CrossAxisAlignment _cross(String? align) => switch (align) {
    'center' => CrossAxisAlignment.center,
    'end' => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.stretch,
  };

  static MainAxisAlignment _main(String? align) => switch (align) {
    'center' => MainAxisAlignment.center,
    'end' => MainAxisAlignment.end,
    'space_between' => MainAxisAlignment.spaceBetween,
    _ => MainAxisAlignment.start,
  };

  static TextAlign _textAlign(String? align) => switch (align) {
    'center' => TextAlign.center,
    'end' => TextAlign.end,
    _ => TextAlign.start,
  };
}

class _RenderContext {
  const _RenderContext({required this.binder, required this.tokens, required this.renderer});

  final TokenBinder binder;
  final HubbleTokens tokens;
  final LayoutRenderer renderer;
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.tokens, required this.fallbackLetter});

  final String? url;
  final HubbleTokens tokens;
  final String fallbackLetter;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tokens.accent, borderRadius: BorderRadius.circular(6)),
      child: Text(fallbackLetter.toUpperCase(), style: HubbleType.display(size: 30, color: tokens.onAccent)),
    );
    final src = url;
    if (src == null || !src.startsWith('https://')) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        src,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Product row/tile shared by `product_list`, `product_card`, and the vendor
/// menu screen. Prices always render in mono.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.tokens,
    this.compact = false,
    this.onTap,
    this.onAdd,
  });

  final Product product;
  final HubbleTokens tokens;
  final bool compact;
  final ProductTapHandler? onTap;
  final ProductTapHandler? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final price = Text(
      formatCents(product.priceCents, currency: product.currency),
      style: HubbleType.mono(size: 14, color: t.accent, weight: FontWeight.w700),
    );
    final name = Text(
      product.name,
      style: HubbleType.display(size: compact ? 16 : 18, color: t.onCanvas),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final add = onAdd == null
        ? null
        : IconButton(
            tooltip: 'Add to cart',
            onPressed: product.isAvailable ? () => onAdd!(product) : null,
            icon: Icon(Icons.add_box, color: product.isAvailable ? t.accent : t.iron),
          );
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(product),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.iron),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: name),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [price, ?add]),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name,
                          if (product.description != null && product.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                product.description!,
                                style: HubbleType.body(size: 13, color: t.onCanvas.withValues(alpha: 0.8)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 6),
                          price,
                        ],
                      ),
                    ),
                    if (!product.isAvailable)
                      Text(
                        'SOLD OUT',
                        style: HubbleType.mono(size: 11, color: t.alert, weight: FontWeight.w700),
                      )
                    else
                      ?add,
                  ],
                ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
