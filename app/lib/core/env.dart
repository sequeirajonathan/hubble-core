/// Build-time configuration. Values are injected with `--dart-define` (see
/// the distribution workflows) so no secrets live in the repository.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:54321');

  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Deep link the auth email / SMS flow returns to.
  static const authRedirect = String.fromEnvironment('AUTH_REDIRECT', defaultValue: 'hubble://auth-callback');

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;
}
