import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_repository.dart';
import 'supabase_auth_repository.dart';
import 'unconfigured_auth_repository.dart';

Future<AuthRepository> createAuthRepository({
  required String supabaseUrl,
  required String publishableKey,
}) async {
  if (supabaseUrl.isEmpty || publishableKey.isEmpty) {
    return const UnconfiguredAuthRepository();
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: publishableKey);
  return SupabaseAuthRepository(Supabase.instance.client);
}
