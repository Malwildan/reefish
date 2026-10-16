import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sailing_session.dart';
import '../domain/sailing_session_store.dart';

/// One foreground session per account. Writes and clears are serialized so a
/// late location callback cannot overwrite a newer session snapshot.
class SharedPreferencesSailingSessionStore implements SailingSessionStore {
  SharedPreferencesSailingSessionStore({
    required SharedPreferences preferences,
    required String ownerId,
  }) : _preferences = preferences,
       _ownerId = ownerId,
       _key = 'reefish.sailing-session.v1.$ownerId' {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must not be empty');
    }
  }

  final SharedPreferences _preferences;
  final String _ownerId;
  final String _key;
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  @override
  Future<SailingSession?> read() => _serialized(() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Expected an object');
      final session = SailingSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (session.ownerId != _ownerId) {
        throw const FormatException(
          'Stored session belongs to another account',
        );
      }
      return session;
    } catch (error) {
      throw SailingStoreFailure(
        'Data sesi berlayar tersimpan tidak valid dan tetap disimpan untuk diperiksa.',
        cause: error,
      );
    }
  });

  @override
  Future<void> save(SailingSession session) => _serialized(() async {
    if (session.ownerId != _ownerId) {
      throw const SailingStoreFailure(
        'Sesi berlayar tidak cocok dengan akun ini.',
      );
    }
    try {
      session.validate();
      final saved = await _preferences.setString(
        _key,
        jsonEncode(session.toJson()),
      );
      if (!saved) throw StateError('Penyimpanan menolak data sesi berlayar.');
    } catch (error) {
      if (error is SailingStoreFailure) rethrow;
      throw SailingStoreFailure(
        'Sesi berlayar tidak dapat disimpan. Perekaman dihentikan agar data tetap akurat.',
        cause: error,
      );
    }
  });

  @override
  Future<void> clear({required String clientTripId}) => _serialized(() async {
    final existing = await _readWithinQueue();
    if (existing == null) return;
    if (existing.clientTripId != clientTripId) {
      throw const SailingStoreFailure(
        'Sesi yang akan dihapus tidak cocok dengan pengiriman yang dikonfirmasi.',
      );
    }
    if (!await _preferences.remove(_key)) {
      throw const SailingStoreFailure('Sesi berlayar tidak dapat dihapus.');
    }
  });

  Future<SailingSession?> _readWithinQueue() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Expected an object');
      final session = SailingSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (session.ownerId != _ownerId) {
        throw const FormatException(
          'Stored session belongs to another account',
        );
      }
      return session;
    } catch (error) {
      throw SailingStoreFailure(
        'Data sesi berlayar tersimpan tidak valid dan tetap disimpan untuk diperiksa.',
        cause: error,
      );
    }
  }
}
