import 'package:flutter/material.dart';

import 'src/app/reefish_app.dart';
import 'src/auth/data/unconfigured_auth_repository.dart';

void main() {
  const initialPageName = String.fromEnvironment(
    'INITIAL_PAGE',
    defaultValue: 'splash',
  );
  const previewSafeArea = bool.fromEnvironment('PREVIEW_SAFE_AREA');
  runApp(
    ReefishApp(
      authRepository: const UnconfiguredAuthRepository(),
      initialPage: ReefishInitialPageName.fromName(initialPageName),
      previewSafeArea: previewSafeArea,
    ),
  );
}
