import 'package:flutter/material.dart';
import 'package:reefish_mobile/src/app/reefish_app.dart';
import 'package:reefish_mobile/src/auth/data/unconfigured_auth_repository.dart';

/// Browser-only review entry point; the production entry point is lib/main.dart.
/// `?screen=welcome|signup|login|splash` selects a screen without fake auth.
void main() {
  runApp(ColoredBox(
    color: const Color(0xFFE5ECEE),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 932),
        child: ReefishApp(
          authRepository: const UnconfiguredAuthRepository(),
          initialPage: ReefishInitialPageName.fromName(
            Uri.base.queryParameters['screen'] ?? 'splash',
          ),
          previewSafeArea: true,
        ),
      ),
    ),
  ));
}
