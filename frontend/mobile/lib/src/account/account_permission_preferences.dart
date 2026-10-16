import 'package:shared_preferences/shared_preferences.dart';

/// Local, account-scoped preference for allowing location recording.
///
/// This value records the user's product choice. The operating-system
/// permission must still be checked independently before reading location.
abstract interface class AccountPermissionPreferences {
  Future<bool> trackingAllowed(String ownerId);

  Future<void> setTrackingAllowed(String ownerId, bool allowed);

  Future<bool> termsAccepted(String ownerId);

  Future<void> setTermsAccepted(String ownerId, bool accepted);
}

class SharedPreferencesAccountPermissionPreferences
    implements AccountPermissionPreferences {
  const SharedPreferencesAccountPermissionPreferences({
    required this.preferences,
  });

  final SharedPreferences preferences;

  static String _key(String ownerId) =>
      'reefish.account.permissions.v1.${Uri.encodeComponent(ownerId)}.tracking_allowed';
  static String _termsKey(String ownerId) =>
      'reefish.account.permissions.v1.${Uri.encodeComponent(ownerId)}.terms_accepted';

  @override
  Future<bool> trackingAllowed(String ownerId) async =>
      preferences.getBool(_key(ownerId)) ?? false;

  @override
  Future<void> setTrackingAllowed(String ownerId, bool allowed) async {
    final stored = await preferences.setBool(_key(ownerId), allowed);
    if (!stored) {
      throw StateError('Could not save the location preference.');
    }
  }

  @override
  Future<bool> termsAccepted(String ownerId) async =>
      preferences.getBool(_termsKey(ownerId)) ?? false;

  @override
  Future<void> setTermsAccepted(String ownerId, bool accepted) async {
    final stored = await preferences.setBool(_termsKey(ownerId), accepted);
    if (!stored) {
      throw StateError('Could not save the terms preference.');
    }
  }
}

abstract interface class LocationPermissionAdapter {
  Future<bool> isGranted();

  Future<bool> request();
}
