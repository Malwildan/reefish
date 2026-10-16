import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/auth/data/secure_session_local_storage.dart';

const key = 'sb-project-auth-token';

void main() {
  group('SecureSessionLocalStorage', () {
    test('migrates legacy session only after secure write readback', () async {
      final secure = _MemorySecretStore();
      final legacy = _MemoryLegacyStore()..values[key] = 'legacy-session';
      final storage = _storage(secure, legacy);

      await storage.initialize();

      expect(secure.values[key], 'legacy-session');
      expect(legacy.values, isEmpty);
      expect(await storage.accessToken(), 'legacy-session');
    });

    test('retains legacy session when secure migration write fails', () async {
      final secure = _MemorySecretStore()..failWrites = true;
      final legacy = _MemoryLegacyStore()..values[key] = 'legacy-session';
      final storage = _storage(secure, legacy);

      await storage.initialize();

      expect(legacy.values[key], 'legacy-session');
      expect(await storage.accessToken(), 'legacy-session');
    });

    test(
      'retains legacy session when secure migration readback fails',
      () async {
        final secure = _MemorySecretStore()..failedReadOnCall = 2;
        final legacy = _MemoryLegacyStore()..values[key] = 'legacy-session';
        final storage = _storage(secure, legacy);

        await storage.initialize();

        expect(legacy.values[key], 'legacy-session');
        expect(await storage.accessToken(), 'legacy-session');
      },
    );

    test(
      'reopened storage keeps legacy authoritative after mismatched readback',
      () async {
        final secure = _MemorySecretStore()
          ..mismatchedWrites = true
          ..failDeletes = true;
        final legacy = _MemoryLegacyStore()..values[key] = 'legacy-session';
        final storage = _storage(secure, legacy);
        await storage.initialize();

        expect(await storage.accessToken(), 'legacy-session');
        expect(legacy.values[key], 'legacy-session');

        secure.mismatchedWrites = false;
        final reopened = _storage(secure, legacy);
        await reopened.initialize();

        expect(await reopened.accessToken(), 'legacy-session');
        expect(legacy.values[key], isNull);
      },
    );

    test(
      'existing secure session wins and removes stale legacy copy',
      () async {
        final secure = _MemorySecretStore()..values[key] = 'secure-session';
        final legacy = _MemoryLegacyStore()..values[key] = 'stale-session';
        final storage = _storage(secure, legacy);

        await storage.initialize();

        expect(await storage.accessToken(), 'secure-session');
        expect(legacy.values, isEmpty);
      },
    );

    test('reopened storage reads existing secure session', () async {
      final secure = _MemorySecretStore()..values[key] = 'persisted-session';
      final legacy = _MemoryLegacyStore();
      final reopened = _storage(secure, legacy);

      await reopened.initialize();

      expect(await reopened.hasAccessToken(), isTrue);
      expect(await reopened.accessToken(), 'persisted-session');
    });

    test(
      'replacement persists current session and removes legacy value',
      () async {
        final secure = _MemorySecretStore()..values[key] = 'old-session';
        final legacy = _MemoryLegacyStore()..values[key] = 'stale-session';
        final storage = _storage(secure, legacy);
        await storage.initialize();

        await storage.persistSession('refreshed-session');

        expect(await storage.accessToken(), 'refreshed-session');
        expect(legacy.values, isEmpty);
      },
    );

    test(
      'logout waits for an in-flight session write before removing it',
      () async {
        final secure = _MemorySecretStore()..writeGate = Completer<void>();
        final legacy = _MemoryLegacyStore();
        final storage = _storage(secure, legacy);
        await storage.initialize();

        final write = storage.persistSession('session-before-logout');
        final logout = storage.removePersistedSession();
        await Future<void>.delayed(Duration.zero);
        expect(secure.values[key], isNull);

        secure.writeGate!.complete();
        await Future.wait([write, logout]);

        expect(secure.values, isEmpty);
        expect(legacy.values, isEmpty);
        expect(await storage.hasAccessToken(), isFalse);
      },
    );

    test('failed write does not prevent a later logout', () async {
      final secure = _MemorySecretStore();
      final legacy = _MemoryLegacyStore();
      final storage = _storage(secure, legacy);
      await storage.initialize();
      secure.failWrites = true;

      await expectLater(
        storage.persistSession('new-session'),
        throwsStateError,
      );
      await storage.removePersistedSession();

      expect(await storage.hasAccessToken(), isFalse);
    });

    test('remove clears both stores', () async {
      final secure = _MemorySecretStore()..values[key] = 'secure-session';
      final legacy = _MemoryLegacyStore()..values[key] = 'legacy-session';
      final storage = _storage(secure, legacy);
      await storage.initialize();

      await storage.removePersistedSession();

      expect(secure.values, isEmpty);
      expect(legacy.values, isEmpty);
    });
  });
}

SecureSessionLocalStorage _storage(
  _MemorySecretStore secure,
  _MemoryLegacyStore legacy,
) => SecureSessionLocalStorage(
  persistSessionKey: key,
  secureStore: secure,
  legacyStore: legacy,
);

class _MemorySecretStore implements SessionSecretStore {
  final Map<String, String> values = {};
  bool failWrites = false;
  bool mismatchedWrites = false;
  bool failDeletes = false;
  int failedReadOnCall = -1;
  int readCalls = 0;
  Completer<void>? writeGate;

  @override
  Future<String?> read(String key) async {
    readCalls += 1;
    if (readCalls == failedReadOnCall) {
      throw StateError('read failure');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (writeGate != null) await writeGate!.future;
    if (failWrites) throw StateError('write failure');
    values[key] = mismatchedWrites ? '$value-mismatch' : value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('delete failure');
    values.remove(key);
  }
}

class _MemoryLegacyStore implements LegacySessionStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
