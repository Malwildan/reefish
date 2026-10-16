import 'package:flutter/material.dart';

import 'src/app/reefish_app.dart';
import 'src/auth/data/auth_repository_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const initialPageName = String.fromEnvironment(
    'INITIAL_PAGE',
    defaultValue: 'splash',
  );
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const previewSafeArea = bool.fromEnvironment('PREVIEW_SAFE_AREA');
  final authRepository = await createAuthRepository(
    supabaseUrl: supabaseUrl,
    publishableKey: publishableKey,
  );
  runApp(
    ReefishApp(
      authRepository: authRepository,
      initialPage: ReefishInitialPageName.fromName(initialPageName),
      previewSafeArea: previewSafeArea,
    ),
  );
}
