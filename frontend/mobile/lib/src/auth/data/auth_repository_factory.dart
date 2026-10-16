import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_repository.dart';
import 'secure_session_local_storage.dart';
import 'supabase_auth_repository.dart';
import 'unconfigured_auth_repository.dart';

Future<AuthRepository> createAuthRepository({
  required String supabaseUrl,
  required String publishableKey,
}) async {
  if (supabaseUrl.isEmpty || publishableKey.isEmpty) {
    return const UnconfiguredAuthRepository();
  }

  final authOptions = kIsWeb
      ? const FlutterAuthClientOptions(
          persistSession: true,
          autoRefreshToken: true,
        )
      : FlutterAuthClientOptions(
          persistSession: true,
          autoRefreshToken: true,
          localStorage: SecureSessionLocalStorage(
            persistSessionKey:
                'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
            secureStore: FlutterSecureSessionSecretStore(
              const FlutterSecureStorage(),
            ),
            legacyStore: await SharedPreferencesLegacySessionStore.create(),
          ),
        );

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: publishableKey,
    authOptions: authOptions,
  );
  return SupabaseAuthRepository(Supabase.instance.client);
}
