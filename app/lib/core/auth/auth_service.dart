import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';

/// Unified sign-on: one identity for shoppers and vendors.
///
/// Both entry points (email magic link, phone OTP) end in the same JWT, so a
/// user who later creates a vendor never re-authenticates.
class AuthService {
  AuthService(this._auth);

  final GoTrueClient _auth;

  Stream<AuthState> get changes => _auth.onAuthStateChange;

  Session? get currentSession => _auth.currentSession;

  User? get currentUser => _auth.currentUser;

  Future<void> sendMagicLink(String email) {
    return _auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: Env.authRedirect,
      shouldCreateUser: true,
    );
  }

  Future<void> sendPhoneCode(String phoneE164) {
    return _auth.signInWithOtp(phone: phoneE164.trim(), shouldCreateUser: true);
  }

  Future<AuthResponse> verifyPhoneCode({required String phoneE164, required String code}) {
    return _auth.verifyOTP(type: OtpType.sms, phone: phoneE164.trim(), token: code.trim());
  }

  Future<AuthResponse> verifyEmailCode({required String email, required String code}) {
    return _auth.verifyOTP(type: OtpType.email, email: email.trim(), token: code.trim());
  }

  Future<void> signOut() => _auth.signOut();
}
