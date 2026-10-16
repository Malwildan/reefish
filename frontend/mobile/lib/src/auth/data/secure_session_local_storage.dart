import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SessionSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract interface class LegacySessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureSessionSecretStore implements SessionSecretStore {
  FlutterSecureSessionSecretStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SharedPreferencesLegacySessionStore implements LegacySessionStore {
  SharedPreferencesLegacySessionStore(this._preferences);

  final SharedPreferences _preferences;

  static Future<SharedPreferencesLegacySessionStore> create() async =>
      SharedPreferencesLegacySessionStore(
        await SharedPreferences.getInstance(),
      );

  @override
  Future<String?> read(String key) async => _preferences.getString(key);

  @override
  Future<void> delete(String key) async {
    if (!await _preferences.remove(key)) {
      throw StateError('Could not remove legacy session data.');
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (!await _preferences.setString(key, value)) {
      throw StateError('Could not persist session migration state.');
    }
  }
}

/// Supabase session storage that migrates the SDK's previous native key.
///
/// All operations share a queue because Supabase invokes persistence without
/// awaiting it; an older in-flight write must finish before a later logout
/// removes the session.
class SecureSessionLocalStorage extends LocalStorage {
  SecureSessionLocalStorage({
    required this.persistSessionKey,
    required SessionSecretStore secureStore,
    required LegacySessionStore legacyStore,
  }) : _secureStore = secureStore,
       _legacyStore = legacyStore;

  final String persistSessionKey;
  final SessionSecretStore _secureStore;
  final LegacySessionStore _legacyStore;

  Future<void> _operations = Future<void>.value();
  bool _initialized = false;
  String? _legacyFallback;
  bool _preferLegacyFallback = false;

  String get _migrationMarkerKey => '$persistSessionKey-migration-pending';

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  @override
  Future<void> initialize() => _enqueue(() async {
    if (_initialized) return;

    final migrationPending =
        await _legacyStore.read(_migrationMarkerKey) == 'pending';
    final secureSession = await _secureStore.read(persistSessionKey);
    final legacySession = await _legacyStore.read(persistSessionKey);

    if (migrationPending && legacySession != null) {
      _legacyFallback = legacySession;
      _preferLegacyFallback = true;
      await _migrateLegacySession(legacySession);
    } else if (secureSession != null) {
      await _legacyStore.delete(persistSessionKey);
      await _legacyStore.delete(_migrationMarkerKey);
    } else if (legacySession != null) {
      _legacyFallback = legacySession;
      _preferLegacyFallback = true;
      await _legacyStore.write(_migrationMarkerKey, 'pending');
      await _migrateLegacySession(legacySession);
    }
    _initialized = true;
  });

  Future<void> _migrateLegacySession(String legacySession) async {
    String? readBack;
    try {
      await _secureStore.write(persistSessionKey, legacySession);
      readBack = await _secureStore.read(persistSessionKey);
    } catch (_) {
      // Keep the legacy value and migration marker until secure readback works.
      await _removeUnverifiedSecureSession();
      return;
    }
    if (readBack != legacySession) {
      await _removeUnverifiedSecureSession();
      return;
    }
    try {
      await _legacyStore.delete(persistSessionKey);
      await _legacyStore.delete(_migrationMarkerKey);
      _legacyFallback = null;
      _preferLegacyFallback = false;
    } catch (_) {
      // A verified secure copy is authoritative; leftover legacy data is safe.
    }
  }

  Future<void> _removeUnverifiedSecureSession() async {
    try {
      await _secureStore.delete(persistSessionKey);
    } catch (_) {
      // The durable marker keeps legacy data authoritative on the next launch.
    }
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() => _enqueue(() async {
    await _ensureInitialized();
    if (_preferLegacyFallback) return _legacyFallback;
    final secureSession = await _secureStore.read(persistSessionKey);
    return secureSession ?? _legacyFallback;
  });

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      // initialize cannot be called from inside a queued operation. This
      // method is only reached after initialize() from Supabase's lifecycle.
      throw StateError('Secure session storage has not been initialized.');
    }
  }

  @override
  Future<void> removePersistedSession() => _enqueue(() async {
    await _ensureInitialized();
    try {
      await _secureStore.delete(persistSessionKey);
    } finally {
      await _legacyStore.delete(persistSessionKey);
      await _legacyStore.delete(_migrationMarkerKey);
      _legacyFallback = null;
      _preferLegacyFallback = false;
    }
  });

  @override
  Future<void> persistSession(String persistSessionString) =>
      _enqueue(() async {
        await _ensureInitialized();
        final legacySession = await _legacyStore.read(persistSessionKey);
        if (legacySession != null) {
          await _legacyStore.write(_migrationMarkerKey, 'pending');
          _legacyFallback = legacySession;
          _preferLegacyFallback = true;
        }
        await _secureStore.write(persistSessionKey, persistSessionString);
        final readBack = await _secureStore.read(persistSessionKey);
        if (readBack != persistSessionString) {
          throw StateError('Secure session persistence did not verify.');
        }
        try {
          await _legacyStore.delete(persistSessionKey);
          await _legacyStore.delete(_migrationMarkerKey);
          _legacyFallback = null;
          _preferLegacyFallback = false;
        } catch (_) {
          // The pending marker keeps the legacy value authoritative on reopen.
        }
      });
}
