import 'package:flutter/material.dart';
import 'package:reefish_mobile/src/app/reefish_app.dart';
import 'package:reefish_mobile/src/auth/data/auth_repository_factory.dart';
import 'package:reefish_mobile/src/map/data/demo_grid_policy_repository.dart';

/// Browser-only review entry point; the production entry point is lib/main.dart.
/// `?screen=departure&demo-grid-locks=1` uses explicit example grid locks.
/// Production policy reads never fall back to these local examples.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final authRepository = await createAuthRepository(
    supabaseUrl: supabaseUrl,
    publishableKey: publishableKey,
  );
  runApp(
    ColoredBox(
      color: const Color(0xFFE5ECEE),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 932),
          child: ReefishApp(
            authRepository: authRepository,
            initialPage: ReefishInitialPageName.fromName(
              Uri.base.queryParameters['screen'] ?? 'splash',
            ),
            previewSafeArea: true,
            gridPolicyRepository:
                Uri.base.queryParameters['demo-grid-locks'] == '1'
                ? DemoGridPolicyRepository()
                : null,
          ),
        ),
      ),
    ),
  );
}
