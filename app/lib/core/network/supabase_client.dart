import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';

/// Single network entry point. Everything in the app talks to Supabase
/// through [db]; edge functions through [functions].
class HubbleBackend {
  const HubbleBackend._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
  }

  static SupabaseClient get db => Supabase.instance.client;

  static FunctionsClient get functions => db.functions;

  static GoTrueClient get auth => db.auth;
}
