import 'dart:ui';

/// Industrial Bolt color matrix. These are the host defaults; a vendor's
/// storefront may override any key in [overridableKeys] (validated by
/// `theme_tokens_are_valid()` in the database and again here).
class HubbleTokens {
  const HubbleTokens({
    this.canvas = const Color(0xFF1A1A1A),
    this.surface = const Color(0xFF222222),
    this.accent = const Color(0xFFFF7A00),
    this.iron = const Color(0xFF4A4A4A),
    this.alert = const Color(0xFFFF3B30),
    this.onAccent = const Color(0xFF1A1A1A),
    this.onCanvas = const Color(0xFFF2F2F2),
  });

  /// Scaffold Canvas: flat matte black foundation.
  final Color canvas;

  /// Container Surface: obsidian layer framing vendor cards.
  final Color surface;

  /// Primary Active Accent: Safety Amber. Actions, selection rings, checkout.
  final Color accent;

  /// Secondary Text/Borders: Dark Iron.
  final Color iron;

  /// Semantic Alert: Alert Red. Dangerous actions, failures, sold out.
  final Color alert;

  final Color onAccent;
  final Color onCanvas;

  static const host = HubbleTokens();

  static const overridableKeys = ['canvas', 'surface', 'accent', 'iron', 'alert', 'on_accent', 'on_canvas'];

  Color byKey(String key) => switch (key) {
    'canvas' => canvas,
    'surface' => surface,
    'accent' => accent,
    'iron' => iron,
    'alert' => alert,
    'on_accent' => onAccent,
    'on_canvas' => onCanvas,
    _ => accent,
  };

  /// Applies a vendor override map (`{"accent": "#00AAFF"}`). Unknown keys and
  /// malformed colors are ignored so a bad row can never break rendering.
  HubbleTokens merge(Map<String, dynamic>? overrides) {
    if (overrides == null || overrides.isEmpty) return this;
    Color pick(String key, Color fallback) {
      final raw = overrides[key];
      return raw is String ? (parseHexColor(raw) ?? fallback) : fallback;
    }

    return HubbleTokens(
      canvas: pick('canvas', canvas),
      surface: pick('surface', surface),
      accent: pick('accent', accent),
      iron: pick('iron', iron),
      alert: pick('alert', alert),
      onAccent: pick('on_accent', onAccent),
      onCanvas: pick('on_canvas', onCanvas),
    );
  }

  Map<String, String> toJson() => {
    'canvas': toHex(canvas),
    'surface': toHex(surface),
    'accent': toHex(accent),
    'iron': toHex(iron),
    'alert': toHex(alert),
    'on_accent': toHex(onAccent),
    'on_canvas': toHex(onCanvas),
  };

  /// Only the keys that differ from the host defaults, for storing a draft.
  Map<String, String> diffFromHost() {
    final mine = toJson();
    final base = host.toJson();
    return {
      for (final entry in mine.entries)
        if (entry.value != base[entry.key]) entry.key: entry.value,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is HubbleTokens &&
      other.canvas == canvas &&
      other.surface == surface &&
      other.accent == accent &&
      other.iron == iron &&
      other.alert == alert &&
      other.onAccent == onAccent &&
      other.onCanvas == onCanvas;

  @override
  int get hashCode => Object.hash(canvas, surface, accent, iron, alert, onAccent, onCanvas);
}

final _hex = RegExp(r'^#([0-9A-Fa-f]{6})$');

/// Parses `#RRGGBB`; returns null for anything else.
Color? parseHexColor(String value) {
  final match = _hex.firstMatch(value.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

String toHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
