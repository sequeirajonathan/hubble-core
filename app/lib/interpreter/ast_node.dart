/// Storefront layout AST — the Dart mirror of
/// backend/supabase/functions/_shared/ast.ts and `layout_ast_is_valid()`.
///
/// The interpreter never executes anything: it walks this tree and maps each
/// node to a native widget. Unknown node types are rejected at parse time so
/// a bad row degrades to an error card, not a crash.
library;

enum NodeType {
  screen('screen', container: true),
  column('column', container: true),
  row('row', container: true),
  stack('stack', container: true),
  spacer('spacer'),
  divider('divider'),
  text('text'),
  image('image'),
  hero('hero'),
  badge('badge'),
  button('button'),
  productList('product_list'),
  productCard('product_card'),
  hours('hours'),
  mapPin('map_pin'),
  contact('contact');

  const NodeType(this.wire, {this.container = false});

  final String wire;
  final bool container;

  static NodeType? fromWire(String? wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

const int kMaxAstDepth = 24;
const int kMaxAstChildren = 200;

const List<String> kBindPaths = [
  'vendor.name',
  'vendor.tagline',
  'vendor.logo_url',
  'vendor.address_text',
  'vendor.phone',
  'vendor.website_url',
  'vendor.hours_text',
  'vendor.rating',
  'vendor.review_count',
  'vendor.products',
];

const List<String> kButtonActions = ['open_cart', 'call', 'directions', 'open_url', 'scroll_to'];

class LayoutValidationException implements Exception {
  LayoutValidationException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'LayoutValidationException($path: $message)';
}

/// A prop referencing runtime data, e.g. `{"$bind": "vendor.logo_url"}`.
class BindRef {
  const BindRef(this.path);

  final String path;

  @override
  bool operator ==(Object other) => other is BindRef && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A prop referencing a theme token, e.g. `{"$token": "accent"}`.
class TokenRef {
  const TokenRef(this.key);

  final String key;

  @override
  bool operator ==(Object other) => other is TokenRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class LayoutNode {
  const LayoutNode({required this.type, this.props = const {}, this.children = const []});

  final NodeType type;
  final Map<String, Object?> props;
  final List<LayoutNode> children;

  /// Parses and validates a whole tree. Throws [LayoutValidationException].
  static LayoutNode parse(Object? json) => _parse(json, r'$', 0);

  static LayoutNode _parse(Object? json, String path, int depth) {
    if (depth > kMaxAstDepth) {
      throw LayoutValidationException(path, 'nesting deeper than $kMaxAstDepth');
    }
    if (json is! Map) throw LayoutValidationException(path, 'node must be an object');
    final rawType = json['type'];
    final type = rawType is String ? NodeType.fromWire(rawType) : null;
    if (type == null) throw LayoutValidationException(path, 'unknown node type $rawType');
    if (depth == 0 && type != NodeType.screen) {
      throw LayoutValidationException(path, 'root node must be a screen');
    }
    if (depth > 0 && type == NodeType.screen) {
      throw LayoutValidationException(path, 'screen may only appear at the root');
    }

    final rawProps = json['props'];
    if (rawProps != null && rawProps is! Map) {
      throw LayoutValidationException('$path.props', 'props must be an object');
    }
    final props = <String, Object?>{};
    if (rawProps is Map) {
      for (final entry in rawProps.entries) {
        props[entry.key.toString()] = _parseProp(entry.value, '$path.props.${entry.key}');
      }
    }
    _validateProps(type, props, '$path.props');

    final rawChildren = json['children'];
    final children = <LayoutNode>[];
    if (rawChildren != null) {
      if (rawChildren is! List) {
        throw LayoutValidationException('$path.children', 'children must be an array');
      }
      if (!type.container) {
        throw LayoutValidationException('$path.children', '${type.wire} cannot have children');
      }
      if (rawChildren.length > kMaxAstChildren) {
        throw LayoutValidationException('$path.children', 'more than $kMaxAstChildren children');
      }
      for (var i = 0; i < rawChildren.length; i++) {
        children.add(_parse(rawChildren[i], '$path.children[$i]', depth + 1));
      }
    }
    return LayoutNode(type: type, props: props, children: children);
  }

  static Object? _parseProp(Object? value, String path) {
    if (value is Map) {
      if (value.containsKey(r'$bind')) {
        final bind = value[r'$bind'];
        if (bind is! String || !kBindPaths.contains(bind)) {
          throw LayoutValidationException(path, 'unknown bind path $bind');
        }
        return BindRef(bind);
      }
      if (value.containsKey(r'$token')) {
        final token = value[r'$token'];
        if (token is! String) throw LayoutValidationException(path, r'$token must be a string');
        return TokenRef(token);
      }
      return Map<String, Object?>.fromEntries(value.entries.map((e) => MapEntry(e.key.toString(), e.value)));
    }
    if (value is List) return List<Object?>.unmodifiable(value);
    return value;
  }

  static void _validateProps(NodeType type, Map<String, Object?> props, String path) {
    if (type == NodeType.button) {
      final action = props['action'];
      if (action != null && !kButtonActions.contains(action)) {
        throw LayoutValidationException('$path.action', 'unknown button action $action');
      }
      if (action == 'open_url') {
        final url = props['url'];
        if (url is! String || !url.startsWith('https://')) {
          throw LayoutValidationException('$path.url', 'open_url requires an https URL');
        }
      }
    }
    if (type == NodeType.image) {
      final src = props['src'];
      if (src is String && !src.startsWith('https://')) {
        throw LayoutValidationException('$path.src', 'image src must be https');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'type': type.wire,
    if (props.isNotEmpty) 'props': _propsToJson(props),
    if (children.isNotEmpty) 'children': children.map((c) => c.toJson()).toList(),
  };

  static Map<String, Object?> _propsToJson(Map<String, Object?> props) => {
    for (final e in props.entries)
      e.key: switch (e.value) {
        BindRef(:final path) => {r'$bind': path},
        TokenRef(:final key) => {r'$token': key},
        final other => other,
      },
  };

  int get nodeCount => 1 + children.fold(0, (sum, c) => sum + c.nodeCount);
}
