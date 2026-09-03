import 'dart:ui';

import '../core/theme/tokens.dart';
import 'ast_node.dart';
import 'storefront_data.dart';

/// Resolves prop values: `{"$token": key}` → [Color], `{"$bind": path}` → data,
/// and everything else passes through.
class TokenBinder {
  const TokenBinder({required this.tokens, required this.data});

  final HubbleTokens tokens;
  final StorefrontData data;

  Object? value(Object? raw) => switch (raw) {
    TokenRef(:final key) => tokens.byKey(key),
    BindRef(:final path) => data.resolve(path),
    _ => raw,
  };

  String? string(Map<String, Object?> props, String key, {String? fallback}) {
    final v = value(props[key]);
    if (v == null) return fallback;
    if (v is String) return v.isEmpty ? fallback : v;
    if (v is num) return v.toString();
    return fallback;
  }

  double? number(Map<String, Object?> props, String key, {double? fallback}) {
    final v = value(props[key]);
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  bool boolean(Map<String, Object?> props, String key, {bool fallback = false}) {
    final v = value(props[key]);
    return v is bool ? v : fallback;
  }

  Color? color(Map<String, Object?> props, String key, {Color? fallback}) {
    final raw = props[key];
    if (raw is TokenRef) return tokens.byKey(raw.key);
    if (raw is String) return parseHexColor(raw) ?? fallback;
    return fallback;
  }
}
