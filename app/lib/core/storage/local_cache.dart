import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../auth/session_controller.dart';

/// Thin persistence layer for small, non-sensitive state: the chosen
/// viewport, the last rendered layout per vendor (for instant re-open) and
/// draft carts. Tokens/JWTs are handled by supabase_flutter, never here.
class LocalCache {
  LocalCache(this._prefs);

  static Future<LocalCache> open() async => LocalCache(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _modeKey = 'viewport_mode';
  static const _layoutPrefix = 'layout:';
  static const _cartKey = 'carts';

  ViewportMode? readViewportMode() {
    final raw = _prefs.getString(_modeKey);
    if (raw == null) return null;
    return ViewportMode.values.cast<ViewportMode?>().firstWhere((m) => m!.name == raw, orElse: () => null);
  }

  Future<void> writeViewportMode(ViewportMode mode) => _prefs.setString(_modeKey, mode.name);

  Map<String, dynamic>? readLayout(String vendorId) {
    final raw = _prefs.getString('$_layoutPrefix$vendorId');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLayout(String vendorId, Map<String, dynamic> layout) =>
      _prefs.setString('$_layoutPrefix$vendorId', jsonEncode(layout));

  Map<String, dynamic>? readCarts() {
    final raw = _prefs.getString(_cartKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCarts(Map<String, dynamic> carts) => _prefs.setString(_cartKey, jsonEncode(carts));
}
