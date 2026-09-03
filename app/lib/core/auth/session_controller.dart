import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../models/vendor.dart';
import '../storage/local_cache.dart';
import 'auth_service.dart';

/// Which side of the app the user is currently looking at. The identity is
/// the same; only the viewport changes.
enum ViewportMode { shopper, vendor }

/// Holds the signed-in identity, its profile and vendor memberships, and the
/// viewport the user has chosen. The router listens to this.
class SessionController extends ChangeNotifier {
  SessionController({required AuthService auth, required SupabaseClient db, required LocalCache cache})
    : this._(auth, db, cache);

  SessionController._(this._auth, this._db, this._cache) {
    _sub = _auth.changes.listen(_onAuthChange);
    _session = _auth.currentSession;
    _mode = _cache.readViewportMode() ?? ViewportMode.shopper;
    if (_session != null) unawaited(refresh());
  }

  final AuthService _auth;
  final SupabaseClient _db;
  final LocalCache _cache;
  late final StreamSubscription<AuthState> _sub;

  Session? _session;
  Profile? _profile;
  List<VendorMembership> _memberships = const [];
  ViewportMode _mode = ViewportMode.shopper;
  bool _loading = false;

  Session? get session => _session;
  Profile? get profile => _profile;
  List<VendorMembership> get memberships => _memberships;
  bool get isSignedIn => _session != null;
  bool get hasVendorRole => _memberships.isNotEmpty;
  bool get loading => _loading;
  String? get userId => _session?.user.id;

  /// Effective viewport: vendor mode requires at least one membership.
  ViewportMode get mode =>
      _mode == ViewportMode.vendor && hasVendorRole ? ViewportMode.vendor : ViewportMode.shopper;

  Future<void> setMode(ViewportMode mode) async {
    _mode = mode;
    await _cache.writeViewportMode(mode);
    notifyListeners();
  }

  void _onAuthChange(AuthState state) {
    _session = state.session;
    if (_session == null) {
      _profile = null;
      _memberships = const [];
      _mode = ViewportMode.shopper;
      notifyListeners();
    } else if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession ||
        state.event == AuthChangeEvent.userUpdated) {
      unawaited(refresh());
    } else {
      notifyListeners();
    }
  }

  /// Reloads profile + memberships. Safe to call after creating a vendor so
  /// the vendor hub unlocks without a new sign-in.
  Future<void> refresh() async {
    final uid = userId;
    if (uid == null) return;
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        _db.from('profiles').select().eq('id', uid).maybeSingle(),
        _db
            .from('vendor_members')
            .select('role, vendors(id, name, slug, niche, logo_url, is_live)')
            .eq('user_id', uid),
      ]);
      final profileRow = results[0] as Map<String, dynamic>?;
      final memberRows = (results[1] as List).cast<Map<String, dynamic>>();
      _profile = profileRow == null ? null : Profile.fromJson(profileRow);
      _memberships = memberRows
          .where((r) => r['vendors'] != null)
          .map(VendorMembership.fromJoinRow)
          .toList(growable: false);
    } catch (err, stack) {
      debugPrint('session refresh failed: $err\n$stack');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
