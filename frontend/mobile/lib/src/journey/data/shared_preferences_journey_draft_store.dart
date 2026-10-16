import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/journey_models.dart';
import '../domain/journey_repository.dart';

/// Stores one unsent completed trip for this signed-in account.
/// This is a pending draft slot, not a general offline outbox.
class SharedPreferencesJourneyDraftStore implements JourneyDraftStore {
  SharedPreferencesJourneyDraftStore({
    required SharedPreferences preferences,
    required String ownerId,
  }) : _preferences = preferences,
       _ownerId = ownerId,
       _key = 'reefish.journey-draft.v1.$ownerId' {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must not be empty');
    }
  }

  final SharedPreferences _preferences;
  final String _ownerId;
  final String _key;

  @override
  Future<void> save(JourneyDraft draft) async {
    if (draft.ownerId != _ownerId) {
      throw ArgumentError('Journey draft belongs to another account');
    }
    final encoded = jsonEncode({
      'owner_id': _ownerId,
      'trip': draft.trip.toJson(),
    });
    if (!await _preferences.setString(_key, encoded)) {
      throw const JourneyFailure(
        code: JourneyFailureCode.storage,
        message: 'Could not save the pending journey draft.',
      );
    }
  }

  @override
  Future<JourneyDraft?> read() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Expected an object');
      final json = Map<String, dynamic>.from(decoded);
      if (json['owner_id'] != _ownerId || json['trip'] is! Map) {
        throw const FormatException('Stored draft has invalid account or trip');
      }
      final tripJson = Map<String, dynamic>.from(json['trip'] as Map);
      return JourneyDraft(
        ownerId: _ownerId,
        trip: JourneyTripInput.fromJson(tripJson),
      );
    } catch (error) {
      throw JourneyFailure(
        code: JourneyFailureCode.storage,
        message: 'The pending journey draft is invalid and was preserved.',
        details: error,
      );
    }
  }

  @override
  Future<void> delete() async {
    if (!await _preferences.remove(_key)) {
      throw const JourneyFailure(
        code: JourneyFailureCode.storage,
        message: 'Could not clear the pending journey draft.',
      );
    }
  }
}
